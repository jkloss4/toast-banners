--[[
    Toast Banners - Core (from Horizon Suite's Presence module)
    Cinematic zone text and notification display. Frame, layers, animation engine,
    and public QueueOrPlay API. Ported from ModernZoneText.
    Changes from Horizon Suite: custom title/subtitle colors, an adjustable gap between
    the title and the divider, and previews that play the real banner on screen.

    Design notes:
    - Colour is resolved at show time only (resolveColors, getDiscoveryColor); OnUpdate
      touches alpha and layout only, never colour or text.
    - Presence uses cinematic timings (entrance 0.7s, exit 0.8s by default; both set in the options) and
      larger type sizes by design.
    - QueueOrPlay(typeName, title, subtitle, opts): title = heading, subtitle = second
      line; opts.questID is for colour/icon only, never displayed.
]]
local _, addon = ...
if not addon then return end
local L = addon.L


addon.Presence = addon.Presence or {}

-- ============================================================================
-- SCENARIO HELPERS (standalone; no Focus dependency)
-- ============================================================================

-- True when the player is in an active scenario. Uses addon.IsWorldScenario when Focus loaded, else C_Scenario.GetInfo.
function addon.Presence.IsScenarioActive()
    if addon.IsWorldScenario and addon.IsWorldScenario() then return true end
    local ok, name, currentStage = pcall(C_Scenario.GetInfo)
    return ok and ((name and name ~= "") or (currentStage and currentStage > 0))
end

-- Get display info for Presence scenario toasts. Title, subtitle, category. No Focus dependency.
-- @return title string|nil, subtitle string|nil, category string|nil
function addon.Presence.GetScenarioDisplayInfo()
    if not addon.Presence.IsScenarioActive() then return nil, nil, nil end
    local isDelve = addon.IsDelveActive and addon.IsDelveActive()
    local inPartyDungeon = addon.IsInPartyDungeon and addon.IsInPartyDungeon()
    local category = isDelve and "DELVES" or (inPartyDungeon and "DUNGEON") or "SCENARIO"

    local scenarioName
    local ok, name = pcall(C_Scenario.GetInfo)
    if ok and name and name ~= "" then scenarioName = name end

    local stageName
    local sOk, sName = pcall(C_Scenario.GetStepInfo)
    if sOk and sName and sName ~= "" then stageName = sName end

    local title = scenarioName
    if inPartyDungeon then
        local instOk, instanceName = pcall(GetInstanceInfo)
        title = (instOk and instanceName) or "Dungeon"
    elseif not title or title == "" then
        title = "Scenario"
    end

    return title, stageName or "", category
end

-- Strip WoW markup (textures, colors) from a string for display.
-- @param s string|nil
-- @return string
function addon.Presence.StripMarkup(s)
    if not s or s == "" then return s or "" end
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return strtrim(s)
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local MAIN_SIZE    = 48
local SUB_SIZE     = 24
local FRAME_WIDTH  = 800
local FRAME_HEIGHT = 250
local FRAME_Y_DEF  = -180
local DIVIDER_W    = 400
local DIVIDER_H    = 2
local DIVIDER_Y    = -65  -- top of the divider line, from the top of the banner
local MAX_QUEUE    = 8

local ENTRANCE_DUR_DEF  = 0.7
local EXIT_DUR_DEF      = 0.8
local CROSSFADE_DUR = 0.4
local ELEMENT_DUR   = 0.4
local SUBTITLE_TRANSITION_DUR = 0.12

local DISCOVERY_SIZE  = 16
local QUEST_ICON_SIZE = 24  -- quest-type icon in toasts; larger than Focus (16) to match heading scale
local DELAY_TITLE     = 0.0
local DELAY_DIVIDER   = 0.15
local DELAY_SUBTITLE  = 0.30
-- The "Discovered" line doesn't slide: it fades in where it rests, this long after the entrance (the slide) ends, or as
-- soon as it arrives if that's later. Without animations it shows and goes with the rest of the banner.
local DISCOVERY_FADE_AFTER = 0.3
local DISCOVERY_FADE_DUR   = 0.6
local DISCOVERY_FADE_OUT   = 0.4  -- it's gone just as the rest of the banner starts its exit

local TYPES = {
    LEVEL_UP       = { pri = 4, category = "COMPLETE",   subCategory = "DEFAULT", sz = 48, dur = 5.0 },
    BOSS_EMOTE     = { pri = 4, specialColor = true,     subCategory = "DEFAULT", sz = 48, dur = 5.0 },
    ACHIEVEMENT    = { pri = 3, category = "ACHIEVEMENT", subCategory = "DEFAULT", sz = 48, dur = 4.5 },
    QUEST_COMPLETE = { pri = 2, category = "DEFAULT",   subCategory = "DEFAULT", sz = 48, dur = 4.0 },
    WORLD_QUEST    = { pri = 2, category = "WORLD",     subCategory = "DEFAULT", sz = 48, dur = 4.0 },
    ZONE_CHANGE    = { pri = 2, category = "DEFAULT",   subCategory = "CAMPAIGN", sz = 48, dur = 4.0 },
    QUEST_ACCEPT       = { pri = 1, category = "DEFAULT",   subCategory = "DEFAULT", sz = 36, dur = 3.0 },
    WORLD_QUEST_ACCEPT = { pri = 2, category = "WORLD",     subCategory = "DEFAULT", sz = 36, dur = 3.0 },
    QUEST_UPDATE       = { pri = 1, category = "DEFAULT",   subCategory = "DEFAULT", sz = 28, dur = 2.5, liveUpdate = true, replaceInQueue = true, subGap = 12 },
    SUBZONE_CHANGE     = { pri = 1, category = "DEFAULT",   subCategory = "CAMPAIGN", sz = 36, dur = 3.0 },
    SCENARIO_START     = { pri = 2, category = "SCENARIO", subCategory = "DEFAULT", sz = 36, dur = 3.5 },
    SCENARIO_UPDATE     = { pri = 1, category = "SCENARIO", subCategory = "DEFAULT", sz = 36, dur = 2.5, liveUpdate = true, replaceInQueue = true },
    SCENARIO_COMPLETE   = { pri = 2, category = "SCENARIO", subCategory = "DEFAULT", sz = 48, dur = 4.0 },
    ACHIEVEMENT_PROGRESS = { pri = 1, category = "ACHIEVEMENT", subCategory = "DEFAULT", sz = 28, dur = 2.5, liveUpdate = true, replaceInQueue = true, subGap = 12 },
    RARE_DEFEATED      = { pri = 2, category = "DEFAULT",  subCategory = "DEFAULT", sz = 36, dur = 3.5 },
    BOSS_DEFEATED      = { pri = 3, category = "DUNGEON",  subCategory = "DEFAULT", sz = 48, dur = 4.5 },
    BONUS_OBJECTIVE_ACCEPT = { pri = 1, category = "BONUS", subCategory = "DEFAULT", sz = 36, dur = 3.0 },
    BONUS_OBJECTIVE    = { pri = 2, category = "BONUS",    subCategory = "DEFAULT", sz = 48, dur = 4.0 },
}

-- Type name -> { key, fallback, default } for IsTypeEnabledForType.
-- Matches OptionsData presence toggles; used by Blizzard "any toast enabled" and domain handlers.
local TYPE_OPTIONS = {
    LEVEL_UP           = { key = "presenceLevelUp",           fallback = nil, default = true },
    BOSS_EMOTE         = { key = "presenceBossEmote",         fallback = nil, default = true },
    ACHIEVEMENT        = { key = "presenceAchievement",       fallback = nil, default = true },
    QUEST_COMPLETE     = { key = "presenceQuestComplete",     fallback = "presenceQuestEvents", default = true },
    WORLD_QUEST        = { key = "presenceWorldQuest",        fallback = "presenceQuestEvents", default = true },
    ZONE_CHANGE        = { key = "presenceZoneChange",         fallback = nil, default = true },
    QUEST_ACCEPT       = { key = "presenceQuestAccept",        fallback = "presenceQuestEvents", default = true },
    WORLD_QUEST_ACCEPT = { key = "presenceWorldQuestAccept", fallback = "presenceQuestEvents", default = true },
    QUEST_UPDATE       = { key = "presenceQuestUpdate",       fallback = "presenceQuestEvents", default = true },
    SUBZONE_CHANGE     = { key = "presenceSubzoneChange",     fallback = "presenceZoneChange",  default = true },
    SCENARIO_START     = { key = "presenceScenarioStart",    fallback = "showScenarioEvents",  default = true },
    SCENARIO_UPDATE    = { key = "presenceScenarioUpdate",   fallback = "showScenarioEvents",  default = true },
    SCENARIO_COMPLETE  = { key = "presenceScenarioComplete", fallback = "showScenarioEvents",  default = true },
    ACHIEVEMENT_PROGRESS = { key = "presenceAchievementProgress", fallback = nil, default = false },
    RARE_DEFEATED      = { key = "presenceRareDefeated",      fallback = nil, default = true },
    BOSS_DEFEATED      = { key = "presenceBossDefeated",      fallback = nil, default = true },
    BONUS_OBJECTIVE_ACCEPT = { key = "presenceBonusAccept",   fallback = "presenceQuestEvents", default = true },
    BONUS_OBJECTIVE    = { key = "presenceBonusComplete",     fallback = "presenceQuestEvents", default = true },
}

-- Order and L-key mapping for preview dropdown. Used by options.
local PREVIEW_TYPE_ORDER = {
    "ZONE_CHANGE", "SUBZONE_CHANGE", "QUEST_ACCEPT", "WORLD_QUEST_ACCEPT", "QUEST_UPDATE",
    "QUEST_COMPLETE", "WORLD_QUEST", "SCENARIO_START", "SCENARIO_UPDATE", "SCENARIO_COMPLETE",
    "ACHIEVEMENT", "ACHIEVEMENT_PROGRESS", "BOSS_EMOTE", "LEVEL_UP", "RARE_DEFEATED",
    "BOSS_DEFEATED", "BONUS_OBJECTIVE_ACCEPT", "BONUS_OBJECTIVE",
}
local PREVIEW_TYPE_LABELS = {
    ZONE_CHANGE = "Zone entry",
    SUBZONE_CHANGE = "Subzone changes",
    QUEST_ACCEPT = "Quest accepted",
    WORLD_QUEST_ACCEPT = "World quest accepted",
    QUEST_UPDATE = "Quest progress",
    QUEST_COMPLETE = "Quest complete",
    WORLD_QUEST = "World quest complete",
    SCENARIO_START = "Scenario start",
    SCENARIO_UPDATE = "Scenario progress",
    SCENARIO_COMPLETE = "Scenario complete",
    ACHIEVEMENT = "Achievement earned",
    ACHIEVEMENT_PROGRESS = "Achievement progress",
    BOSS_EMOTE = "Boss emotes",
    LEVEL_UP = "Level up",
    RARE_DEFEATED = "Rare defeated",
    BOSS_DEFEATED = "Boss defeated",
    BONUS_OBJECTIVE_ACCEPT = "Bonus objective",
    BONUS_OBJECTIVE = "Bonus objective complete",
}

local debounceTimers = {}

-- Check if a Presence type is enabled, with optional fallback to a grouped option.
-- @param key string DB key for the per-type toggle (e.g. presenceQuestAccept)
-- @param fallbackKey string|nil DB key for fallback when key is nil (e.g. presenceQuestEvents)
-- @param fallbackDefault boolean Default when fallbackKey is nil or not used
-- @return boolean
local function IsTypeEnabled(key, fallbackKey, fallbackDefault)
    if not addon.GetDB then return fallbackDefault end
    local v = addon.GetDB(key, nil)
    if v ~= nil then return v end
    -- Not `(fallbackKey and GetDB(...)) or fallbackDefault`: that turns an inherited
    -- false (e.g. subzone following Zone entry off) back into the default.
    if fallbackKey then return addon.GetDB(fallbackKey, fallbackDefault) end
    return fallbackDefault
end

-- Check if a Presence type (e.g. QUEST_ACCEPT, SCENARIO_UPDATE) is enabled via TYPE_OPTIONS.
-- @param typeName string One of TYPES keys (LEVEL_UP, QUEST_ACCEPT, etc.)
-- @return boolean
local function IsTypeEnabledForType(typeName)
    local opts = typeName and TYPE_OPTIONS[typeName]
    if not opts then return false end
    return IsTypeEnabled(opts.key, opts.fallback, opts.default)
end

-- Cancel existing timer for key, schedule callback after delay. Debounce helper.
-- @param key string Unique key (e.g. "quest:123", "scenario", "zone")
-- @param delay number Seconds before callback runs
-- @param callback function Called when timer fires
-- @return nil
local function RequestDebounced(key, delay, callback)
    if debounceTimers[key] then
        debounceTimers[key]:Cancel()
        debounceTimers[key] = nil
    end
    if not C_Timer or not C_Timer.NewTimer then return end
    debounceTimers[key] = C_Timer.NewTimer(delay, function()
        debounceTimers[key] = nil
        if callback then callback() end
    end)
end

-- Cancel a pending debounced callback for the given key.
-- @param key string Unique key passed to RequestDebounced
-- @return nil
local function CancelDebounced(key)
    if debounceTimers[key] then
        debounceTimers[key]:Cancel()
        debounceTimers[key] = nil
    end
end

-- Build display string from normalized objective.
-- Accepts { text?, finished?, numFulfilled?, numRequired?, quantityString?, percent? }.
-- For isWeightedProgress objectives, percent is the displayed value (0-100); quantityString is not used.
-- @param o table Normalized objective
-- @return string|nil
local function FormatObjectiveForDisplay(o)
    if not o then return nil end
    if o.percent ~= nil and type(o.percent) == "number" then
        if o.text and o.text ~= "" and o.text ~= "0" then
            return ("%s (%d%%)"):format(o.text, math.min(100, math.max(0, math.floor(o.percent))))
        end
        return ("%d%%"):format(math.min(100, math.max(0, math.floor(o.percent))))
    end
    if o.quantityString and o.quantityString ~= "" and o.quantityString ~= "0"
       and not (o.text and o.text ~= "" and o.quantityString:match("^%d+$")) then
        return o.quantityString
    end
    if o.text and o.text ~= "" and o.text ~= "0" then
        if o.numFulfilled ~= nil and o.numRequired ~= nil and o.numRequired > 0 then
            if o.numRequired == 1 then
                return o.text
            end
            local pattern = ("%d/%d"):format(o.numFulfilled, o.numRequired)
            if o.text:find(pattern, 1, true) then
                return o.text
            end
            return ("%s (%d/%d)"):format(o.text, o.numFulfilled, o.numRequired)
        end
        return o.text
    end
    if o.numFulfilled ~= nil and o.numRequired ~= nil and o.numRequired > 0 then
        if o.numRequired == 1 then
            return nil
        end
        return ("%d/%d"):format(o.numFulfilled, o.numRequired)
    end
    return nil
end

-- True if any event-toast type (achievement, quest, scenario) is enabled. Used by Blizzard suppression.
-- @return boolean
local function IsAnyToastEnabled()
    local toastTypes = { "ACHIEVEMENT", "ACHIEVEMENT_PROGRESS", "QUEST_ACCEPT", "WORLD_QUEST_ACCEPT", "QUEST_COMPLETE", "WORLD_QUEST", "QUEST_UPDATE", "SCENARIO_START", "SCENARIO_UPDATE", "SCENARIO_COMPLETE" }
    for _, t in ipairs(toastTypes) do
        if IsTypeEnabledForType(t) then return true end
    end
    return false
end

-- Hide in Flight: every banner that's hidden in flight (zone, subzone, quest and scenario) checks this
local function IsFlightSuppressed()
    return addon.GetDB and addon.GetDB("presenceSuppressInFlight", false) and UnitOnTaxi and UnitOnTaxi("player") or false
end

-- True when zone, subzone and scenario banners are hidden: Hide in Flight, or the Hide option for the instance
-- you're in (quest banners only follow Hide in Flight, through IsFlightSuppressed)
-- @return boolean
local function ShouldSuppressType()
    if addon.GetDB and addon.GetDB("presenceSuppressZoneInMplus", true) and addon.IsInMythicDungeon and addon.IsInMythicDungeon() then
        return true
    end
    if not addon.GetDB then return false end
    if IsFlightSuppressed() then return true end
    local inType = select(2, GetInstanceInfo())
    if inType == "party" and addon.GetDB("presenceSuppressInDungeon", false) then return true end
    if inType == "raid"  and addon.GetDB("presenceSuppressInRaid", false)    then return true end
    if inType == "arena" and addon.GetDB("presenceSuppressInPvP", false)     then return true end
    if inType == "pvp"   and addon.GetDB("presenceSuppressInBattleground", false) then return true end
    return false
end

local function getFrameY()
    local v = addon.GetDB and tonumber(addon.GetDB("presenceFrameY", FRAME_Y_DEF)) or FRAME_Y_DEF
    return math.max(-300, math.min(0, v))
end

local function getFrameScale()
    local v = addon.GetDB and tonumber(addon.GetDB("presenceFrameScale", 1)) or 1
    local base = math.max(0.5, math.min(2, v))
    local moduleScale = (addon.GetModuleScale and addon.GetModuleScale("presence")) or 1
    return base * moduleScale
end

local function getEntranceDur()
    if addon.GetDB and not addon.GetDB("presenceAnimations", true) then return 0 end
    local v = addon.GetDB and tonumber(addon.GetDB("presenceEntranceDur", ENTRANCE_DUR_DEF)) or ENTRANCE_DUR_DEF
    return math.max(0.2, math.min(1.5, v))
end

local function getExitDur()
    if addon.GetDB and not addon.GetDB("presenceAnimations", true) then return 0 end
    local v = addon.GetDB and tonumber(addon.GetDB("presenceExitDur", EXIT_DUR_DEF)) or EXIT_DUR_DEF
    return math.max(0.2, math.min(1.5, v))
end

local function getHoldScale()
    local v = addon.GetDB and tonumber(addon.GetDB("presenceHoldScale", 1)) or 1
    return math.max(0.5, math.min(2, v))
end

local PRESENCE_FONT_USE_GLOBAL = "__global__"
local defaultFontPath = (addon.GetDefaultFontPath and addon.GetDefaultFontPath()) or "Fonts\\FRIZQT__.TTF"

-- Apply a font path with hard fallback so FontStrings never end up without a font.
local function SetSafeFont(fs, path, size, flags)
    if not fs then return false end
    if fs:SetFont(path, size, flags) then return true end
    if path ~= defaultFontPath and fs:SetFont(defaultFontPath, size, flags) then return true end
    return fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags)
