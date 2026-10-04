-- Toast Banners core: what Horizon Suite's core gave its Presence module (saved settings, strings, colors, fonts and
-- the module hooks), on the addon namespace, so the banner files keep Horizon Suite's code and API.
--
-- Settings are saved in ToastBannersDB under Horizon Suite's own key names (presenceZoneChange, ...).

local addonName, addon = ...

addon.Presence = {}

-- WoW: Forever (interface 1xxxx) still has the Delves and Mythic+ APIs, but not the content: its
-- C_PartyInfo.IsDelveInProgress even answers true outdoors. Only retail has either.
addon.IS_RETAIL = select(4, GetBuildInfo()) >= 20000
addon.HAS_DELVES = addon.IS_RETAIL and C_DelvesUI ~= nil
addon.HAS_MYTHIC_PLUS = addon.IS_RETAIL and C_MythicPlus ~= nil

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
function addon.GetDB(key, default)
    local value = ToastBannersDB and ToastBannersDB[key]
    if value == nil then return default end
    return value
end

-- Applies the settings: frame position, fonts, which Blizzard banners are hidden, and a preview on screen
function addon.ApplySettings()
    local P = addon.Presence
    if P.ApplyPresenceOptions then P.ApplyPresenceOptions() end
    if P.ApplyBlizzardSuppression then P.ApplyBlizzardSuppression() end
end

function addon.SetDB(key, value)
    ToastBannersDB[key] = value
    addon.ApplySettings()
end

-- Defaults of the settings the options page shows; the banner code has the same defaults built in
addon.DEFAULTS = {
    showPresenceQuestTypeIcons     = true,
    presenceIconSize               = 24,
    presenceHideQuestUpdateTitle   = false,
    showPresenceDiscovery          = true,
    presenceFrameY                 = -180,
    presenceFrameScale             = 1,
    presenceAnimations             = true,
    presenceEntranceDur            = 0.7,
    presenceExitDur                = 0.8,
    presenceHoldScale              = 1,
    presenceZoneChange             = true,
    presenceZoneEntryNameOnly      = false,
    presenceHideZoneForSubzone     = false,
    presenceSuppressZoneInMplus    = true,
    presenceSuppressInDungeon      = false,
    presenceSuppressInDelve        = false,
    presenceSuppressInRaid         = false,
    presenceSuppressInPvP          = false,
    presenceSuppressInBattleground = false,
    presenceLevelUp                = true,
    presenceBossEmote              = true,
    presenceAchievement            = true,
    presenceAchievementProgress    = false,
    presenceQuestEvents            = true,
    presenceRareDefeated           = true,
    presenceTitleFontPath          = "__global__",
    presenceSubtitleFontPath       = "__global__",
    presenceDiscoveryFontPath      = "__global__",
    presenceTitleFontOutline       = "OUTLINE",
    presenceSubtitleFontOutline    = "OUTLINE",
    presenceDiscoveryFontOutline   = "OUTLINE",
    presencePrimaryLargeSz         = 48,
    presenceSecondaryLargeSz       = 24,
    presenceTitleGapLarge          = 17,
    presencePrimaryMediumSz        = 36,
    presenceSecondaryMediumSz      = 22,
    presenceTitleGapMedium         = 29,
    presencePrimarySmallSz         = 28,
    presenceSecondarySmallSz       = 20,
    presenceTitleGapSmall          = 37,
    presenceDiscoverySize          = 16,
    presenceZoneTypeColoring       = false,
}

-- Color settings, saved as { r, g, b }
addon.COLOR_DEFAULTS = {
    presenceBossEmoteColor     = { 1, 0.2, 0.2 },
    presenceDiscoveryColor     = { 0.4, 1, 0.5 },
    presenceZoneColorFriendly  = { 0.1, 1.0, 0.1 },
    presenceZoneColorHostile   = { 1.0, 0.1, 0.1 },
    presenceZoneColorContested = { 1.0, 0.7, 0.0 },
    presenceZoneColorSanctuary = { 0.41, 0.8, 0.94 },
}

function addon.GetColorSetting(key)
    local c = addon.GetDB(key)
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return c
    end
    return addon.COLOR_DEFAULTS[key]
end

