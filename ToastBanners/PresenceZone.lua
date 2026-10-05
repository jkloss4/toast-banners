--[[
    Toast Banners - Zone
    Zone and subzone change notifications. ZONE_CHANGE, SUBZONE_CHANGE.
    APIs: GetZoneText, GetSubZoneText, addon.IsDelveActive, addon.IsInPartyDungeon.
]]

local _, addon = ...
if not addon or not addon.Presence then return end

local ZONE_DEBOUNCE = 0.25
local SUBZONE_DEDUP_TIME = 2.0
local DELVE_TIER_WAIT_INTERVAL = 0.15
local DELVE_TIER_WAIT_MAX = 2.0
-- After a loading screen the game reports the zone several times while it finishes loading; zone events in this
-- window are combined into one banner, shown once it ends
local LOADING_SETTLE_TIME = 2.0
-- A zone banner up to this long after the settle window is for arriving through the loading screen
local ARRIVAL_GRACE = 0.5

-- ============================================================================
-- State
-- ============================================================================

local lastKnownZone = nil
local lastSubzoneTitleShown = nil
local lastSubzoneTitleTime = 0
local pendingDelveZoneTimer = nil
local pendingDelveZoneRetryCount = 0
local loading = true           -- a loading screen is up (the addon loads during the first one)
local settleUntil = 0          -- GetTime() when the window after a loading screen ends
local arrivalUntil = 0         -- GetTime() until which a zone banner is for arriving without walking (spirit release)
local pendingFire = nil        -- the zone banner waiting to be shown
local pendingNewArea = false   -- a new-zone event is waiting to be shown (a later subzone event doesn't replace it)
local placeZone, placeSub       -- where you were at the last zone change a banner was worked out for (shown or not)

-- ============================================================================
-- Helpers
-- ============================================================================

local function Strip(s)
    return addon.Presence.StripMarkup and addon.Presence.StripMarkup(s) or (s or "")
end

-- A "Discovered" line waiting for this banner travels with it, so it shows on this banner even when the banner has to
-- wait in the queue behind another (it was put on whatever banner was on screen)
local function TakeDiscovery(opts)
    if addon.Presence.pendingDiscovery then
        opts.showDiscovery = true
        addon.Presence.pendingDiscovery = nil
    end
    return opts
end

local function ShouldSuppress()
    return addon.Presence.ShouldSuppressType and addon.Presence.ShouldSuppressType()
end

-- Not `a and f() or default`: that returns the default whenever the option is off.
local function IsTypeEnabled(key, fallbackKey, fallbackDefault)
    if not addon.Presence.IsTypeEnabled then return fallbackDefault end
    return addon.Presence.IsTypeEnabled(key, fallbackKey, fallbackDefault)
end

local function CancelPendingDelveZone()
    if pendingDelveZoneTimer then
        pendingDelveZoneTimer:Cancel()
        pendingDelveZoneTimer = nil
    end
    pendingDelveZoneRetryCount = 0
end

local function tryFireDelveZoneNotification()
    if not addon:IsModuleEnabled("presence") then
        CancelPendingDelveZone()
        return
    end
    if not IsTypeEnabled("presenceZoneChange", nil, true) then
        CancelPendingDelveZone()
        return
    end
    if ShouldSuppress() then
        CancelPendingDelveZone()
        return
    end
    if not addon.IsDelveActive or not addon.IsDelveActive() then
        CancelPendingDelveZone()
        return
    end

    local zoneText = GetZoneText() or "Unknown Zone"
    local tier = addon.GetActiveDelveTier and addon.GetActiveDelveTier()

    if tier then
        CancelPendingDelveZone()
        if addon.Presence.CancelZoneAnim then addon.Presence.CancelZoneAnim() end
        lastKnownZone = zoneText
        lastSubzoneTitleShown = nil
        lastSubzoneTitleTime = 0
        local opts = { category = "DELVES", source = "ZONE_CHANGED_NEW_AREA" }
        addon.Presence.QueueOrPlay("ZONE_CHANGE", Strip(zoneText), "Tier " .. tier, TakeDiscovery(opts))
    else
        pendingDelveZoneRetryCount = pendingDelveZoneRetryCount + 1
        if pendingDelveZoneRetryCount * DELVE_TIER_WAIT_INTERVAL >= DELVE_TIER_WAIT_MAX then
            CancelPendingDelveZone()
            if addon.Presence.CancelZoneAnim then addon.Presence.CancelZoneAnim() end
            lastKnownZone = zoneText
            lastSubzoneTitleShown = nil
            lastSubzoneTitleTime = 0
            local opts = { category = "DELVES", source = "ZONE_CHANGED_NEW_AREA" }
            addon.Presence.QueueOrPlay("ZONE_CHANGE", Strip(zoneText), "Delve", TakeDiscovery(opts))
        else
            pendingDelveZoneTimer = C_Timer.NewTimer(DELVE_TIER_WAIT_INTERVAL, tryFireDelveZoneNotification)
        end
    end
end

-- ============================================================================
-- Zone notification
-- ============================================================================

local function ScheduleZoneNotification(isNewArea)
    local zone = GetZoneText() or "Unknown Zone"
    local sub = GetSubZoneText() or ""

    if not isNewArea and sub ~= "" and zone == sub then return end

    if isNewArea then
        lastKnownZone = zone
        pendingNewArea = true
        CancelPendingDelveZone()
    end

    local function fireZoneNotification()
        -- events since the last banner were combined: a new zone among them makes this a zone entry banner
        pendingFire = nil
        addon.Trace("zone banner fires: newArea=%s zone=%s sub=%s", tostring(pendingNewArea), tostring(GetZoneText()), tostring(GetSubZoneText()))
        isNewArea = pendingNewArea
        pendingNewArea = false
        if not addon:IsModuleEnabled("presence") then return end
        if ShouldSuppress() then
            -- on a flying mount nothing says when you land: start watching for it
            if addon.Presence.Zone_OnFlyingSuppressed then addon.Presence.Zone_OnFlyingSuppressed(placeZone, placeSub) end
            return
        end

        zone = GetZoneText() or "Unknown Zone"
        sub = GetSubZoneText() or ""
        placeZone, placeSub = zone, sub

        -- Arriving through a loading screen (logging in, a hearthstone, a portal) or by releasing your spirit, as when
        -- landing from a flight: where walking in shows a subzone banner (the subzone over the zone), that's the
        -- banner, not the zone entry
        local arrived = GetTime() <= math.max(settleUntil + ARRIVAL_GRACE, arrivalUntil)
        if isNewArea and arrived and sub ~= "" and sub ~= zone
            and IsTypeEnabled("presenceSubzoneChange", "presenceZoneChange", true)
            and not (addon.IsDelveActive and addon.IsDelveActive()) then
            addon.Trace("arrived without walking: subzone banner for %s", sub)
            isNewArea = false
        end

        if addon.Presence.CancelZoneAnim then addon.Presence.CancelZoneAnim() end

        local opts = {}

        if isNewArea then
            lastKnownZone = zone
            if not IsTypeEnabled("presenceZoneChange", nil, true) then return end
            -- "Zone Name Only": no subzone under the zone name (a Delve still shows its tier)
            local displaySub = (addon.GetDB and addon.GetDB("presenceZoneEntryNameOnly", false)) and "" or sub
            if addon.IsDelveActive and addon.IsDelveActive() then
                opts.category = "DELVES"
                local tier = addon.GetActiveDelveTier and addon.GetActiveDelveTier()
                if tier then
                    displaySub = "Tier " .. tier
                else
                    pendingDelveZoneRetryCount = 0
                    pendingDelveZoneTimer = C_Timer.NewTimer(DELVE_TIER_WAIT_INTERVAL, tryFireDelveZoneNotification)
                    return
                end
            elseif addon.IsInPartyDungeon and addon.IsInPartyDungeon() then
                opts.category = "DUNGEON"
            end
            opts.source = "ZONE_CHANGED_NEW_AREA"
            lastSubzoneTitleShown = nil
            lastSubzoneTitleTime = 0
            addon.Presence.QueueOrPlay("ZONE_CHANGE", Strip(zone), Strip(displaySub), TakeDiscovery(opts))
        else
            if not IsTypeEnabled("presenceSubzoneChange", "presenceZoneChange", true) then return end
            if sub == "" then return end
            if addon.IsDelveActive and addon.IsDelveActive() then return end
            if addon.IsInPartyDungeon and addon.IsInPartyDungeon() then
                opts.category = "DUNGEON"
            end
            opts.source = "ZONE_CHANGED"

            local isInterior = lastKnownZone and sub ~= "" and sub == lastKnownZone
            local displayTitle = isInterior and zone or sub
            local displayParent = isInterior and sub or zone

            local hideZoneForSubzone = addon.GetDB and addon.GetDB("presenceHideZoneForSubzone", false)
            local sameZone = lastKnownZone and (
                (not isInterior and zone ~= "" and zone == lastKnownZone) or
                (isInterior and sub ~= "" and sub == lastKnownZone)
            )

            local notifTitle = Strip(displayTitle)
            local notifSub = hideZoneForSubzone and sameZone and "" or Strip(displayParent)

            local now = GetTime()
            if notifTitle == lastSubzoneTitleShown and (now - lastSubzoneTitleTime) < SUBZONE_DEDUP_TIME then
                return
            end
            lastSubzoneTitleShown = notifTitle
            lastSubzoneTitleTime = now
            addon.Presence.QueueOrPlay("SUBZONE_CHANGE", notifTitle, notifSub, TakeDiscovery(opts))
        end
    end
    if addon.Presence.RequestDebounced then
        -- during a loading screen it waits for the loading to finish (Zone_OnInit schedules it then)
        pendingFire = fireZoneNotification
        if loading then
            addon.Presence.CancelDebounced("zone")
        else
            addon.Presence.RequestDebounced("zone", math.max(ZONE_DEBOUNCE, settleUntil - GetTime()), fireZoneNotification)
        end
    end
end

-- ============================================================================
-- Event handlers
-- ============================================================================

function addon.Presence.Zone_OnZoneChangedNewArea()
    addon.Trace("ZONE_CHANGED_NEW_AREA zone=%s sub=%s loading=%s", tostring(GetZoneText()), tostring(GetSubZoneText()), tostring(loading))
    if addon.Presence.ReapplyZoneSuppression and C_Timer and C_Timer.After then
        C_Timer.After(0, addon.Presence.ReapplyZoneSuppression)
    end
    ScheduleZoneNotification(true)
end

function addon.Presence.Zone_OnZoneChanged()
    addon.Trace("ZONE_CHANGED zone=%s sub=%s loading=%s", tostring(GetZoneText()), tostring(GetSubZoneText()), tostring(loading))
    if addon.Presence.ReapplyZoneSuppression and C_Timer and C_Timer.After then
        C_Timer.After(0, addon.Presence.ReapplyZoneSuppression)
    end
    local zone = GetZoneText() or ""
    local sub = GetSubZoneText()
    if sub and sub ~= "" and sub ~= zone then
        ScheduleZoneNotification(false)
    end
end

-- Hide in Flight hides zone banners on a flight path. The zone at takeoff is kept, so landing somewhere else still
-- shows the banner for where you land.
local flight = nil
local LANDING_DELAY = 0.5 -- UnitOnTaxi can still be true when control comes back

-- Releasing your spirit moves you to a graveyard without a loading screen; the zone banner that follows is for
-- arriving there, not for walking in
local SPIRIT_ARRIVAL_WINDOW = 2
function addon.Presence.Zone_OnSpiritRelease()
    addon.Trace("spirit released")
    arrivalUntil = GetTime() + SPIRIT_ARRIVAL_WINDOW
end

function addon.Presence.Zone_OnControlLost()
    -- the taxi starts just after control is lost
    C_Timer.After(LANDING_DELAY, function()
        if not flight and UnitOnTaxi and UnitOnTaxi("player") then
            flight = { zone = GetZoneText() or "", sub = GetSubZoneText() or "" }
            addon.Trace("flight start zone=%s sub=%s", flight.zone, flight.sub)
        end
    end)
end

-- Landed (from a flight path or a flying mount): the banner for where you are, as walking in would show it
local function Land(from)
    if not (addon.GetDB and addon.GetDB("presenceSuppressInFlight", false)) then return end
    C_Timer.After(LANDING_DELAY, function()
        local zone, sub = GetZoneText() or "", GetSubZoneText() or ""
        addon.Trace("flight landed zone=%s sub=%s", zone, sub)
        -- Where walking in shows a subzone banner (the subzone over the zone), landing shows that same banner;
        -- elsewhere, a new zone gets its zone entry banner
        local subzoneShows = sub ~= "" and sub ~= zone
            and IsTypeEnabled("presenceSubzoneChange", "presenceZoneChange", true)
        if subzoneShows and (zone ~= from.zone or sub ~= from.sub) then
            ScheduleZoneNotification(false)
        elseif zone ~= from.zone then
            ScheduleZoneNotification(true)
        end
    end)
end

function addon.Presence.Zone_OnControlGained()
    if not flight or flight.mount then return end
    local from = flight
    flight = nil
    Land(from)
end

-- A flying mount: there's no event for landing, so once a zone banner is hidden because you're flying, check until
-- you're down. You were last at fromZone / fromSub before the hidden banner.
local flyingWatch
function addon.Presence.Zone_OnFlyingSuppressed(fromZone, fromSub)
    if not (addon.GetDB and addon.GetDB("presenceSuppressInFlight", false)) then return end
    if flight or not (IsFlying and IsFlying()) or (UnitOnTaxi and UnitOnTaxi("player")) then return end
    flight = { zone = fromZone or "", sub = fromSub or "", mount = true }
    addon.Trace("flying start zone=%s sub=%s", flight.zone, flight.sub)
    flyingWatch = C_Timer.NewTicker(0.5, function()
        if IsFlying() then return end
        flyingWatch:Cancel()
        flyingWatch = nil
        local from = flight
        flight = nil
        if from then Land(from) end
    end)
end

function addon.Presence.Zone_OnDelveDataUpdate()
    if not pendingDelveZoneTimer then return end
    if not addon.IsDelveActive or not addon.IsDelveActive() then return end

    pendingDelveZoneTimer:Cancel()
    pendingDelveZoneTimer = nil
    tryFireDelveZoneNotification()
end

-- ============================================================================
-- Init (called from OnPlayerEnteringWorld)
-- ============================================================================

-- A loading screen starts: zone banners wait until it's over
function addon.Presence.Zone_OnLoadingScreen()
    addon.Trace("loading screen start")
    loading = true
    addon.Presence.CancelDebounced("zone")
end

-- Loading is over (PLAYER_ENTERING_WORLD, and again when the loading screen is gone): the zone reported while
-- loading is shown once, after the settle window
local function EndLoading()
    addon.Trace("loading end, zone banner pending=%s", tostring(pendingFire ~= nil))
    loading = false
    settleUntil = GetTime() + LOADING_SETTLE_TIME
    if pendingFire then
        addon.Presence.RequestDebounced("zone", LOADING_SETTLE_TIME, pendingFire)
    end
end
addon.Presence.Zone_OnLoadingScreenEnd = EndLoading

-- A zone banner is on its way: a loading screen is up, or one is waiting to be shown
function addon.Presence.ZoneBannerWaiting()
    return loading or pendingFire ~= nil
end

function addon.Presence.Zone_OnInit()
    lastKnownZone = GetZoneText() or nil
    placeZone, placeSub = GetZoneText() or "", GetSubZoneText() or ""
    EndLoading()
end