end

local function getPresenceFontPath()
    local global = addon.GetActiveGlobalFont and addon.GetActiveGlobalFont()
    if global then return global end
    local raw = addon.GetDB and addon.GetDB("fontPath", defaultFontPath) or defaultFontPath
    return (addon.ResolveFontPath and addon.ResolveFontPath(raw)) or raw
end

local function getPresenceTitleFontPath()
    local global = addon.GetActiveGlobalFont and addon.GetActiveGlobalFont()
    if global then return global end
    local raw = addon.GetDB and addon.GetDB("presenceTitleFontPath", PRESENCE_FONT_USE_GLOBAL) or PRESENCE_FONT_USE_GLOBAL
    if raw == PRESENCE_FONT_USE_GLOBAL or not raw or raw == "" then return getPresenceFontPath() end
    return (addon.ResolveFontPath and addon.ResolveFontPath(raw)) or raw
end

local function getPresenceSubtitleFontPath()
    local global = addon.GetActiveGlobalFont and addon.GetActiveGlobalFont()
    if global then return global end
    local raw = addon.GetDB and addon.GetDB("presenceSubtitleFontPath", PRESENCE_FONT_USE_GLOBAL) or PRESENCE_FONT_USE_GLOBAL
    if raw == PRESENCE_FONT_USE_GLOBAL or not raw or raw == "" then return getPresenceFontPath() end
    return (addon.ResolveFontPath and addon.ResolveFontPath(raw)) or raw
end

local function getPresenceTitleFontOutline()
    local raw = addon.GetDB and addon.GetDB("presenceTitleFontOutline", "OUTLINE")
    if raw == nil then return "OUTLINE" end
    return raw
end

local function getPresenceSubtitleFontOutline()
    local raw = addon.GetDB and addon.GetDB("presenceSubtitleFontOutline", "OUTLINE")
    if raw == nil then return "OUTLINE" end
    return raw
end

local function getPresenceDiscoveryFontPath()
    local global = addon.GetActiveGlobalFont and addon.GetActiveGlobalFont()
    if global then return global end
    local raw = addon.GetDB and addon.GetDB("presenceDiscoveryFontPath", PRESENCE_FONT_USE_GLOBAL) or PRESENCE_FONT_USE_GLOBAL
    if raw == PRESENCE_FONT_USE_GLOBAL or not raw or raw == "" then return getPresenceFontPath() end
    return (addon.ResolveFontPath and addon.ResolveFontPath(raw)) or raw
end

local function getPresenceDiscoveryFontOutline()
    local raw = addon.GetDB and addon.GetDB("presenceDiscoveryFontOutline", "OUTLINE")
    if raw == nil then return "OUTLINE" end
    return raw
end

local function getPresenceDiscoverySize()
    local raw = tonumber(addon.GetDB and addon.GetDB("presenceDiscoverySize", DISCOVERY_SIZE)) or DISCOVERY_SIZE
    return math.max(12, math.min(40, math.floor(raw)))
end

