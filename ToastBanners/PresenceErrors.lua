--[[
    Toast Banners - Error Frame & Alert Interception
    UIErrorsFrame hook for "Discovered" and quest text. AlertFrame muting.
    APIs: hooksecurefunc, UIErrorsFrame, AlertFrame.
]]

local _, addon = ...
if not addon or not addon.Presence then return end
local L = addon.L
-- ============================================================================
-- Private helpers
-- ============================================================================

local uiErrorsHooked = false

-- Blizzard's message is only taken away when a banner shows it instead: with the Discovered line or quest progress
-- banners turned off, Blizzard's own text stays
local function ShowsDiscoveryLine()
    local P = addon.Presence
    return addon.GetDB("showPresenceDiscovery", true)
        and (P.IsTypeEnabledForType("ZONE_CHANGE") or P.IsTypeEnabledForType("SUBZONE_CHANGE"))
end

-- A "Discovered" line waiting for its banner is only kept this long: with no banner by then (a subzone with subzone
-- banners off, or the banner already gone) it would land on a later banner for somewhere else
local DISCOVERY_WINDOW = 3
local discoveryTimer
local passThrough = false

-- The area named in Blizzard's message ("Discovered: %s", or "Discovered %s: %d experience gained"), or nil
local function DiscoveredArea(msg)
    for _, fmt in ipairs({ _G.ERR_ZONE_EXPLORED_XP, _G.ERR_ZONE_EXPLORED }) do
        if type(fmt) == "string" then
            local pattern = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "%%d+")
            local name = msg:match("^" .. pattern .. "$")
            if name then return name end
        end
    end
end

local function OnUIErrorsAddMessage(self, msg, r, g, b)
    if passThrough then return end
    local discoveredStr = L["PRESENCE_DISCOVERED"]
    if msg and msg:find(discoveredStr, 1, true) then
        if not ShowsDiscoveryLine() then return end
        addon.Presence.SetPendingDiscovery()
        local phase = addon.Presence.animPhase and addon.Presence.animPhase()
        -- You discover a place as you walk in, usually while the banner for where you just were is still up, and the
        -- new place's banner replaces it a moment later: the line goes on the banner on screen only when that banner
        -- is for the discovered area, and otherwise waits for the new banner
        local area = DiscoveredArea(msg)
        local forThisBanner = not area or (addon.Presence.IsZoneBannerFor and addon.Presence.IsZoneBannerFor(area))
        addon.Trace("discovered %s: banner on screen is for it=%s", tostring(area), tostring(forThisBanner))
        if addon:IsModuleEnabled("presence") and forThisBanner and phase
            and (phase == "entrance" or phase == "hold" or phase == "crossfade") then
            if addon.Presence.ShowDiscoveryLine() then addon.Presence.pendingDiscovery = nil end
        end
        -- too late for its banner (leaving or gone) and no new one on its way: that banner plays again with the line
        if addon.Presence.pendingDiscovery and area and addon:IsModuleEnabled("presence")
            and not (addon.Presence.ZoneBannerWaiting and addon.Presence.ZoneBannerWaiting())
            and addon.Presence.ReplayZoneBannerFor and addon.Presence.ReplayZoneBannerFor(area) then
            addon.Presence.pendingDiscovery = nil
        end
        -- in flight, with Show Discoveries on: the banner hidden for it is shown after all
        if addon.Presence.pendingDiscovery and area and addon:IsModuleEnabled("presence")
            and addon.Presence.PlayHeldZoneBanner and addon.Presence.PlayHeldZoneBanner(area) then
            addon.Presence.pendingDiscovery = nil
        end
        if self.Clear then self:Clear() end
        if discoveryTimer then discoveryTimer:Cancel() end
        discoveryTimer = nil
        if addon.Presence.pendingDiscovery then
            -- No banner took it in time: drop it, and show Blizzard's own message so the discovery isn't missed
            local waits = 0
            local function expire()
                discoveryTimer = nil
                if not addon.Presence.pendingDiscovery then return end
                -- a zone banner still on its way (after a loading screen it waits for loading to end): keep waiting
                if waits < 10 and addon.Presence.ZoneBannerWaiting and addon.Presence.ZoneBannerWaiting() then
                    waits = waits + 1
                    discoveryTimer = C_Timer.NewTimer(DISCOVERY_WINDOW, expire)
                    return
                end
                addon.Presence.pendingDiscovery = nil
                addon.Trace("discovery expired with no banner: %s", msg)
                passThrough = true
                self:AddMessage(msg, r, g, b)
                passThrough = false
            end
            discoveryTimer = C_Timer.NewTimer(DISCOVERY_WINDOW, expire)
        end
        return
    end
    if addon.Presence.IsQuestText and addon.Presence.IsQuestText(msg)
        and addon.Presence.IsTypeEnabledForType("QUEST_UPDATE") then
        if self.Clear then self:Clear() end
    end
end

-- ============================================================================
-- Public functions
-- ============================================================================

