-- Options page (Options > AddOns > Toast Banners), drawn in Blizzard's settings style by SettingsKit

local _, addon = ...
local Kit = addon.SettingsKit
local D = addon.DEFAULTS
local GetDB, SetDB = addon.GetDB, addon.SetDB

local function Get(key)
    return function()
        local value = GetDB(key)
        if value == nil then return D[key] end
        return value
    end
end

local function Set(key)
    return function(value) SetDB(key, value) end
end

-- Notification types that follow a grouped setting (Horizon Suite's older "all quest events" options) until changed
local function GetWithFallback(key, fallbackKey)
    return function()
        local value = GetDB(key)
        if value ~= nil then return value end
        return GetDB(fallbackKey, true)
    end
end

local function GetColor(key)
    return function() return unpack(addon.GetColorSetting(key)) end
end

local function SetColor(key)
    return function(r, g, b) SetDB(key, { r, g, b }) end
end

local function Seconds(v) return ("%.1f sec"):format(v) end
local function Pixels(v) return v .. " px" end
local function Multiplier(v) return ("%.1fx"):format(v) end

local page = Kit.NewPage("Toast Banners", {
    onDefaults = function()
        local previewType = ToastBannersDB.presencePreviewType
        wipe(ToastBannersDB)
        ToastBannersDB.presencePreviewType = previewType
        addon.ApplySettings()
    end,
})
local general, notifications, typography = unpack(page:Tabs({ "General", "Notifications", "Typography" }))

---------------------------------------------------------------------------
-- Preview: plays the real banner on screen
---------------------------------------------------------------------------
local PREVIEW_TYPES = {
    { "ZONE_CHANGE", "Zone Entry", "Large" },
    { "SUBZONE_CHANGE", "Subzone Change", "Medium" },
    { "QUEST_ACCEPT", "Quest Accepted", "Medium" },
    { "WORLD_QUEST_ACCEPT", "World Quest Accepted", "Medium" },
    { "QUEST_UPDATE", "Quest Progress", "Small" },
    { "QUEST_COMPLETE", "Quest Complete", "Large" },
    { "WORLD_QUEST", "World Quest Complete", "Large" },
    { "SCENARIO_START", "Scenario Start", "Medium" },
    { "SCENARIO_UPDATE", "Scenario Progress", "Medium" },
    { "SCENARIO_COMPLETE", "Scenario Complete", "Large" },
    { "ACHIEVEMENT", "Achievement Earned", "Large" },
    { "ACHIEVEMENT_PROGRESS", "Achievement Progress", "Small" },
    { "BOSS_EMOTE", "Boss Emote", "Large" },
    { "LEVEL_UP", "Level Up", "Large" },
    { "RARE_DEFEATED", "Rare Defeated", "Medium" },
}
local previewOptions = {}
for _, entry in ipairs(PREVIEW_TYPES) do
    previewOptions[#previewOptions + 1] = { label = entry[2], value = entry[1], tooltip = entry[3] .. " notification." }
end

local function AddPreview(list)
    list:Header("Preview")
    list:Dropdown("Banner", previewOptions,
        function() return GetDB("presencePreviewType", "ZONE_CHANGE") end,
        function(value) ToastBannersDB.presencePreviewType = value end,
        "The banner Show Preview plays.")
    list:Button("Show Preview", function()
        addon.Presence.PreviewToast(GetDB("presencePreviewType", "ZONE_CHANGE"))
    end, "Shows the banner on screen, as it appears in game. While it's showing, it changes with the settings you "
        .. "change, and stays up.")
end

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------
AddPreview(general)

general:Header("Display")
general:Checkbox("Quest Type Icons", Get("showPresenceQuestTypeIcons"), Set("showPresenceQuestTypeIcons"),
    "Shows the quest's type icon (campaign, daily, world quest...) next to quest accepted, complete and progress "
    .. "banners.")
general:Slider("Quest Icon Size", 16, 36, 1, Get("presenceIconSize"), Set("presenceIconSize"), Pixels,
    "Size of the quest type icon. It's never larger than the text beside it.",
    { indent = true, enabled = Get("showPresenceQuestTypeIcons") })
general:Checkbox("Discovered Line", Get("showPresenceDiscovery"), Set("showPresenceDiscovery"),
    "Shows \"Discovered\" under the zone name when you discover a new area.")
general:Slider("Vertical Position", -300, 0, 1, Get("presenceFrameY"), Set("presenceFrameY"), nil,
    "How far down from the top of the screen the banners are shown.")
general:Slider("Scale", 0.5, 2, 0.1, Get("presenceFrameScale"), Set("presenceFrameScale"), Multiplier,
    "Size of the banners.")

general:Header("Animation")
general:Checkbox("Animations", Get("presenceAnimations"), Set("presenceAnimations"),
    "Banners fade and slide in and out. Off, they appear and disappear at once.")
local function AnimationsOn() return Get("presenceAnimations")() end
general:Slider("Entrance Duration", 0.2, 1.5, 0.1, Get("presenceEntranceDur"), Set("presenceEntranceDur"), Seconds,
    "How long a banner takes to appear.", { indent = true, enabled = AnimationsOn })
general:Slider("Exit Duration", 0.2, 1.5, 0.1, Get("presenceExitDur"), Set("presenceExitDur"), Seconds,
    "How long a banner takes to disappear.", { indent = true, enabled = AnimationsOn })
general:Slider("Hold Duration", 0.5, 2, 0.1, Get("presenceHoldScale"), Set("presenceHoldScale"), Multiplier,
    "How long banners stay on screen, as a multiple of their normal time.")

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
-- A notification type turned off shows Blizzard's own banner or alert instead, where Blizzard has one
local OFF_NOTE = "\n\nOff, Blizzard's own notification is shown instead."

notifications:Header("Zones")
notifications:Checkbox("Zone Entry", Get("presenceZoneChange"), Set("presenceZoneChange"),
    "When you enter a new zone." .. OFF_NOTE)
local SubzoneOn = GetWithFallback("presenceSubzoneChange", "presenceZoneChange")
notifications:Checkbox("Subzone Changes", SubzoneOn, Set("presenceSubzoneChange"),
    "When you move to another area within the same zone." .. OFF_NOTE)
notifications:Checkbox("Subzone Only", Get("presenceHideZoneForSubzone"), Set("presenceHideZoneForSubzone"),
    "Subzone banners show only the subzone's name, without the zone's name under it. The zone's name still "
    .. "shows when you enter a new zone.", { indent = true, enabled = SubzoneOn })

notifications:Header("Quests")
notifications:Checkbox("Quest Accepted", GetWithFallback("presenceQuestAccept", "presenceQuestEvents"),
    Set("presenceQuestAccept"), "When you accept a quest.")
notifications:Checkbox("World Quest Accepted", GetWithFallback("presenceWorldQuestAccept", "presenceQuestEvents"),
    Set("presenceWorldQuestAccept"), "When you accept a world quest.")
local QuestProgressOn = GetWithFallback("presenceQuestUpdate", "presenceQuestEvents")
notifications:Checkbox("Quest Progress", QuestProgressOn, Set("presenceQuestUpdate"),
    "When a quest objective updates (e.g. 7/10 Boar Pelts).")
notifications:Checkbox("Objective Only", Get("presenceHideQuestUpdateTitle"), Set("presenceHideQuestUpdateTitle"),
    "Quest and scenario progress banners show only the objective, without the \"Quest Update\" title.",
    { indent = true, enabled = QuestProgressOn })
notifications:Checkbox("Quest Complete", GetWithFallback("presenceQuestComplete", "presenceQuestEvents"),
    Set("presenceQuestComplete"), "When you complete a quest.")
notifications:Checkbox("World Quest Complete", GetWithFallback("presenceWorldQuest", "presenceQuestEvents"),
    Set("presenceWorldQuest"), "When you complete a world quest." .. OFF_NOTE)

notifications:Header("Scenarios")
notifications:Checkbox("Scenario Start", GetWithFallback("presenceScenarioStart", "showScenarioEvents"),
    Set("presenceScenarioStart"), "When you enter a scenario" .. (C_DelvesUI and " or Delve." or "."))
notifications:Checkbox("Scenario Progress", GetWithFallback("presenceScenarioUpdate", "showScenarioEvents"),
    Set("presenceScenarioUpdate"), "When a scenario objective updates.")
notifications:Checkbox("Scenario Complete", GetWithFallback("presenceScenarioComplete", "showScenarioEvents"),
    Set("presenceScenarioComplete"), "When you complete a scenario" .. (C_DelvesUI and " or Delve." or "."))

notifications:Header("Other")
notifications:Checkbox("Achievements", Get("presenceAchievement"), Set("presenceAchievement"),
    "When you earn an achievement." .. OFF_NOTE)
notifications:Checkbox("Achievement Progress", Get("presenceAchievementProgress"), Set("presenceAchievementProgress"),
    "When an achievement's criteria update: always for tracked achievements, and for others when the game says "
    .. "which achievement it is." .. OFF_NOTE)
notifications:Checkbox("Boss Emotes", Get("presenceBossEmote"), Set("presenceBossEmote"),
    "Raid and dungeon boss emotes." .. OFF_NOTE)
notifications:Checkbox("Level Up", Get("presenceLevelUp"), Set("presenceLevelUp"),
    "When you gain a level." .. OFF_NOTE)
notifications:Checkbox("Rare Defeated", Get("presenceRareDefeated"), Set("presenceRareDefeated"),
    "When a rare creature nearby is defeated.")

notifications:Header("Instances")
notifications:Checkbox("Hide in Dungeons", Get("presenceSuppressInDungeon"), Set("presenceSuppressInDungeon"),
    "No zone, subzone or scenario banners inside a dungeon.")
if C_DelvesUI then
    notifications:Checkbox("Hide Delve Progress", Get("presenceSuppressInDelve"), Set("presenceSuppressInDelve"),
        "No objective progress banners inside a Delve. Entering and completing it still show.")
end
if C_MythicPlus then
    notifications:Checkbox("Hide in Mythic+", Get("presenceSuppressZoneInMplus"), Set("presenceSuppressZoneInMplus"),
        "No zone, subzone or scenario banners in Mythic and Mythic+ dungeons.")
end
notifications:Checkbox("Hide in Raids", Get("presenceSuppressInRaid"), Set("presenceSuppressInRaid"),
    "No zone, subzone or scenario banners inside a raid.")
notifications:Checkbox("Hide in Arenas", Get("presenceSuppressInPvP"), Set("presenceSuppressInPvP"),
    "No zone, subzone or scenario banners inside an arena.")
notifications:Checkbox("Hide in Battlegrounds", Get("presenceSuppressInBattleground"),
    Set("presenceSuppressInBattleground"), "No zone, subzone or scenario banners inside a battleground.")

---------------------------------------------------------------------------
-- Typography
---------------------------------------------------------------------------
AddPreview(typography)

local OUTLINES = {
    { label = "None", value = "" },
    { label = "Outline", value = "OUTLINE" },
    { label = "Thick Outline", value = "THICKOUTLINE" },
}

typography:Header("Fonts")
typography:Dropdown("Main Title Font", addon.GetFontOptions, Get("presenceTitleFontPath"),
    Set("presenceTitleFontPath"), "Font of the main title (the large first line).")
typography:Dropdown("Subtitle Font", addon.GetFontOptions, Get("presenceSubtitleFontPath"),
    Set("presenceSubtitleFontPath"), "Font of the subtitle (the line under the divider).")
typography:Dropdown("Discovery Font", addon.GetFontOptions, Get("presenceDiscoveryFontPath"),
    Set("presenceDiscoveryFontPath"), "Font of the \"Discovered\" line.")
typography:Dropdown("Main Title Outline", OUTLINES, Get("presenceTitleFontOutline"),
    Set("presenceTitleFontOutline"), "Outline around the main title's letters.")
typography:Dropdown("Subtitle Outline", OUTLINES, Get("presenceSubtitleFontOutline"),
    Set("presenceSubtitleFontOutline"), "Outline around the subtitle's letters.")
typography:Dropdown("Discovery Outline", OUTLINES, Get("presenceDiscoveryFontOutline"),
    Set("presenceDiscoveryFontOutline"), "Outline around the \"Discovered\" line's letters.")

local SIZES = {
    { "Large", "Large", "zone entry, quest and world quest complete, scenario complete, achievement earned, boss emote "
        .. "and level up" },
    { "Medium", "Medium", "subzone change, quest and world quest accepted, scenario start and progress, and rare "
        .. "defeated" },
    { "Small", "Small", "quest progress and achievement progress" },
}
for _, size in ipairs(SIZES) do
    local name, key, types = size[1], size[2], size[3]
    typography:Header(name .. " Notifications")
    typography:Slider("Main Title Size", 12, 72, 1, Get("presencePrimary" .. key .. "Sz"),
        Set("presencePrimary" .. key .. "Sz"), nil, "Font size of the main title on " .. types .. " banners.")
    typography:Slider("Subtitle Size", 12, 40, 1, Get("presenceSecondary" .. key .. "Sz"),
        Set("presenceSecondary" .. key .. "Sz"), nil, "Font size of the subtitle on " .. types .. " banners.")
    typography:Slider("Main Title Spacing", 0, 60, 1, Get("presenceTitleGap" .. key), Set("presenceTitleGap" .. key),
        Pixels, "Space between the main title and the divider line on " .. types .. " banners.")
end

typography:Header("Discovery Line")
typography:Slider("Discovery Size", 12, 40, 1, Get("presenceDiscoverySize"), Set("presenceDiscoverySize"), nil,
    "Font size of the \"Discovered\" line under the zone name.")

typography:Header("Colors")
local TitleByType = Get("presenceTitleColorByType")
typography:Checkbox("Color Main Titles by Type", TitleByType, Set("presenceTitleColorByType"),
    "Main titles take the color of the banner's type: gold for campaign quests, purple for world quests, green for "
    .. "completed quests, bronze for achievements and so on.\n\nOff, every main title uses Main Title Color. Boss "
    .. "emotes and Zone Type Colors keep their own colors.")
typography:ColorSwatch("Main Title Color", GetColor("presenceTitleColor"), SetColor("presenceTitleColor"),
    "Color of every main title, and its divider line.",
    { indent = true, enabled = function() return not TitleByType() end })
local SubtitleByType = Get("presenceSubtitleColorByType")
typography:Checkbox("Color Subtitles by Type", SubtitleByType, Set("presenceSubtitleColorByType"),
    "Subtitles take the color of the banner's type: gold for zone banners, light gray for the rest.\n\nOff, every "
    .. "subtitle uses Subtitle Color.")
typography:ColorSwatch("Subtitle Color", GetColor("presenceSubtitleColor"), SetColor("presenceSubtitleColor"),
    "Color of every subtitle.", { indent = true, enabled = function() return not SubtitleByType() end })
typography:ColorSwatch("Boss Emote Color", GetColor("presenceBossEmoteColor"), SetColor("presenceBossEmoteColor"),
    "Color of the boss's name on boss emote banners.")
typography:ColorSwatch("Discovery Line Color", GetColor("presenceDiscoveryColor"), SetColor("presenceDiscoveryColor"),
    "Color of the \"Discovered\" line.")

typography:Header("Zone Type Colors")
local ZoneTypeOn = Get("presenceZoneTypeColoring")
typography:Checkbox("Color by Zone Type", ZoneTypeOn, Set("presenceZoneTypeColoring"),
    "Zone and subzone names take the color of the zone's PvP type: friendly, hostile, contested or sanctuary.")
for _, zoneType in ipairs({ "Friendly", "Hostile", "Contested", "Sanctuary" }) do
    local key = "presenceZoneColor" .. zoneType
    typography:ColorSwatch(zoneType .. " Zone Color", GetColor(key), SetColor(key),
        "Color of " .. zoneType:lower() .. " zone names.", { indent = true, enabled = ZoneTypeOn })
end

local TYPOGRAPHY_KEYS = {
    "presenceTitleFontPath", "presenceSubtitleFontPath", "presenceDiscoveryFontPath",
    "presenceTitleFontOutline", "presenceSubtitleFontOutline", "presenceDiscoveryFontOutline",
    "presencePrimaryLargeSz", "presenceSecondaryLargeSz", "presenceTitleGapLarge",
    "presencePrimaryMediumSz", "presenceSecondaryMediumSz", "presenceTitleGapMedium",
    "presencePrimarySmallSz", "presenceSecondarySmallSz", "presenceTitleGapSmall",
    "presenceDiscoverySize", "presenceTitleColorByType", "presenceTitleColor", "presenceSubtitleColorByType",
    "presenceSubtitleColor", "presenceBossEmoteColor", "presenceDiscoveryColor", "presenceZoneTypeColoring",
    "presenceZoneColorFriendly", "presenceZoneColorHostile", "presenceZoneColorContested", "presenceZoneColorSanctuary",
}
typography:Spacer(20)
typography:Button("Reset Typography", function()
    for _, key in ipairs(TYPOGRAPHY_KEYS) do ToastBannersDB[key] = nil end
    addon.ApplySettings()
end, "Sets the fonts, sizes, spacing and colors on this tab back to their defaults.")

Kit.Register(page)

addon.RefreshOptions = function() page:Refresh() end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_TOASTBANNERS1 = "/toastbanners"
SlashCmdList["TOASTBANNERS"] = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "demo" then
        -- every banner, one after another
        for i, entry in ipairs(PREVIEW_TYPES) do
            C_Timer.After((i - 1) * 3, function() addon.Presence.PreviewToast(entry[1]) end)
        end
    elseif cmd == "debug" then
        addon.Presence.DumpDebug()
    else
        Kit.Open(page)
    end
end