-- Per-FontString hook that re-asserts our desired font path whenever a
-- font-replacement addon (e.g. Platynator) overrides SetFont or SetFontObject.
-- Size is nil so PlayCinematic's variant-sized SetSafeFont calls go through unchanged;
-- the lock only protects the font path. Mirrors LockDirectFont in PresenceTalkingHead.lua.
local function LockDirectFont(fontString, getFont)
    local busyObj  = false
    local busyFont = false

    hooksecurefunc(fontString, "SetFontObject", function(self, obj)
        if busyObj or not obj then return end
        local path, size, flags = getFont()
        if not path then return end
        local _, curSize, curFlags = self:GetFont()
        busyObj = true
        self:SetFontObject(nil)
        self:SetFont(path, size or curSize or 12, flags or curFlags or "OUTLINE")
        busyObj = false
    end)

    hooksecurefunc(fontString, "SetFont", function(self, path, size, flags)
        if busyFont then return end
        local targetPath, targetSize, targetFlags = getFont()
        if not targetPath or path == targetPath then return end
        busyFont = true
        self:SetFont(targetPath, targetSize or size, targetFlags or flags or "OUTLINE")
        busyFont = false
    end)
end

local function GetPresenceTitleFont()
    return getPresenceTitleFontPath(), nil, getPresenceTitleFontOutline()
end

local function GetPresenceSubFont()
    return getPresenceSubtitleFontPath(), nil, getPresenceSubtitleFontOutline()
end

local function GetPresenceDiscoveryFont()
    return getPresenceDiscoveryFontPath(), nil, getPresenceDiscoveryFontOutline()
end

-- Variant-based sizes: large (sz 48), medium (sz 36), small (sz 28). Each has primary + secondary.
local VARIANT_DEFAULTS = {
    large  = { primary = 48, secondary = 24 },
    medium = { primary = 36, secondary = 22 },
    small  = { primary = 28, secondary = 20 },
}

local VARIANT_KEYS = {
    large  = { "presencePrimaryLargeSz",  "presenceSecondaryLargeSz"  },
    medium = { "presencePrimaryMediumSz", "presenceSecondaryMediumSz" },
    small  = { "presencePrimarySmallSz",  "presenceSecondarySmallSz"  },
}

-- Gap in px between the main title and the divider line, per variant. The defaults match Horizon Suite's layout,
-- where the title hung from the top of the frame and the divider sat 65px down.
local TITLE_GAP_DEFAULTS = { large = 17, medium = 29, small = 37 }
local TITLE_GAP_KEYS = { large = "presenceTitleGapLarge", medium = "presenceTitleGapMedium", small = "presenceTitleGapSmall" }

local function getTitleGap(variant)
    local def = TITLE_GAP_DEFAULTS[variant]
    local v = addon.GetDB and tonumber(addon.GetDB(TITLE_GAP_KEYS[variant], def))
    return math.max(0, math.min(60, v or def))
end

-- Gap in px between the divider line and the subtitle, per variant
local SUB_GAP_DEFAULT = 10
local SUB_GAP_KEYS = { large = "presenceSubGapLarge", medium = "presenceSubGapMedium", small = "presenceSubGapSmall" }

local function getSubGap(variant)
    local v = addon.GetDB and tonumber(addon.GetDB(SUB_GAP_KEYS[variant], SUB_GAP_DEFAULT))
    return math.max(0, math.min(40, v or SUB_GAP_DEFAULT))
end

-- The type's own size, from its sz
local function getDefaultVariant(cfg)
    if cfg.sz >= 44 then return "large" end
    if cfg.sz >= 32 then return "medium" end
    return "small"
end

local VALID_VARIANTS = { large = true, medium = true, small = true }

-- The size chosen for the type on the Notifications tab (presenceSize_<TYPE>), else its own
local function getVariant(cfg, typeName)
    local chosen = addon.GetDB and typeName and addon.GetDB("presenceSize_" .. typeName)
    if VALID_VARIANTS[chosen] then return chosen end
    return getDefaultVariant(cfg)
end

local function getPrimarySz(variant)
    local def = VARIANT_DEFAULTS[variant]
    local key = VARIANT_KEYS[variant][1]
    local v = addon.GetDB and tonumber(addon.GetDB(key, def.primary))
    return math.max(12, math.min(72, v or def.primary))
end

local function getSecondarySz(variant)
    local def = VARIANT_DEFAULTS[variant]
    local key = VARIANT_KEYS[variant][2]
    local v = addon.GetDB and tonumber(addon.GetDB(key, def.secondary))
    return math.max(12, math.min(40, v or def.secondary))
end

local function getCategoryColor(cat, default)
    local c = (addon.GetQuestColor and addon.GetQuestColor(cat)) or (addon.QUEST_COLORS and addon.QUEST_COLORS[cat]) or (addon.QUEST_COLORS and addon.QUEST_COLORS.DEFAULT) or default
    return c
end

local function getDiscoveryColor()
    return (addon.GetPresenceDiscoveryColor and addon.GetPresenceDiscoveryColor()) or addon.PRESENCE_DISCOVERY_COLOR or getCategoryColor("COMPLETE", { 0.4, 1, 0.5 })
end

-- Returns a color for the current zone PvP type (friendly/hostile/contested/sanctuary).
-- Uses user-configured colors if set, otherwise sane defaults.
-- @return table|nil {r,g,b} or nil if zone type is unknown
local function GetZoneTypeColor()
    local pvpType = (C_PvP and C_PvP.GetZonePVPInfo) and C_PvP.GetZonePVPInfo() or (GetZonePVPInfo and GetZonePVPInfo()) or nil
    if not pvpType or pvpType == "" then return nil end
    local colorKey
    if pvpType == "friendly" then
        colorKey = "presenceZoneColorFriendly"
    elseif pvpType == "hostile" then
        colorKey = "presenceZoneColorHostile"
    elseif pvpType == "contested" then
        colorKey = "presenceZoneColorContested"
    elseif pvpType == "sanctuary" then
        colorKey = "presenceZoneColorSanctuary"
    else
        return nil
    end
    local c = addon.GetDB and addon.GetDB(colorKey, nil)
    if c and type(c) == "table" and c[1] and c[2] and c[3] then return c end
    -- Sane defaults
    local defaults = {
        presenceZoneColorFriendly  = { 0.1, 1.0, 0.1 },  -- green
        presenceZoneColorHostile   = { 1.0, 0.1, 0.1 },  -- red
        presenceZoneColorContested = { 1.0, 0.7, 0.0 },  -- orange
        presenceZoneColorSanctuary = { 0.41, 0.8, 0.94 }, -- light blue
    }
    return defaults[colorKey] or nil
end


-- A color chosen for one notification type on the Colors tab ("title", "line", "sub" or "discovery"), or nil.
-- Saved as presenceTypeColor_<TYPE>_<part> = { r, g, b }, used while presenceTypeColorOn_<TYPE>_<part> is on.
local function getTypeColor(typeName, part)
    if not (addon.GetDB and addon.GetDB("presenceTypeColorOn_" .. typeName .. "_" .. part, false)) then return nil end
    local c = addon.GetDB("presenceTypeColor_" .. typeName .. "_" .. part)
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return c
    end
    return nil
end

-- The colors a type gets from its type alone (before any color settings): main title, subtitle
local function getTypeDefaultColors(typeName)
    local cfg = TYPES[typeName]
    if not cfg then return { 1, 1, 1 }, { 1, 1, 1 } end
    if typeName == "BOSS_EMOTE" then
        return addon.GetColorSetting("presenceBossEmoteColor"), getCategoryColor("DEFAULT", { 1, 1, 1 })
    end
    return getCategoryColor(cfg.category, { 0.9, 0.9, 0.9 }), getCategoryColor(cfg.subCategory or "DEFAULT", { 1, 1, 1 })
end

local function resolveColors(typeName, cfg, opts)
    opts = opts or {}
    if cfg.specialColor and typeName == "BOSS_EMOTE" then
        local c = (addon.GetPresenceBossEmoteColor and addon.GetPresenceBossEmoteColor()) or addon.PRESENCE_BOSS_EMOTE_COLOR or { 1, 0.2, 0.2 }
        local sc = getCategoryColor("DEFAULT", { 1, 1, 1 })
        return c, sc
    end
    -- Zone-type coloring for zone/subzone changes when enabled
    if (typeName == "ZONE_CHANGE" or typeName == "SUBZONE_CHANGE") and addon.GetDB and addon.GetDB("presenceZoneTypeColoring", false) then
        local ztc = GetZoneTypeColor()
        if ztc then
            local subCat = cfg.subCategory or "DEFAULT"
            local sc = getCategoryColor(subCat, { 1, 1, 1 })
            return ztc, sc
        end
    end
    local cat = cfg.category
    if opts.category and (typeName == "SCENARIO_START" or typeName == "SCENARIO_UPDATE" or typeName == "SCENARIO_COMPLETE" or typeName == "ZONE_CHANGE" or typeName == "SUBZONE_CHANGE" or typeName == "BOSS_DEFEATED") then
        cat = opts.category
    elseif opts.questID then
        if (typeName == "QUEST_COMPLETE" or typeName == "QUEST_UPDATE") and addon.GetQuestBaseCategory then
            local ok, res = pcall(addon.GetQuestBaseCategory, opts.questID)
            cat = (ok and res) or cat
        elseif typeName == "QUEST_ACCEPT" and addon.GetQuestCategory then
            local ok, res = pcall(addon.GetQuestCategory, opts.questID)
            cat = (ok and res) or cat
        end
    end
    local c = getCategoryColor(cat, { 0.9, 0.9, 0.9 })
    local subCat = cfg.subCategory or "DEFAULT"
    local sc = getCategoryColor(subCat, { 1, 1, 1 })
    return c, sc
end

-- ============================================================================
-- FRAME & LAYER CREATION
-- ============================================================================