---------------------------------------------------------------------------
-- Strings (Horizon Suite's enUS text)
---------------------------------------------------------------------------
addon.L = {
    FOCUS_DELVE_COMPLETE                  = "Delve Complete",
    PRESENCE_ACHIEVEMENT_EARNED           = "ACHIEVEMENT EARNED",
    PRESENCE_AIDING_THE_ACCORD            = "Aiding the Accord",
    PRESENCE_AZERITE_MINING               = "Azerite Mining",
    PRESENCE_DISCOVERED                   = "Discovered",
    PRESENCE_DRAGON_GLYPHS_3_5            = "Dragon Glyphs: 3/5",
    PRESENCE_EXPLORING_KHAZ_ALGAR         = "Exploring Khaz Algar",
    PRESENCE_EXPLORING_THE_MIDNIGHT_ISLES = "Exploring the Midnight Isles",
    PRESENCE_LEVEL_UP                     = "LEVEL UP",
    PRESENCE_NEW_QUEST                    = "New Quest",
    PRESENCE_OBJECTIVE_SECURED            = "Objective Secured",
    PRESENCE_QUEST_ACCEPTED               = "QUEST ACCEPTED",
    PRESENCE_QUEST_COMPLETE               = "QUEST COMPLETE",
    PRESENCE_QUEST_UPDATE                 = "QUEST UPDATE",
    PRESENCE_RARE_DEFEATED                = "RARE DEFEATED",
    PRESENCE_SCENARIO_COMPLETE            = "Scenario Complete",
    PRESENCE_THE_FATE_OF_THE_HORDE        = "The Fate of the Horde",
    PRESENCE_WORLD_QUEST_ACCEPTED         = "WORLD QUEST ACCEPTED",
    PRESENCE_WORLD_QUEST_COMPLETE         = "WORLD QUEST COMPLETE",
    PRESENCE_YOU_HAVE_REACHED_LEVEL_80    = "You have reached level 80",
    PRESENCE_YOU_HAVE_REACHED_LEVEL_X     = "You have reached level %s",
    UI_PREY                               = "Prey",
}

---------------------------------------------------------------------------
-- Chat output, and Horizon Suite's debug log (not included: its calls do nothing)
---------------------------------------------------------------------------
function addon.HSPrint(msg)
    print("|cffffd200Toast Banners|r: " .. tostring(msg or ""))
end

local function Noop() end
addon.Log = {
    isEnabled   = function() return false end,
    debug       = Noop,
    registerTag = Noop,
    enableTag   = Noop,
    createPanel = function() return { Show = Noop, Hide = Noop } end,
}

---------------------------------------------------------------------------
-- The banners are Horizon Suite's "presence" module, always on while the addon is loaded
---------------------------------------------------------------------------
function addon:IsModuleEnabled()
    return true
end

---------------------------------------------------------------------------
-- Colors (Horizon Suite's Config.lua)
---------------------------------------------------------------------------
addon.SHADOW_OX = 2
addon.SHADOW_OY = -2
addon.SHADOW_A  = 0.8

-- Title colors by type of quest or notification
addon.QUEST_COLORS = {
    DEFAULT     = { 0.90, 0.90, 0.90 },
    CAMPAIGN    = { 1.00, 0.82, 0.00 },  -- Blizzard's gold (NORMAL_FONT_COLOR)
    IMPORTANT   = { 1.00, 0.45, 0.80 },
    LEGENDARY   = { 1.00, 0.50, 0.00 },
    DUNGEON     = { 0.64, 0.21, 0.93 },
    RAID        = { 0.85, 0.25, 0.25 },
    DELVES      = { 0.32, 0.72, 0.68 },
    SCENARIO    = { 0.38, 0.52, 0.88 },
    WORLD       = { 0.78, 0.42, 0.95 },
    WEEKLY      = { 0.25, 0.88, 0.92 },
    PREY        = { 0.72, 0.22, 0.22 },
    DAILY       = { 0.25, 0.88, 0.92 },
    CALLING     = { 0.20, 0.60, 1.00 },
    COMPLETE    = { 0.20, 1.00, 0.40 },
    ACHIEVEMENT = { 0.78, 0.48, 0.22 },
}

function addon.GetQuestColor(category)
    return addon.QUEST_COLORS[category] or addon.QUEST_COLORS.DEFAULT
end

addon.PRESENCE_BOSS_EMOTE_COLOR = addon.COLOR_DEFAULTS.presenceBossEmoteColor
addon.PRESENCE_DISCOVERY_COLOR  = addon.COLOR_DEFAULTS.presenceDiscoveryColor

function addon.GetPresenceBossEmoteColor()
    return addon.GetColorSetting("presenceBossEmoteColor")
end

function addon.GetPresenceDiscoveryColor()
    return addon.GetColorSetting("presenceDiscoveryColor")
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
function addon.GetDefaultFontPath()
    local path = GameFontNormal and GameFontNormal:GetFont()
    if path and path ~= "" then return path end
    return "Fonts\\FRIZQT__.TTF"
end

-- A saved font is a file path, or the name of a LibSharedMedia font (when another addon provides the library)
function addon.ResolveFontPath(value)
    if type(value) ~= "string" or value == "" then
        return addon.GetDefaultFontPath()
    end
    if value:find("\\") or value:find("/") then
        return value
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.Fetch then
        local ok, path = pcall(LSM.Fetch, LSM, "font", value, true)
        if ok and type(path) == "string" and path ~= "" then
            return path
        end
    end
    return addon.GetDefaultFontPath()
end

-- Font choices: the game's fonts, then any LibSharedMedia fonts
function addon.GetFontOptions()
    local options = {
        { label = "Default", value = "__global__", tooltip = "The game's standard font." },
        { label = "Friz Quadrata", value = "Fonts\\FRIZQT__.TTF" },
        { label = "Arial Narrow", value = "Fonts\\ARIALN.TTF" },
        { label = "Morpheus", value = "Fonts\\MORPHEUS.TTF" },
        { label = "Skurri", value = "Fonts\\SKURRI.TTF" },
    }
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.List then
        local builtIn = {}
        for _, option in ipairs(options) do builtIn[option.label] = true end
        for _, name in ipairs(LSM:List("font")) do
            if not builtIn[name] then
                options[#options + 1] = { label = name, value = name }
            end
        end
    end
    return options
end

---------------------------------------------------------------------------
-- Startup: load settings, then start the banners (Horizon Suite's OnInit and OnEnable for the module)
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    ToastBannersDB = ToastBannersDB or {}

    local P = addon.Presence
    P.Init()
    P.EnableEvents()
    P.SuppressBlizzard()
    P.ApplyAlertMuting()
    P.HookUIErrorsFrame()
    if addon.RefreshOptions then addon.RefreshOptions() end
end)