-- Hook UIErrorsFrame AddMessage to intercept "Discovered" and quest text. Idempotent.
-- @return nil
local function HookUIErrorsFrame()
    if uiErrorsHooked or not UIErrorsFrame then return end
    if hooksecurefunc then
        hooksecurefunc(UIErrorsFrame, "AddMessage", function(self, msg, r, g, b)
            if not addon:IsModuleEnabled("presence") then return end
            OnUIErrorsAddMessage(self, msg, r, g, b)
        end)
        uiErrorsHooked = true
    end
end

-- Clear hook state. Note: hooksecurefunc cannot be undone; callback no-ops when Presence disabled.
-- @return nil
local function UnhookUIErrorsFrame()
    -- hooksecurefunc cannot be undone; we simply stop acting in the callback when Presence is disabled
    -- The callback will remain but will no-op when addon:IsModuleEnabled("presence") is false
    uiErrorsHooked = false
end

-- ============================================================================
-- ALERT FRAME MUTING
-- ============================================================================

-- AlertFrame events Presence replaces, each paired with the notification type
-- whose option governs it. An event is unregistered only while its type is ON,
-- so switching that type off hands the alert back to Blizzard without needing
-- the whole module disabled. Ordered for deterministic application.
-- Only events AlertFrame itself registers belong here (AlertFrames.lua OnLoad):
-- restoring one it never listened to would hand it an event Blizzard didn't ask for.
-- QUEST_TURNED_IN feeds only WorldQuestCompleteAlertSystem - a regular turn-in
-- never toasts on AlertFrame - so the world quest option governs it.
local ALERT_EVENT_TYPES = {
    { event = "ACHIEVEMENT_EARNED", type = "ACHIEVEMENT" },
    { event = "CRITERIA_EARNED",    type = "ACHIEVEMENT_PROGRESS" },
    { event = "QUEST_TURNED_IN",    type = "WORLD_QUEST" },
}

local alertEventsUnregistered = {}

local function AlertFrameSupportsRegistration()
    return AlertFrame and AlertFrame.RegisterEvent and AlertFrame.UnregisterEvent
end

local function IsAlertTypeEnabled(typeName)
    local P = addon.Presence
    if not (P and P.IsTypeEnabledForType) then return false end
    return P.IsTypeEnabledForType(typeName) and true or false
end

-- Mute or restore each AlertFrame event according to its type's option.
-- Callers gate on the module, not this function: OnEnable runs before EnableModule
-- flags the module on, so an IsModuleEnabled check here would make it a no-op.
-- Idempotent; safe to call on every option change.
-- @return nil
local function ApplyAlertMuting()
    if not AlertFrameSupportsRegistration() then return end
    for _, entry in ipairs(ALERT_EVENT_TYPES) do
        local shouldMute = IsAlertTypeEnabled(entry.type)
        local isMuted = alertEventsUnregistered[entry.event] and true or false
        if shouldMute ~= isMuted then
            -- pcall: AlertFrame methods can throw on some flavours.
            local method = shouldMute and AlertFrame.UnregisterEvent or AlertFrame.RegisterEvent
            local ok, err = pcall(method, AlertFrame, entry.event)
            if ok then
                alertEventsUnregistered[entry.event] = shouldMute or nil
            elseif addon.HSPrint then
                addon.HSPrint("Presence ApplyAlertMuting failed for " .. entry.event .. ": " .. tostring(err))
            end
        end
    end
end

-- True when every AlertFrame event Presence governs is currently muted.
-- Callers that clear AlertFrame wholesale must check this first: once any event
-- is handed back to Blizzard, wiping the queue would swallow the alert instead.
-- @return boolean
local function AreAllAlertsMuted()
    for _, entry in ipairs(ALERT_EVENT_TYPES) do
        if not alertEventsUnregistered[entry.event] then return false end
    end
    return true
end

-- Per-event mute state, read from what was actually (un)registered rather than
-- from the options, so a failed call shows up in the suppression debug dump.
-- @return table Array of { event, type, muted } in application order
local function GetAlertMuteState()
    local out = {}
    for i, entry in ipairs(ALERT_EVENT_TYPES) do
        out[i] = { event = entry.event, type = entry.type, muted = alertEventsUnregistered[entry.event] and true or false }
    end
    return out
end

-- Re-register every muted AlertFrame event when Presence is disabled.
-- @return nil
local function RestoreAlerts()
    if not AlertFrameSupportsRegistration() then return end
    for _, entry in ipairs(ALERT_EVENT_TYPES) do
        if alertEventsUnregistered[entry.event] then
            -- pcall: AlertFrame methods can throw on some flavours.
            local ok, err = pcall(AlertFrame.RegisterEvent, AlertFrame, entry.event)
            if ok then
                alertEventsUnregistered[entry.event] = nil
            elseif addon.HSPrint then
                addon.HSPrint("Presence RestoreAlerts failed for " .. entry.event .. ": " .. tostring(err))
            end
        end
    end
end

-- ============================================================================
-- Exports
-- ============================================================================

addon.Presence.HookUIErrorsFrame   = HookUIErrorsFrame
addon.Presence.UnhookUIErrorsFrame = UnhookUIErrorsFrame
addon.Presence.ApplyAlertMuting    = ApplyAlertMuting
addon.Presence.AreAllAlertsMuted   = AreAllAlertsMuted
addon.Presence.GetAlertMuteState   = GetAlertMuteState
addon.Presence.RestoreAlerts       = RestoreAlerts