local function CreateLayer(parent)
    local L = {}
    local shadowA = (addon.SHADOW_A ~= nil) and addon.SHADOW_A or 0.8
    -- Respect Typography shadow settings when available; fall back to addon globals
    local shadowX = (addon.GetDB and tonumber(addon.GetDB("shadowOffsetX", 2))) or addon.SHADOW_OX or 2
    local shadowY = (addon.GetDB and tonumber(addon.GetDB("shadowOffsetY", -2))) or addon.SHADOW_OY or -2

    L.titleShadow = parent:CreateFontString(nil, "BORDER")
    SetSafeFont(L.titleShadow, getPresenceTitleFontPath(), MAIN_SIZE, getPresenceTitleFontOutline())
    L.titleShadow:SetTextColor(0, 0, 0, shadowA)
    L.titleShadow:SetJustifyH("CENTER")

    L.titleText = parent:CreateFontString(nil, "OVERLAY")
    SetSafeFont(L.titleText, getPresenceTitleFontPath(), MAIN_SIZE, getPresenceTitleFontOutline())
    L.titleText:SetTextColor(1, 1, 1, 1)
    L.titleText:SetJustifyH("CENTER")
    L.titleText:SetPoint("TOP", 0, 0)
    L.titleShadow:SetPoint("CENTER", L.titleText, "CENTER", shadowX, shadowY)

    -- Quest-type icon (same atlas as Focus); larger size to match heading scale
    L.questTypeIcon = parent:CreateTexture(nil, "ARTWORK")
    L.questTypeIcon:SetSize(QUEST_ICON_SIZE, QUEST_ICON_SIZE)
    L.questTypeIcon:SetPoint("RIGHT", L.titleText, "LEFT", -6, 0)
    L.questTypeIcon:Hide()

    L.divider = parent:CreateTexture(nil, "ARTWORK")
    L.divider:SetSize(DIVIDER_W, DIVIDER_H)
    L.divider:SetPoint("TOP", 0, -65)
    L.divider:SetColorTexture(1, 1, 1, 1)
    L.divider:SetAlpha(0)

    L.subShadow = parent:CreateFontString(nil, "BORDER")
    SetSafeFont(L.subShadow, getPresenceSubtitleFontPath(), SUB_SIZE, getPresenceSubtitleFontOutline())
    L.subShadow:SetTextColor(0, 0, 0, shadowA)
    L.subShadow:SetJustifyH("CENTER")

    L.subText = parent:CreateFontString(nil, "OVERLAY")
    SetSafeFont(L.subText, getPresenceSubtitleFontPath(), SUB_SIZE, getPresenceSubtitleFontOutline())
    L.subText:SetTextColor(1, 1, 1, 1)  -- neutral; resolved at play via resolveColors
    L.subText:SetJustifyH("CENTER")
    L.subText:SetPoint("TOP", L.divider, "BOTTOM", 0, -10)
    L.subShadow:SetPoint("CENTER", L.subText, "CENTER", shadowX, shadowY)

    L.discoveryShadow = parent:CreateFontString(nil, "BORDER")
    SetSafeFont(L.discoveryShadow, getPresenceDiscoveryFontPath(), getPresenceDiscoverySize(), getPresenceDiscoveryFontOutline())
    L.discoveryShadow:SetTextColor(0, 0, 0, shadowA)
    L.discoveryShadow:SetJustifyH("CENTER")

    L.discoveryText = parent:CreateFontString(nil, "OVERLAY")
    SetSafeFont(L.discoveryText, getPresenceDiscoveryFontPath(), getPresenceDiscoverySize(), getPresenceDiscoveryFontOutline())
    L.discoveryText:SetTextColor(1, 1, 1, 1)  -- neutral; resolved at show via getDiscoveryColor
    L.discoveryText:SetJustifyH("CENTER")
    L.discoveryText:SetPoint("TOP", L.subText, "BOTTOM", 0, -5)
    L.discoveryShadow:SetPoint("CENTER", L.discoveryText, "CENTER", shadowX, shadowY)
    L.discoveryText:SetAlpha(0)
    L.discoveryShadow:SetAlpha(0)

    LockDirectFont(L.titleShadow,     GetPresenceTitleFont)
    LockDirectFont(L.titleText,       GetPresenceTitleFont)
    LockDirectFont(L.subShadow,       GetPresenceSubFont)
    LockDirectFont(L.subText,         GetPresenceSubFont)
    LockDirectFont(L.discoveryShadow, GetPresenceDiscoveryFont)
    LockDirectFont(L.discoveryText,   GetPresenceDiscoveryFont)

    return L
end

local F, layerA, layerB, curLayer, oldLayer
local anim
local active, activeTitle, activeTypeName
local activeOpts, activeSubtitle  -- kept so a preview can be redrawn as its settings change
local queue, crossfadeStartAlpha
local subtitleTransition  -- { phase = "fadeOut"|"fadeIn", elapsed = 0, newText = string }
local PlayCinematic

-- Cached at PlayCinematic time so OnUpdate never calls GetDB.
local cachedEntranceDur   = 0.7
local cachedExitDur       = 0.8
local cachedHasDiscovery  = false
local discoveryClock      = 0      -- seconds since the banner started, for the "Discovered" fade
local discoveryFrom       = 0      -- when the "Discovered" line arrived (0: with the banner)
local cachedSubGap        = 10  -- px below divider; QUEST_UPDATE uses 12 for compact layout
local cachedCompactLayout = false  -- when true, hide title/divider; show only subtitle (QUEST_UPDATE with presenceHideQuestUpdateTitle)

-- Skip-trackers: avoid redundant layout calls when value hasn't changed.
local lastTitleOffsetY = nil
local lastSubOffsetY   = nil
local lastDividerWidth = nil

local QUEST_UPDATE_DEDUPE_TIME = 1.5
local lastQuestUpdateNorm, lastQuestUpdateTime

-- ============================================================================
-- LIVE DEBUG LOG  (via addon.Log + generic panel from LoggerPanel.lua)
-- ============================================================================

local function IsDebugLive()
    return addon.Log and addon.Log.isEnabled("presence")
end

local presencePanel = addon.Log.createPanel("presence", "Presence Live Debug", {
    maxLines = 500,
    onClose  = function()
        if addon.Presence and addon.Presence.SetDebugLive then
            addon.Presence.SetDebugLive(false)
        end
    end,
})

local function SetDebugLive(v)
    if addon.SetDB then addon.SetDB("presenceDebugLive", v) end
    addon.Log.enableTag("presence", v or nil)
    if v then
        presencePanel.Show()
        addon.Log.debug("presence", "Live debug enabled")
    else
        presencePanel.Hide()
    end
end

local function ToggleDebugLive()
    local next = not IsDebugLive()
    SetDebugLive(next)
    return next
end

-- ============================================================================
-- EASING & ANIMATION HELPERS
-- ============================================================================

local function easeOut(t) return 1 - (1 - t) * (1 - t) end
local function easeIn(t)  return t * t end

local function entEase(elapsed, delay)
    if elapsed < delay then return 0 end
    return easeOut(math.min((elapsed - delay) / ELEMENT_DUR, 1))
end

local function resetLayer(L)
    L.titleText:SetAlpha(0)
    L.titleShadow:SetAlpha(0)
    L.divider:SetAlpha(0)
    L.subText:SetAlpha(0)
    L.subShadow:SetAlpha(0)
    L.discoveryText:SetAlpha(0)
    L.discoveryShadow:SetAlpha(0)
    L.discoveryText:SetText("")
    L.discoveryShadow:SetText("")
    if L.questTypeIcon then L.questTypeIcon:Hide() end
end

-- Apply toast content (fonts, colors, text, icon, layout) to a layer. Shared by PlayCinematic and preview.
-- @param layer table Layer from CreateLayer
-- @param typeName string One of TYPES keys
-- @param title string Heading text
-- @param subtitle string Second line text
-- @param opts table|nil opts.questID, opts.category
-- @return nil
local function ApplyToastContentToLayer(layer, typeName, title, subtitle, opts)
    opts = opts or {}
    local cfg = TYPES[typeName]
    if not cfg then return end

    local compactLayout = (typeName == "QUEST_UPDATE" or typeName == "SCENARIO_UPDATE") and (addon.GetDB and addon.GetDB("presenceHideQuestUpdateTitle", false))
    local c, sc = resolveColors(typeName, cfg, opts)
    local pcc = addon.GetModuleClassColor and addon.GetModuleClassColor("presence")
    if pcc then
        c = { pcc[1], pcc[2], pcc[3] }
    end
    local variant = getVariant(cfg, typeName)
    local mainSz = math.max(12, math.min(72, math.floor(getPrimarySz(variant))))
    local subSz = compactLayout and mainSz or math.max(12, math.min(40, math.floor(getSecondarySz(variant))))

    SetSafeFont(layer.titleText, getPresenceTitleFontPath(), mainSz, getPresenceTitleFontOutline())
    SetSafeFont(layer.titleShadow, getPresenceTitleFontPath(), mainSz, getPresenceTitleFontOutline())
    SetSafeFont(layer.subText, getPresenceSubtitleFontPath(), subSz, getPresenceSubtitleFontOutline())
    SetSafeFont(layer.subShadow, getPresenceSubtitleFontPath(), subSz, getPresenceSubtitleFontOutline())

    -- Each type's own colors (Colors tab) win; the divider line otherwise takes the main title's color
    c = getTypeColor(typeName, "title") or c
    sc = getTypeColor(typeName, "sub") or sc
    local lc = getTypeColor(typeName, "line") or c

    layer.titleText:SetTextColor(c[1], c[2], c[3], 1)
    layer.subText:SetTextColor(sc[1], sc[2], sc[3], 1)
    layer.divider:SetVertexColor(lc[1], lc[2], lc[3])

    if compactLayout then
        layer.titleText:SetText("")
        layer.titleShadow:SetText("")
    else
        layer.titleText:SetText(title or "")
        layer.titleShadow:SetText(title or "")
    end
    layer.subText:SetText(subtitle or "")
    layer.subShadow:SetText(subtitle or "")

    resetLayer(layer)
    layer.divider:SetSize(0.01, DIVIDER_H)

    if layer.questTypeIcon then
        local showIcon = false
        local atlas
        local questRelated = (typeName == "QUEST_ACCEPT" or typeName == "QUEST_COMPLETE" or typeName == "QUEST_UPDATE" or typeName == "WORLD_QUEST" or typeName == "WORLD_QUEST_ACCEPT" or typeName == "BONUS_OBJECTIVE_ACCEPT" or typeName == "BONUS_OBJECTIVE")
        local showIcons = addon.GetDB and addon.GetDB("showPresenceQuestTypeIcons", true)
        if questRelated and opts.questID and addon.GetQuestTypeAtlas and addon.GetDB and showIcons then
            local catForAtlas = "DEFAULT"
            if typeName == "QUEST_COMPLETE" then
                catForAtlas = "COMPLETE"
            elseif (typeName == "QUEST_ACCEPT" or typeName == "QUEST_UPDATE") and addon.GetQuestCategory then
                catForAtlas = addon.GetQuestCategory(opts.questID) or catForAtlas
            elseif typeName == "WORLD_QUEST" or typeName == "WORLD_QUEST_ACCEPT" then
                catForAtlas = "WORLD"
            end
            if typeName == "BONUS_OBJECTIVE_ACCEPT" or typeName == "BONUS_OBJECTIVE" then
                atlas = "QuestBonusObjective"  -- the bonus objective icon Blizzard's tracker uses
            else
                atlas = addon.GetQuestTypeAtlas(opts.questID, catForAtlas)
            end
            if atlas then showIcon = true end
        elseif questRelated and opts.previewAtlas and showIcons then
            -- a preview has no real quest to pick the icon from, so its sample carries a typical one
            atlas = opts.previewAtlas
            showIcon = true
        end
        if showIcon and atlas then
            layer.questTypeIcon:SetAtlas(atlas)
            local iconMax = (addon.GetDB and addon.GetDB("presenceIconSize", 24)) or QUEST_ICON_SIZE
            local iconSz = compactLayout and ((subSz < iconMax) and subSz or iconMax) or ((mainSz < iconMax) and mainSz or iconMax)
            layer.questTypeIcon:SetSize(iconSz, iconSz)
            layer.questTypeIcon:ClearAllPoints()
            layer.questTypeIcon:SetPoint("RIGHT", compactLayout and layer.subText or layer.titleText, "LEFT", -6, 0)
            layer.questTypeIcon:Show()
        else
            layer.questTypeIcon:Hide()
        end
    end

    -- the type's own extra space (quest and achievement progress have 2px more) on top of the size's Subtitle Spacing
    local subGap = getSubGap(variant) + ((cfg.subGap or 10) - 10)
    layer.subGap = subGap
    -- The title sits titleGap above the divider line and the subtitle subGap below it; the entrance animation starts
    -- the title 20px higher and the subtitle 10px lower. Both are placed on the banner rather than on the line: the
    -- line grows from nothing as they move, and rounding its edges would shift anything attached to it sideways.
    layer.titleGap = getTitleGap(variant)
    layer.divider:ClearAllPoints()
    layer.divider:SetPoint("TOP", 0, DIVIDER_Y)
    layer.titleText:ClearAllPoints()
    layer.titleText:SetPoint("BOTTOM", layer.titleText:GetParent(), "TOP", 0, DIVIDER_Y + layer.titleGap + 20)
    layer.subText:ClearAllPoints()
    layer.subText:SetPoint("TOP", 0, DIVIDER_Y - DIVIDER_H - (subGap + 10))
    -- the "Discovered" line is placed where it rests under the subtitle's final spot: it fades in there, without the
    -- subtitle's slide
    local discoveryGap = addon.GetDB and tonumber(addon.GetDB("presenceDiscoveryGap", 5)) or 5
    layer.discoveryGap = math.max(0, math.min(30, discoveryGap))
    layer.discoveryText:ClearAllPoints()
    layer.discoveryText:SetPoint("TOP", 0,
        DIVIDER_Y - DIVIDER_H - subGap - layer.subText:GetStringHeight() - layer.discoveryGap)

    local showDiscovery = opts.showDiscovery or (addon.Presence.pendingDiscovery and (typeName == "ZONE_CHANGE" or typeName == "SUBZONE_CHANGE") and (not addon.GetDB or addon.GetDB("showPresenceDiscovery", true)))
    if showDiscovery then
        SetSafeFont(layer.discoveryText,   getPresenceDiscoveryFontPath(), getPresenceDiscoverySize(), getPresenceDiscoveryFontOutline())
        SetSafeFont(layer.discoveryShadow, getPresenceDiscoveryFontPath(), getPresenceDiscoverySize(), getPresenceDiscoveryFontOutline())
        layer.discoveryText:SetText(L["PRESENCE_DISCOVERED"])
        layer.discoveryShadow:SetText(L["PRESENCE_DISCOVERED"])
        local dc = getTypeColor(typeName, "discovery") or getDiscoveryColor()
        layer.discoveryText:SetTextColor(dc[1], dc[2], dc[3], 1)
        layer.discoveryShadow:SetTextColor(0, 0, 0, (addon.SHADOW_A ~= nil) and addon.SHADOW_A or 0.8)
        addon.Presence.pendingDiscovery = nil
    end
end

-- Layout helpers: only call through when the value changes.
local function setTitleOffset(L, offsetY)
    if lastTitleOffsetY ~= offsetY then
        lastTitleOffsetY = offsetY
        L.titleText:ClearAllPoints()
        L.titleText:SetPoint("BOTTOM", L.titleText:GetParent(), "TOP", 0, DIVIDER_Y + (L.titleGap or 0) + offsetY)
    end
end

local function setSubOffset(L, offsetY)
    if lastSubOffsetY ~= offsetY then
        lastSubOffsetY = offsetY
        L.subText:ClearAllPoints()
        L.subText:SetPoint("TOP", 0, DIVIDER_Y - DIVIDER_H - cachedSubGap + offsetY)
    end
end

local function setDividerWidth(L, w)
    w = math.max(w, 0.01)
    if lastDividerWidth ~= w then
        lastDividerWidth = w
        L.divider:SetSize(w, DIVIDER_H)
    end
end

local function updateEntrance()
    local L  = curLayer
    -- The element delays and ELEMENT_DUR make up the default 0.7s entrance; they're scaled to the Entrance Duration
    local e  = (cachedEntranceDur > 0) and (anim.elapsed * ENTRANCE_DUR_DEF / cachedEntranceDur) or math.huge
    local te = entEase(e, DELAY_TITLE)
    local de = entEase(e, DELAY_DIVIDER)
    local se = entEase(e, DELAY_SUBTITLE)

    if cachedCompactLayout then
        L.titleText:SetAlpha(0)
        L.titleShadow:SetAlpha(0)
        if L.questTypeIcon and L.questTypeIcon:IsShown() then L.questTypeIcon:SetAlpha(te) end
    else
        L.titleText:SetAlpha(te)
        L.titleShadow:SetAlpha(te * 0.8)
        if L.questTypeIcon and L.questTypeIcon:IsShown() then L.questTypeIcon:SetAlpha(te) end
        setTitleOffset(L, (1 - te) * 20)
    end

    L.divider:SetAlpha(de * 0.5)
    setDividerWidth(L, DIVIDER_W * de)

    local subAlpha = se
    if subtitleTransition then
        local st = subtitleTransition
        local t = math.min(st.elapsed / SUBTITLE_TRANSITION_DUR, 1)
        local stAlpha = (st.phase == "fadeOut") and (1 - t) or t
        -- Subtitle is still entering; don't go brighter than entrance progress
        subAlpha = math.min(subAlpha, stAlpha)
    end

    L.subText:SetAlpha(subAlpha)
    L.subShadow:SetAlpha(subAlpha * 0.8)
    setSubOffset(L, (1 - se) * (-10))
end

-- The "Discovered" line's fade, from discoveryClock: nothing until DISCOVERY_FADE_AFTER past the entrance (or until it
-- arrived, if later), then in over DISCOVERY_FADE_DUR. Fully shown at once without animations.
local function discoveryAlpha()
    if cachedEntranceDur <= 0 then return 1 end
    local t = (discoveryClock - math.max(cachedEntranceDur + DISCOVERY_FADE_AFTER, discoveryFrom)) / DISCOVERY_FADE_DUR
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

local function setDiscoveryAlpha(L, a)
    L.discoveryText:SetAlpha(a)
    L.discoveryShadow:SetAlpha(a * 0.8)
end

local function updateCrossfade()
    -- the old banner is gone by the time the new one's entrance ends, however short
    local fadeDur = math.min(CROSSFADE_DUR, cachedEntranceDur)
    local fadeT = (fadeDur > 0) and math.min(anim.elapsed / fadeDur, 1) or 1
    local fade  = crossfadeStartAlpha * (1 - easeIn(fadeT))
    local fade8 = fade * 0.8
    oldLayer.titleText:SetAlpha(fade)
    oldLayer.titleShadow:SetAlpha(fade8)
    if oldLayer.questTypeIcon and oldLayer.questTypeIcon:IsShown() then oldLayer.questTypeIcon:SetAlpha(fade) end
    oldLayer.divider:SetAlpha(fade * 0.5)
    oldLayer.subText:SetAlpha(fade)
    oldLayer.subShadow:SetAlpha(fade8)
    if (oldLayer.discoveryText:GetText() or "") ~= "" then
        oldLayer.discoveryText:SetAlpha(fade)
        oldLayer.discoveryShadow:SetAlpha(fade8)
    end
    updateEntrance()
end

local function updateExit()
    local L   = curLayer
    local e   = (cachedExitDur > 0) and math.min(anim.elapsed / cachedExitDur, 1) or 1
    local inv = 1 - e
    local inv8 = inv * 0.8

    if cachedCompactLayout then
        L.titleText:SetAlpha(0)
        L.titleShadow:SetAlpha(0)
    else
        L.titleText:SetAlpha(inv)
        L.titleShadow:SetAlpha(inv8)
        setTitleOffset(L, e * 15)
    end

    if L.questTypeIcon and L.questTypeIcon:IsShown() then L.questTypeIcon:SetAlpha(inv) end
    L.divider:SetAlpha(0.5 * inv)
    setDividerWidth(L, DIVIDER_W * inv)

    L.subText:SetAlpha(inv)
    L.subShadow:SetAlpha(inv8)
    setSubOffset(L, e * (-10))

    if cachedHasDiscovery then
        setDiscoveryAlpha(L, 0) -- faded out by the end of the hold
    end
end

local function updateSubtitleTransition(dt)
    if not subtitleTransition or not curLayer then return end
    local st = subtitleTransition
    st.elapsed = st.elapsed + dt
    local L = curLayer
    if st.phase == "fadeOut" then
        local t = math.min(st.elapsed / SUBTITLE_TRANSITION_DUR, 1)
        local alpha = 1 - t
        L.subText:SetAlpha(alpha)
        L.subShadow:SetAlpha(alpha * 0.8)
        if st.elapsed >= SUBTITLE_TRANSITION_DUR then
            L.subText:SetText(st.newText or "")
            L.subShadow:SetText(st.newText or "")
            st.phase = "fadeIn"
            st.elapsed = 0
        end
    else
        local t = math.min(st.elapsed / SUBTITLE_TRANSITION_DUR, 1)
        local alpha = t
        L.subText:SetAlpha(alpha)
        L.subShadow:SetAlpha(alpha * 0.8)
        if st.elapsed >= SUBTITLE_TRANSITION_DUR then
            L.subText:SetAlpha(1)
            L.subShadow:SetAlpha(0.8)
            subtitleTransition = nil
        end
    end
end

local function finalizeEntrance()
    local L = curLayer
    if cachedCompactLayout then
        L.titleText:SetAlpha(0)
        L.titleShadow:SetAlpha(0)
    else
        L.titleText:SetAlpha(1)
        L.titleShadow:SetAlpha(0.8)
        setTitleOffset(L, 0)
    end
    if L.questTypeIcon and L.questTypeIcon:IsShown() then L.questTypeIcon:SetAlpha(1) end
    L.divider:SetAlpha(0.5)
    setDividerWidth(L, DIVIDER_W)
    L.subText:SetAlpha(1)
    L.subShadow:SetAlpha(0.8)
    setSubOffset(L, 0)
end

local onComplete
-- OnUpdate: drives entrance/hold/exit phases; adjusts alpha and layout only (no colour or text).
local MAX_FRAME_STEP = 1 / 30  -- a hitch (e.g. right after a loading screen) can't skip the animation ahead

local entranceStartedAt, entranceFrames = 0, 0  -- for the trace: how long the entrance really took

local function PresenceOnUpdate(_, dt)
    if anim.phase == "idle" then return end
    if dt > MAX_FRAME_STEP * 2 and IsDebugLive() then
        addon.Trace("frame hitch %.3fs during %s", dt, anim.phase)
    end
    dt = math.min(dt, MAX_FRAME_STEP)
    anim.elapsed = anim.elapsed + dt

    if subtitleTransition then
        updateSubtitleTransition(dt)
    end

    if anim.phase ~= "exit" then
        discoveryClock = discoveryClock + dt
        if cachedHasDiscovery then
            local a = discoveryAlpha()
            if anim.phase == "hold" and cachedEntranceDur > 0 then -- out over the end of the hold, before the exit
                a = math.min(a, math.max(0, (anim.holdDur - anim.elapsed) / DISCOVERY_FADE_OUT))
            end
            setDiscoveryAlpha(curLayer, a)
        end
    end

    if anim.phase == "entrance" then
        if anim.elapsed == dt then entranceStartedAt, entranceFrames = GetTime(), 0 end
        entranceFrames = entranceFrames + 1
        if cachedEntranceDur > 0 then
            updateEntrance()
        else
            finalizeEntrance()
        end
        if anim.elapsed >= cachedEntranceDur then
            addon.Trace("entrance done: %.2fs real time, %d frames", GetTime() - entranceStartedAt, entranceFrames)
            finalizeEntrance()
            anim.phase   = "hold"
            anim.elapsed = 0
        end
    elseif anim.phase == "crossfade" then
        updateCrossfade()
        if anim.elapsed >= cachedEntranceDur then
            finalizeEntrance()
            resetLayer(oldLayer)
            anim.phase   = "hold"
            anim.elapsed = 0
        end
    elseif anim.phase == "hold" then
        if anim.elapsed >= anim.holdDur then
            anim.phase   = "exit"
            anim.elapsed = 0
        end
    elseif anim.phase == "exit" then
        updateExit()
        if anim.elapsed >= cachedExitDur then
            onComplete()
        end
    end
end

onComplete = function()
    local doneTitle, doneType, doneSub
    if IsDebugLive() then
        doneTitle = activeTitle
        doneType  = activeTypeName
        doneSub   = (curLayer and curLayer.subText and curLayer.subText:GetText()) or ""
    end

    subtitleTransition = nil
    F:SetScript("OnUpdate", nil)
    anim.phase      = "idle"
    active          = nil
    activeTitle     = nil
    activeTypeName  = nil
    resetLayer(curLayer)
    resetLayer(oldLayer)
    F:Hide()

    if doneTitle then
        addon.Log.debug("presence",("Complete %s \"%s\" | \"%s\"; queue=%d"):format(tostring(doneType or "?"), tostring(doneTitle or ""):gsub('"', "'"), tostring(doneSub):gsub('"', "'"), #queue))
    end

    if #queue > 0 then
        local best = 1
        for i = 2, #queue do
            if TYPES[queue[i][1]].pri > TYPES[queue[best][1]].pri then
                best = i
            end
        end
        local nxt = table.remove(queue, best)
        -- Defer to next frame to avoid visible flicker when advancing queue (Hide then Show in same frame)
        C_Timer.After(0, function() PlayCinematic(nxt[1], nxt[2], nxt[3], nxt[4]) end)
    end
end

-- ============================================================================
-- Public functions
-- ============================================================================

-- While a preview banner plays, the settings window it was started from is made invisible, so the banner is seen
-- against the game world; it comes back when the banner is gone (or a real banner takes its place).
local settingsHidden = false

-- Settings tooltips (the Show Preview button's, or any row the mouse passes over) stay hidden meanwhile
local tooltipHooked = false

local function HideSettingsForPreview()
    if not (SettingsPanel and SettingsPanel:IsShown()) then return end
    settingsHidden = true
    SettingsPanel:SetAlpha(0)
    local tooltip = SettingsTooltip
    if tooltip then
        tooltip:Hide()
        if not tooltipHooked then
            tooltipHooked = true
            tooltip:HookScript("OnShow", function(self)
                if settingsHidden then self:Hide() end
            end)
        end
    end
end

local function RestoreSettings()
    if not settingsHidden then return end
    settingsHidden = false
    if SettingsPanel then SettingsPanel:SetAlpha(1) end
end

-- One-time setup: create frame, layers, animation state. Idempotent.
-- @return nil
local function Init()
    if F then return end

    F = CreateFrame("Frame", "ToastBannersFrame", UIParent)
    F:SetScript("OnHide", RestoreSettings)
    F:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    F:SetPoint("TOP", 0, getFrameY())
    F:SetScale(getFrameScale())
    F:Hide()

    layerA   = CreateLayer(F)
    layerB   = CreateLayer(F)
    -- New layers start visible: left that way, the first banner after a login or reload took the spare layer for a
    -- banner already on screen and crossfaded out of it (its full-width divider shrinking under the new one)
    resetLayer(layerA)
    resetLayer(layerB)
    curLayer = layerA
    oldLayer = layerB

    anim = { phase = "idle", elapsed = 0, holdDur = 4 }
    active = nil
    activeTitle = nil
    activeTypeName = nil
    queue = {}
    crossfadeStartAlpha = 1
    subtitleTransition = nil
    addon.Presence.pendingDiscovery = nil

    addon.Presence.frame = F
    addon.Presence.anim = anim
    addon.Presence.active = function() return active end
    addon.Presence.activeTitle = function() return activeTitle end
    addon.Presence.animPhase = function() return anim.phase end
end

PlayCinematic = function(typeName, title, subtitle, opts)
    local cfg = TYPES[typeName]
    if not cfg then return end

    opts = opts or {}
    if not opts.ignoreTypeEnabled and not IsTypeEnabledForType(typeName) then return end
    cachedCompactLayout = (typeName == "QUEST_UPDATE" or typeName == "SCENARIO_UPDATE") and (addon.GetDB and addon.GetDB("presenceHideQuestUpdateTitle", false))

    if typeName == "QUEST_UPDATE" and subtitle and addon.Presence.NormalizeQuestUpdateText then
        lastQuestUpdateNorm = addon.Presence.NormalizeQuestUpdateText(subtitle)
        lastQuestUpdateTime = GetTime()
    end

    ApplyToastContentToLayer(curLayer, typeName, title, subtitle, opts)
    -- a preview is drawn above everything, with the settings window it was started from out of the way
    F:SetFrameStrata(opts.preview and "DIALOG" or "MEDIUM")
    if opts.preview then HideSettingsForPreview() else RestoreSettings() end
    activeOpts, activeSubtitle = opts, subtitle

    cachedSubGap = curLayer.subGap or 10
    active        = cfg
    activeTitle   = title
    activeTypeName = typeName
    anim.elapsed = 0
    discoveryClock, discoveryFrom = 0, 0
    anim.holdDur = cfg.dur * getHoldScale()

    -- Cache per-animation values; reset trackers so first frame always writes.
    cachedEntranceDur  = getEntranceDur()
    cachedExitDur      = getExitDur()
    cachedHasDiscovery = (curLayer.discoveryText:GetText() or "") ~= ""
    lastTitleOffsetY   = nil
    lastSubOffsetY     = nil
    lastDividerWidth   = nil

    if oldLayer.titleText:GetAlpha() > 0 then
        anim.phase = "crossfade"
    else
        anim.phase = "entrance"
    end

    if IsDebugLive() then
        local src = (opts.source and (" via %s"):format(opts.source)) or ""
        addon.Log.debug("presence",("Play %s \"%s\" | \"%s\" phase=%s%s"):format(typeName, tostring(title or ""):gsub('"', "'"), tostring(subtitle or ""):gsub('"', "'"), anim.phase, src))
    end

    F:SetScript("OnUpdate", PresenceOnUpdate)
    F:SetAlpha(1)
    F:Show()
end

-- Update the subtitle text of the currently displayed cinematic (e.g. subzone soft-update).
-- Uses a quick fade-out/fade-in transition instead of instant swap.
-- @param newSub string New subtitle text
-- @return nil
local function SoftUpdateSubtitle(newSub)
    if not curLayer then return end
    local txt = newSub or ""
    if (curLayer.subText:GetText() or "") == txt then return end
    if subtitleTransition then
        subtitleTransition.newText = txt
    else
        subtitleTransition = { phase = "fadeOut", elapsed = 0, newText = txt }
    end
    if anim.phase == "hold" then
        anim.elapsed = 0
    end
end

-- Show the "Discovered" line on the current layer (zone/subzone discovery).
-- @return nil
local function ShowDiscoveryLine()
    if not curLayer then return end
    if addon.GetDB and not addon.GetDB("showPresenceDiscovery", true) then return end
    curLayer.discoveryText:SetText(L["PRESENCE_DISCOVERED"])
    curLayer.discoveryShadow:SetText(L["PRESENCE_DISCOVERED"])
    local dc = (activeTypeName and getTypeColor(activeTypeName, "discovery")) or getDiscoveryColor()
    curLayer.discoveryText:SetTextColor(dc[1], dc[2], dc[3], 1)
    curLayer.discoveryShadow:SetTextColor(0, 0, 0, (addon.SHADOW_A ~= nil) and addon.SHADOW_A or 0.8)
    if not cachedHasDiscovery then
        discoveryFrom = discoveryClock -- fades in from now if the banner is already past its fade
    end
    cachedHasDiscovery = true
end

-- Set flag so next zone/subzone change shows "Discovered" line.
-- @return nil
local function SetPendingDiscovery()
    addon.Presence.pendingDiscovery = true
end

local function interruptCurrent()
    crossfadeStartAlpha = curLayer.titleText:GetAlpha()
    oldLayer, curLayer = curLayer, oldLayer
    active         = nil
    activeTitle    = nil
    activeTypeName = nil
end

local ZONE_ANIM_TYPES = { ZONE_CHANGE = true, SUBZONE_CHANGE = true }

-- Stops any active zone/subzone animation and purges zone entries from the queue.
local function CancelZoneAnim()
    if not F then return end
    if activeTypeName and ZONE_ANIM_TYPES[activeTypeName] then
        addon.Trace("CancelZoneAnim stops %s in phase %s at %.2fs", activeTypeName, anim.phase, anim.elapsed)
        F:SetScript("OnUpdate", nil)
        subtitleTransition = nil
        anim.phase      = "idle"
        anim.elapsed    = 0
        active          = nil
        activeTitle     = nil
        activeTypeName  = nil
        resetLayer(curLayer)
        resetLayer(oldLayer)
        F:Hide()
    end
    if queue then
        local kept = {}
        for _, entry in ipairs(queue) do
            if not ZONE_ANIM_TYPES[entry[1]] then kept[#kept + 1] = entry end
        end
        queue = kept
    end
end

-- Queue or immediately play a cinematic notification.
-- @param typeName string LEVEL_UP, BOSS_EMOTE, ACHIEVEMENT, QUEST_COMPLETE, etc.
-- @param title string Heading text (first line)
-- @param subtitle string Second line text
-- @param opts table|nil Optional; opts.questID for colour/icon, opts.category for SCENARIO_START, opts.source for debug (event name)
-- @return nil
local function QueueOrPlay(typeName, title, subtitle, opts)
    if not F then Init() end
    local cfg = TYPES[typeName]
    if not cfg then return end

    opts = opts or {}
    if not opts.ignoreTypeEnabled and not IsTypeEnabledForType(typeName) then return end

    -- Dedupe: skip QUEST_UPDATE if same normalized text shown recently
    if typeName == "QUEST_UPDATE" and subtitle and addon.Presence.NormalizeQuestUpdateText then
        local norm = addon.Presence.NormalizeQuestUpdateText(subtitle)
        if norm and norm ~= "" and lastQuestUpdateNorm == norm and (GetTime() - (lastQuestUpdateTime or 0)) < QUEST_UPDATE_DEDUPE_TIME then
            return
        end
    end

    if active then
        if cfg.liveUpdate and activeTypeName == typeName
            and (anim.phase == "entrance" or anim.phase == "hold") then
            local newSub = subtitle or ""
            local curSub = (curLayer and curLayer.subText and curLayer.subText:GetText()) or ""
            if newSub ~= curSub then
                if subtitleTransition then
                    subtitleTransition.newText = newSub
                else
                    subtitleTransition = { phase = "fadeOut", elapsed = 0, newText = newSub }
                end
                if anim.phase == "hold" then anim.elapsed = 0 end
                if typeName == "QUEST_UPDATE" and addon.Presence.NormalizeQuestUpdateText then
                    lastQuestUpdateNorm = addon.Presence.NormalizeQuestUpdateText(newSub)
                    lastQuestUpdateTime = GetTime()
                end
                if IsDebugLive() then
                    local src = (opts.source and (" via %s"):format(opts.source)) or ""
                    addon.Log.debug("presence",("LiveUpdate %s \"%s\"%s"):format(typeName, tostring(newSub):gsub('"', "'"), src))
                end
            end
            return
        end

        -- ----------------------------------------------------------------
        -- 2. PRIORITY PREEMPT: incoming event has strictly higher priority
        --    than what is playing.  Interrupt with a crossfade so the more
        --    important notification is never delayed by a queue drain.
        -- ----------------------------------------------------------------
        if cfg.pri > active.pri then
            if IsDebugLive() then
                local src = (opts.source and (" via %s"):format(opts.source)) or ""
                addon.Log.debug("presence",("Preempt %s (pri=%d) over %s (pri=%d)%s"):format(typeName, cfg.pri, activeTypeName or "?", active.pri, src))
            end
            interruptCurrent()
            PlayCinematic(typeName, title, subtitle, opts)
            return
        end

        if #queue < MAX_QUEUE then
            -- Exact-duplicate guard: skip if same type+title is already active
            if activeTitle == title and activeTypeName == typeName then return end

            if cfg.replaceInQueue then
                -- Replace the last same-type entry in the queue instead of appending.
                -- This keeps the queue small during rapid same-type bursts (e.g. mob kills).
                for i = #queue, 1, -1 do
                    if queue[i][1] == typeName then
                        queue[i] = { typeName, title, subtitle, opts }
                        if IsDebugLive() then
                            local src = (opts.source and (" via %s"):format(opts.source)) or ""
                            addon.Log.debug("presence",("QueueReplace[%d] %s | \"%s\"%s"):format(i, typeName, tostring(subtitle or ""):gsub('"', "'"), src))
                        end
                        return
                    end
                end
            end

            queue[#queue + 1] = { typeName, title, subtitle, opts }
            if IsDebugLive() then
                local src = (opts.source and (" via %s"):format(opts.source)) or ""
                addon.Log.debug("presence",("Queued %s | \"%s\" | \"%s\" (q=%d)%s"):format(typeName, tostring(title):gsub('"', "'"), tostring(subtitle or ""):gsub('"', "'"), #queue, src))
            end
        else
            if IsDebugLive() then
                local src = (opts.source and (" via %s"):format(opts.source)) or ""
                addon.Log.debug("presence",("QueueFull – dropped %s%s"):format(typeName, src))
            end
        end
    else
        if IsDebugLive() then
            local src = (opts.source and (" via %s"):format(opts.source)) or ""
            addon.Log.debug("presence",("QueueOrPlay: play %s | \"%s\" | \"%s\"%s"):format(typeName, tostring(title or ""):gsub('"', "'"), tostring(subtitle or ""):gsub('"', "'"), src))
        end
        PlayCinematic(typeName, title, subtitle, opts)
    end
end

-- Remove any queued QUEST_UPDATE entries for the given questID.
-- Called when a quest is disposed (turned in / removed) so stale progress toasts don't play after completion.
-- @param questID number
local function PurgeQueuedQuestUpdates(questID)
    if not questID or not queue or #queue == 0 then return end
    local kept = {}
    for _, entry in ipairs(queue) do
        if not (entry[1] == "QUEST_UPDATE" and entry[4] and entry[4].questID == questID) then
            kept[#kept + 1] = entry
        end
    end
    queue = kept
end

-- Hide frame, clear queue, reset animation state.
-- @return nil
local function HideAndClear()
    if not F then return end
    F:SetScript("OnUpdate", nil)
    anim.phase      = "idle"
    active          = nil
    activeTitle     = nil
    activeTypeName  = nil
    queue = {}
    subtitleTransition = nil
    addon.Presence.pendingDiscovery = nil
    resetLayer(curLayer)
    resetLayer(oldLayer)
    F:Hide()
end

-- Dump Presence internal state to chat for debugging.
-- @return nil
local function DumpDebug()
    if not F then Init() end
    local p = addon.HSPrint or function(msg) print("|cFF00CCFFHorizon Suite:|r " .. tostring(msg or "")) end

    p("|cFF00CCFF--- Presence debug ---|r")
    p("Frame: created, visible=" .. tostring(F and F:IsVisible()))
    p("Module enabled: " .. tostring(addon.IsModuleEnabled and addon:IsModuleEnabled("presence") or "?"))

    if InCombatLockdown then
        p("In combat: " .. tostring(InCombatLockdown()))
    end

    if anim then
        p("Anim phase: " .. tostring(anim.phase) .. ", elapsed: " .. tostring(anim.elapsed) .. ", holdDur: " .. tostring(anim.holdDur))
    end

    if active then
        local sub = (curLayer and curLayer.subText and curLayer.subText:GetText()) or ""
        p("Active: typeName=\"" .. tostring(activeTypeName) .. "\" title=\"" .. tostring(activeTitle) .. "\" subtitle=\"" .. tostring(sub):gsub('"', '\\"') .. "\" pri=" .. tostring(active.pri))
    else
        p("Active: (none)")
    end

    p("Pending discovery: " .. tostring(addon.Presence.pendingDiscovery or false))
    p("Queue: " .. tostring(#queue) .. " entries")
    for i, e in ipairs(queue) do
        p("  [" .. tostring(i) .. "] " .. tostring(e[1]) .. " | \"" .. tostring(e[2]):gsub('"', '\\"') .. "\" | \"" .. tostring(e[3]):gsub('"', '\\"') .. "\"")
    end

    if addon.GetDB then
        p("Options: showPresenceDiscovery=" .. tostring(addon.GetDB("showPresenceDiscovery", true)) .. ", showPresenceQuestTypeIcons=" .. tostring(addon.GetDB("showPresenceQuestTypeIcons", true)) .. ", presenceIconSize=" .. tostring(addon.GetDB("presenceIconSize", 24)))
    end

    if GetZoneText then
        p("Current zone: " .. tostring(GetZoneText()) .. " / " .. tostring(GetSubZoneText()))
    end

    if addon.Presence.DumpBlizzardSuppression then
        addon.Presence.DumpBlizzardSuppression(p)
    end

    if addon.Presence.DumpQuestObjectiveCaches then
        addon.Presence.DumpQuestObjectiveCaches(p)
    end

    p("|cFF00CCFF--- End Presence debug ---|r")
end

-- ============================================================================
-- Exports
-- ============================================================================

-- Redraw a preview banner that's on screen with the current settings, and hold it there, so changes to fonts,
-- sizes, colors and spacing show while they're made.
-- @return nil
local function RefreshPreview()
    if not (F and active and activeOpts and activeOpts.preview) then return end
    if cachedHasDiscovery then addon.Presence.pendingDiscovery = true end
    ApplyToastContentToLayer(curLayer, activeTypeName, activeTitle, activeSubtitle, activeOpts)
    resetLayer(oldLayer)
    cachedSubGap        = curLayer.subGap or 10
    cachedCompactLayout = (activeTypeName == "QUEST_UPDATE" or activeTypeName == "SCENARIO_UPDATE") and (addon.GetDB and addon.GetDB("presenceHideQuestUpdateTitle", false))
    cachedHasDiscovery  = (curLayer.discoveryText:GetText() or "") ~= ""
    lastTitleOffsetY, lastSubOffsetY, lastDividerWidth = nil, nil, nil
    subtitleTransition = nil
    finalizeEntrance()
    anim.phase   = "hold"
    anim.elapsed = 0
end

-- Re-apply frame position and scale from DB. Call when presence options change.
-- Also re-applies fonts to any currently-showing toast layers so that global font
-- toggle changes take effect immediately without waiting for the next toast.
-- @return nil
local function ApplyPresenceOptions()
    if not F then return end
    F:ClearAllPoints()
    F:SetPoint("TOP", 0, getFrameY())
    F:SetScale(getFrameScale())
    local function reapplyLayerFonts(layer)
        if not layer then return end
        -- getSize is optional: title/subtitle keep their per-toast variant size (preserved
        -- from the font string), while discovery re-reads its own configured size.
        local function fix(fs, getPath, getOutline, getSize)
            if not fs then return end
            local _, sz = fs:GetFont()
            local size = (getSize and getSize()) or sz
            if size then SetSafeFont(fs, getPath(), size, getOutline()) end
        end
        fix(layer.titleText,       getPresenceTitleFontPath,     getPresenceTitleFontOutline)
        fix(layer.titleShadow,     getPresenceTitleFontPath,     getPresenceTitleFontOutline)
        fix(layer.subText,         getPresenceSubtitleFontPath,  getPresenceSubtitleFontOutline)
        fix(layer.subShadow,       getPresenceSubtitleFontPath,  getPresenceSubtitleFontOutline)
        fix(layer.discoveryText,   getPresenceDiscoveryFontPath, getPresenceDiscoveryFontOutline, getPresenceDiscoverySize)
        fix(layer.discoveryShadow, getPresenceDiscoveryFontPath, getPresenceDiscoveryFontOutline, getPresenceDiscoverySize)
    end
    reapplyLayerFonts(curLayer)
    reapplyLayerFonts(oldLayer)
    RefreshPreview()
    if addon.Presence.RefreshPreviewWindow then addon.Presence.RefreshPreviewWindow() end
end

-- Returns the typeName of the currently playing or holding cinematic.
local function GetActiveTypeName()
    return activeTypeName
end

-- Build preview sample for a toast type. Uses addon.L for localized strings.
-- @param typeName string One of TYPES keys
-- @return table|nil { title, subtitle, opts?, withDiscovery? } or nil if unknown
local function getPreviewSample(typeName)
    if not TYPES[typeName] then return nil end
    local L = addon.L or {}
    if typeName == "ZONE_CHANGE" then
        local zone, sub = GetZoneText() or "", GetSubZoneText() or ""
        if addon.GetDB("presenceZoneEntryNameOnly", false) then sub = "" end
        return { title = zone ~= "" and zone or "Elwynn Forest", subtitle = sub ~= zone and sub or "", withDiscovery = true }
    end
    if typeName == "SUBZONE_CHANGE" then
        local zone, sub = GetZoneText() or "", GetSubZoneText() or ""
        if sub == "" or sub == zone then
            return { title = "Goldshire", subtitle = zone ~= "" and zone or "Elwynn Forest", withDiscovery = true }
        end
        return { title = sub, subtitle = zone, withDiscovery = true }
    end
    if typeName == "QUEST_ACCEPT" then
        return { title = L["PRESENCE_QUEST_ACCEPTED"], subtitle = L["PRESENCE_THE_FATE_OF_THE_HORDE"], opts = { previewAtlas = "QuestNormal" } }
    end
    if typeName == "WORLD_QUEST_ACCEPT" then
        return { title = L["PRESENCE_WORLD_QUEST_ACCEPTED"], subtitle = "Azerite Mining", opts = { previewAtlas = "quest-recurring-available" } }
    end
    if typeName == "QUEST_UPDATE" then
        return { title = L["PRESENCE_QUEST_UPDATE"], subtitle = "Boar Pelts: 7/10", opts = { previewAtlas = "QuestNormal" } }
    end
    if typeName == "QUEST_COMPLETE" then
        return { title = L["PRESENCE_QUEST_COMPLETE"], subtitle = L["PRESENCE_OBJECTIVE_SECURED"], opts = { previewAtlas = "QuestTurnin" } }
    end
    if typeName == "WORLD_QUEST" then
        return { title = L["PRESENCE_WORLD_QUEST_COMPLETE"], subtitle = "Azerite Mining", opts = { previewAtlas = "quest-recurring-available" } }
    end
    if typeName == "SCENARIO_START" then
        return { title = "Cinderbrew Meadery", subtitle = "Defend the tavern from attackers", opts = { category = "SCENARIO" } }
    end
    if typeName == "SCENARIO_UPDATE" then
        return { title = "Scenario", subtitle = "Dragon Glyphs: 3/5", opts = { category = "SCENARIO" } }
    end
    if typeName == "SCENARIO_COMPLETE" then
        return { title = L["PRESENCE_SCENARIO_COMPLETE"], subtitle = "Objective completed", opts = { category = "SCENARIO" } }
    end
    if typeName == "ACHIEVEMENT" then
        return { title = L["PRESENCE_ACHIEVEMENT_EARNED"], subtitle = L["PRESENCE_EXPLORING_KHAZ_ALGAR"] }
    end
    if typeName == "ACHIEVEMENT_PROGRESS" then
        return { title = L["PRESENCE_EXPLORING_THE_MIDNIGHT_ISLES"], subtitle = "Dragon Glyphs: 3/5" }
    end
    if typeName == "BOSS_EMOTE" then
        return { title = "Ragnaros", subtitle = "BY FIRE BE PURGED!" }
    end
    if typeName == "BOSS_DEFEATED" then
        return { title = L["BOSS_DEFEATED"], subtitle = "Edwin VanCleef", opts = { category = "DUNGEON" } }
    end
    if typeName == "BONUS_OBJECTIVE_ACCEPT" then
        return { title = L["BONUS_OBJECTIVE"], subtitle = "Defias Brotherhood", opts = { previewAtlas = "QuestBonusObjective" } }
    end
    if typeName == "BONUS_OBJECTIVE" then
        return { title = L["BONUS_OBJECTIVE_COMPLETE"], subtitle = "Defias Brotherhood", opts = { previewAtlas = "QuestBonusObjective" } }
    end
    if typeName == "LEVEL_UP" then
        local fmt = L["PRESENCE_YOU_HAVE_REACHED_LEVEL_X"]
        return { title = L["PRESENCE_LEVEL_UP"], subtitle = fmt:format(UnitLevel("player") or "") }
    end
    if typeName == "RARE_DEFEATED" then
        return { title = L["PRESENCE_RARE_DEFEATED"], subtitle = "Gorged Great-Horn" }
    end
    return nil
end

-- Preview a toast type with sample data: the real banner, shown right away (replacing any banner on screen) and
-- above the settings window. Used by options and slash commands.
-- @param typeName string One of TYPES keys (LEVEL_UP, QUEST_COMPLETE, etc.)
-- @return nil
local function PreviewToast(typeName)
    local sample = getPreviewSample(typeName)
    if not sample then return end
    if not F then Init() end
    HideAndClear()
    if sample.withDiscovery then
        SetPendingDiscovery()
    end
    local opts = {}
    for k, v in pairs(sample.opts or {}) do opts[k] = v end
    opts.ignoreTypeEnabled = true
    opts.preview = true
    PlayCinematic(typeName, sample.title, sample.subtitle, opts)
end

-- ============================================================================
-- PREVIEW WINDOW: a banner drawn still, in a movable window, redrawn as settings change
-- ============================================================================

local WINDOW_NAME = "ToastBannersPreviewWindow"
local PREVIEW_W, PREVIEW_H = FRAME_WIDTH, 300  -- room above and below the divider for the largest settings
local PREVIEW_DIVIDER_Y = -150
local previewWindow, previewHolder, previewLayer, previewTypeName

-- Draw the banner in its finished state (where the entrance animation ends)
local function DrawPreviewWindow()
    local sample = getPreviewSample(previewTypeName)
    local cfg = TYPES[previewTypeName]
    if not (sample and cfg) then return end

    local opts = {}
    for k, v in pairs(sample.opts or {}) do opts[k] = v end
    opts.showDiscovery = sample.withDiscovery and addon.GetDB("showPresenceDiscovery", true) or nil
    -- the layer code clears a pending "Discovered" line once it shows one; this one isn't the real banner's
    local pending = addon.Presence.pendingDiscovery
    ApplyToastContentToLayer(previewLayer, previewTypeName, sample.title, sample.subtitle, opts)
    addon.Presence.pendingDiscovery = pending

    local layer = previewLayer
    local compact = (previewTypeName == "QUEST_UPDATE" or previewTypeName == "SCENARIO_UPDATE")
        and addon.GetDB("presenceHideQuestUpdateTitle", false)
    layer.divider:ClearAllPoints()
    layer.divider:SetPoint("TOP", 0, PREVIEW_DIVIDER_Y)
    layer.divider:SetSize(DIVIDER_W, DIVIDER_H)
    layer.divider:SetAlpha(0.5)
    layer.titleText:ClearAllPoints()
    layer.titleText:SetPoint("BOTTOM", layer.divider, "TOP", 0, layer.titleGap or 0)
    layer.titleText:SetAlpha(compact and 0 or 1)
    layer.titleShadow:SetAlpha(compact and 0 or 0.8)
    if layer.questTypeIcon:IsShown() then layer.questTypeIcon:SetAlpha(1) end
    layer.subText:ClearAllPoints()
    layer.subText:SetPoint("TOP", layer.divider, "BOTTOM", 0, -(layer.subGap or 10))
    layer.discoveryText:ClearAllPoints()
    layer.discoveryText:SetPoint("TOP", layer.subText, "BOTTOM", 0, -(layer.discoveryGap or 5))
    layer.subText:SetAlpha(1)
    layer.subShadow:SetAlpha(0.8)
    local hasDiscovery = (layer.discoveryText:GetText() or "") ~= ""
    layer.discoveryText:SetAlpha(hasDiscovery and 1 or 0)
    layer.discoveryShadow:SetAlpha(hasDiscovery and 0.8 or 0)

    -- at the banners' own scale, as large as fits on screen
    local scale = math.min(getFrameScale(), (UIParent:GetWidth() - 80) / PREVIEW_W, (UIParent:GetHeight() - 120) / PREVIEW_H)
    previewHolder:SetScale(scale)
    previewWindow:SetSize(PREVIEW_W * scale + 24, PREVIEW_H * scale + 70)
    local label = addon.PREVIEW_LABELS and addon.PREVIEW_LABELS[previewTypeName] or previewTypeName
    previewWindow:SetTitle("Toast Banners: " .. label)
end

local function CreatePreviewWindow()
    local window = CreateFrame("Frame", WINDOW_NAME, UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(window)
    ButtonFrameTemplate_HideButtonBar(window)
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetPoint("TOP", 0, -60)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    tinsert(UISpecialFrames, WINDOW_NAME) -- Escape closes it

    previewHolder = CreateFrame("Frame", nil, window.Inset)
    previewHolder:SetSize(PREVIEW_W, PREVIEW_H)
    previewHolder:SetPoint("CENTER")
    previewLayer = CreateLayer(previewHolder)
    return window
end

-- Open the preview window on a banner type (or switch it to that type)
local function ShowPreviewWindow(typeName)
    previewWindow = previewWindow or CreatePreviewWindow()
    previewTypeName = typeName
    DrawPreviewWindow()
    previewWindow:Show()
    previewWindow:Raise()
end

-- Redraw the open preview window with the current settings, on typeName when given
local function RefreshPreviewWindow(typeName)
    if not (previewWindow and previewWindow:IsShown()) then return end
    previewTypeName = typeName or previewTypeName
    DrawPreviewWindow()
end

addon.Log.registerTag("presence", "presenceDebugLive")

addon.Presence.Init               = Init
addon.Presence.ApplyPresenceOptions = ApplyPresenceOptions
addon.Presence.QueueOrPlay        = QueueOrPlay
addon.Presence.CancelZoneAnim     = CancelZoneAnim
addon.Presence.SoftUpdateSubtitle = SoftUpdateSubtitle
addon.Presence.ShowDiscoveryLine  = ShowDiscoveryLine
addon.Presence.SetPendingDiscovery = SetPendingDiscovery
addon.Presence.HideAndClear       = HideAndClear
addon.Presence.DumpDebug          = DumpDebug
addon.Presence.DebugLog           = function(msg) addon.Log.debug("presence", msg) end
addon.Presence.IsDebugLive        = IsDebugLive
addon.Presence.SetDebugLive       = SetDebugLive
addon.Presence.ToggleDebugLive    = ToggleDebugLive
addon.Presence.ShowDebugPanel     = presencePanel.Show
addon.Presence.HideDebugPanel     = presencePanel.Hide
addon.Presence.GetActiveTypeName  = GetActiveTypeName
addon.Presence.DISCOVERY_WAIT     = 0.15

addon.Presence.IsTypeEnabled        = IsTypeEnabled
addon.Presence.IsTypeEnabledForType  = IsTypeEnabledForType
addon.Presence.IsAnyToastEnabled     = IsAnyToastEnabled
addon.Presence.RequestDebounced     = RequestDebounced
addon.Presence.CancelDebounced      = CancelDebounced
addon.Presence.FormatObjectiveForDisplay = FormatObjectiveForDisplay
addon.Presence.PurgeQueuedQuestUpdates   = PurgeQueuedQuestUpdates
addon.Presence.ShouldSuppressType   = ShouldSuppressType
addon.Presence.IsFlightSuppressed   = IsFlightSuppressed
addon.Presence.TYPE_OPTIONS         = TYPE_OPTIONS
addon.Presence.PreviewToast         = PreviewToast
addon.Presence.PREVIEW_TYPE_ORDER   = PREVIEW_TYPE_ORDER
addon.Presence.PREVIEW_TYPE_LABELS = PREVIEW_TYPE_LABELS
addon.Presence.GetDefaultSize       = function(typeName) return TYPES[typeName] and getDefaultVariant(TYPES[typeName]) end
addon.Presence.GetTypeDefaultColors = getTypeDefaultColors
addon.Presence.ShowPreviewWindow    = ShowPreviewWindow
addon.Presence.RefreshPreviewWindow = RefreshPreviewWindow
