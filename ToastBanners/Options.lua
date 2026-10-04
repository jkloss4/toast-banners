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
local general, notifications, typography, colors = unpack(page:Tabs({ "General", "Notifications", "Typography", "Colors" }))

---------------------------------------------------------------------------
-- Preview: plays the real banner on screen
---------------------------------------------------------------------------
local PREVIEW_TYPES = {
    { "ZONE_CHANGE", "Zone Entry" },
    { "SUBZONE_CHANGE", "Subzone Change" },
    { "QUEST_ACCEPT", "Quest Accepted" },
    { "WORLD_QUEST_ACCEPT", "World Quest Accepted" },
    { "QUEST_UPDATE", "Quest Progress" },
    { "QUEST_COMPLETE", "Quest Complete" },
    { "WORLD_QUEST", "World Quest Complete" },
    { "SCENARIO_START", "Scenario Start" },
    { "SCENARIO_UPDATE", "Scenario Progress" },
    { "SCENARIO_COMPLETE", "Scenario Complete" },
    { "ACHIEVEMENT", "Achievement Earned" },
    { "ACHIEVEMENT_PROGRESS", "Achievement Progress" },
    { "BOSS_EMOTE", "Boss Emote" },
    { "LEVEL_UP", "Level Up" },
    { "RARE_DEFEATED", "Rare Defeated" },
}
-- The size each type is shown at: chosen on the Notifications tab, or the type's own
local function GetSize(typeName)
    local saved = GetDB("presenceSize_" .. typeName)
    if saved == "large" or saved == "medium" or saved == "small" then return saved end
    return addon.Presence.GetDefaultSize(typeName)
end

local function SizeName(size)
    return size:sub(1, 1):upper() .. size:sub(2)
end

-- built when the menu opens, so each tooltip names the type's current size
local function PreviewOptions()
    local options = {}
    for _, entry in ipairs(PREVIEW_TYPES) do
        options[#options + 1] = { label = entry[2], value = entry[1],
            tooltip = SizeName(GetSize(entry[1])) .. " notification." }
    end
    return options
end

local function AddPreview(list)
    list:Header("Preview")
    list:Dropdown("Banner", PreviewOptions,
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

-- Each type's row has its banner size beside it (Large, Medium or Small, set up on the Typography tab)
local SIZE_OPTIONS = {
    { label = "Large", value = "large", tooltip = "Fonts and spacing from Typography > Large Notifications." },
    { label = "Medium", value = "medium", tooltip = "Fonts and spacing from Typography > Medium Notifications." },
    { label = "Small", value = "small", tooltip = "Fonts and spacing from Typography > Small Notifications." },
}

local function TypeRow(label, typeName, get, set, tooltip, opts)
    opts = opts or {}
    local defaultSize = addon.Presence.GetDefaultSize(typeName)
    opts.dropdownTooltip = "Size of " .. label:lower() .. " banners. Default: " .. SizeName(defaultSize) .. "."
    return notifications:CheckboxDropdown(label, get, set, SIZE_OPTIONS,
        function() return GetSize(typeName) end,
        function(value) SetDB("presenceSize_" .. typeName, value ~= defaultSize and value or nil) end,
        tooltip, opts)
end

notifications:Header("Zones")
TypeRow("Zone Entry", "ZONE_CHANGE", Get("presenceZoneChange"), Set("presenceZoneChange"),
    "When you enter a new zone." .. OFF_NOTE)
notifications:Checkbox("Zone Name Only", Get("presenceZoneEntryNameOnly"), Set("presenceZoneEntryNameOnly"),
    "Zone entry banners show only the zone's name, without the subzone you arrive in under it.",
    { indent = true, enabled = Get("presenceZoneChange") })
local SubzoneOn = GetWithFallback("presenceSubzoneChange", "presenceZoneChange")
TypeRow("Subzone Changes", "SUBZONE_CHANGE", SubzoneOn, Set("presenceSubzoneChange"),
    "When you move to another area within the same zone." .. OFF_NOTE)
notifications:Checkbox("Subzone Only", Get("presenceHideZoneForSubzone"), Set("presenceHideZoneForSubzone"),
    "Subzone banners show only the subzone's name, without the zone's name under it. The zone's name still "
    .. "shows when you enter a new zone.", { indent = true, enabled = SubzoneOn })

notifications:Header("Quests")
TypeRow("Quest Accepted", "QUEST_ACCEPT", GetWithFallback("presenceQuestAccept", "presenceQuestEvents"),
    Set("presenceQuestAccept"), "When you accept a quest.")
TypeRow("World Quest Accepted", "WORLD_QUEST_ACCEPT", GetWithFallback("presenceWorldQuestAccept", "presenceQuestEvents"),
    Set("presenceWorldQuestAccept"), "When you accept a world quest.")
local QuestProgressOn = GetWithFallback("presenceQuestUpdate", "presenceQuestEvents")
TypeRow("Quest Progress", "QUEST_UPDATE", QuestProgressOn, Set("presenceQuestUpdate"),
    "When a quest objective updates (e.g. 7/10 Boar Pelts).")
notifications:Checkbox("Objective Only", Get("presenceHideQuestUpdateTitle"), Set("presenceHideQuestUpdateTitle"),
    "Quest and scenario progress banners show only the objective, without the \"Quest Update\" title.",
    { indent = true, enabled = QuestProgressOn })
TypeRow("Quest Complete", "QUEST_COMPLETE", GetWithFallback("presenceQuestComplete", "presenceQuestEvents"),
    Set("presenceQuestComplete"), "When you complete a quest.")
TypeRow("World Quest Complete", "WORLD_QUEST", GetWithFallback("presenceWorldQuest", "presenceQuestEvents"),
    Set("presenceWorldQuest"), "When you complete a world quest." .. OFF_NOTE)

notifications:Header("Scenarios")
TypeRow("Scenario Start", "SCENARIO_START", GetWithFallback("presenceScenarioStart", "showScenarioEvents"),
    Set("presenceScenarioStart"), "When you enter a scenario" .. (addon.HAS_DELVES and " or Delve." or "."))
TypeRow("Scenario Progress", "SCENARIO_UPDATE", GetWithFallback("presenceScenarioUpdate", "showScenarioEvents"),
    Set("presenceScenarioUpdate"), "When a scenario objective updates.")
TypeRow("Scenario Complete", "SCENARIO_COMPLETE", GetWithFallback("presenceScenarioComplete", "showScenarioEvents"),
    Set("presenceScenarioComplete"), "When you complete a scenario" .. (addon.HAS_DELVES and " or Delve." or "."))

notifications:Header("Other")
TypeRow("Achievements", "ACHIEVEMENT", Get("presenceAchievement"), Set("presenceAchievement"),
    "When you earn an achievement." .. OFF_NOTE)
TypeRow("Achievement Progress", "ACHIEVEMENT_PROGRESS", Get("presenceAchievementProgress"), Set("presenceAchievementProgress"),
    "When an achievement's criteria update: always for tracked achievements, and for others when the game says "
    .. "which achievement it is." .. OFF_NOTE)
TypeRow("Boss Emotes", "BOSS_EMOTE", Get("presenceBossEmote"), Set("presenceBossEmote"),
    "Raid and dungeon boss emotes." .. OFF_NOTE)
TypeRow("Level Up", "LEVEL_UP", Get("presenceLevelUp"), Set("presenceLevelUp"),
    "When you gain a level." .. OFF_NOTE)
TypeRow("Rare Defeated", "RARE_DEFEATED", Get("presenceRareDefeated"), Set("presenceRareDefeated"),
    "When a rare creature nearby is defeated.")

notifications:Header("Instances")
notifications:Checkbox("Hide in Dungeons", Get("presenceSuppressInDungeon"), Set("presenceSuppressInDungeon"),
    "No zone, subzone or scenario banners inside a dungeon.")
if addon.HAS_DELVES then
    notifications:Checkbox("Hide Delve Progress", Get("presenceSuppressInDelve"), Set("presenceSuppressInDelve"),
        "No objective progress banners inside a Delve. Entering and completing it still show.")
end
if addon.HAS_MYTHIC_PLUS then
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

-- Which banners use each size is chosen on the Notifications tab
local SIZE_NOTE = "\n\nEach notification type's size is set beside it on the Notifications tab."
for _, key in ipairs({ "Large", "Medium", "Small" }) do
    local types = key:lower()
    typography:Header(key .. " Notifications")
    typography:Slider("Main Title Size", 12, 72, 1, Get("presencePrimary" .. key .. "Sz"),
        Set("presencePrimary" .. key .. "Sz"), nil, "Font size of the main title on " .. types .. " banners." .. SIZE_NOTE)
    typography:Slider("Subtitle Size", 12, 40, 1, Get("presenceSecondary" .. key .. "Sz"),
        Set("presenceSecondary" .. key .. "Sz"), nil, "Font size of the subtitle on " .. types .. " banners." .. SIZE_NOTE)
    typography:Slider("Main Title Spacing", 0, 60, 1, Get("presenceTitleGap" .. key), Set("presenceTitleGap" .. key),
        Pixels, "Space between the main title and the divider line on " .. types .. " banners." .. SIZE_NOTE)
end

typography:Header("Discovery Line")
typography:Slider("Discovery Size", 12, 40, 1, Get("presenceDiscoverySize"), Set("presenceDiscoverySize"), nil,
    "Font size of the \"Discovered\" line under the zone name.")

local TYPOGRAPHY_KEYS = {
    "presenceTitleFontPath", "presenceSubtitleFontPath", "presenceDiscoveryFontPath",
    "presenceTitleFontOutline", "presenceSubtitleFontOutline", "presenceDiscoveryFontOutline",
    "presencePrimaryLargeSz", "presenceSecondaryLargeSz", "presenceTitleGapLarge",
    "presencePrimaryMediumSz", "presenceSecondaryMediumSz", "presenceTitleGapMedium",
    "presencePrimarySmallSz", "presenceSecondarySmallSz", "presenceTitleGapSmall",
    "presenceDiscoverySize",
}
typography:Spacer(20)
typography:Button("Reset Typography", function()
    for _, key in ipairs(TYPOGRAPHY_KEYS) do ToastBannersDB[key] = nil end
    addon.ApplySettings()
end, "Sets the fonts, sizes and spacing on this tab back to their defaults.")

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------
AddPreview(colors)

colors:Header("All Notifications")
local TitleByType = Get("presenceTitleColorByType")
colors:Checkbox("Color Main Titles by Type", TitleByType, Set("presenceTitleColorByType"),
    "Main titles take the color of the banner's type: gold for campaign quests, purple for world quests, green for "
    .. "completed quests, bronze for achievements and so on.\n\nOff, every main title uses Main Title Color. Boss "
    .. "emotes and Zone Type Colors keep their own colors.")
colors:ColorSwatch("Main Title Color", GetColor("presenceTitleColor"), SetColor("presenceTitleColor"),
    "Color of every main title.", { indent = true, enabled = function() return not TitleByType() end })
local DividerMatches = Get("presenceDividerMatchesTitle")
colors:Checkbox("Divider Lines Match Main Title", DividerMatches, Set("presenceDividerMatchesTitle"),
    "The divider line under the main title takes the main title's color.\n\nOff, every divider line uses Divider "
    .. "Line Color.")
colors:ColorSwatch("Divider Line Color", GetColor("presenceDividerColor"), SetColor("presenceDividerColor"),
    "Color of every divider line.", { indent = true, enabled = function() return not DividerMatches() end })
local SubtitleByType = Get("presenceSubtitleColorByType")
colors:Checkbox("Color Subtitles by Type", SubtitleByType, Set("presenceSubtitleColorByType"),
    "Subtitles take the color of the banner's type: gold for zone banners, light gray for the rest.\n\nOff, every "
    .. "subtitle uses Subtitle Color.")
colors:ColorSwatch("Subtitle Color", GetColor("presenceSubtitleColor"), SetColor("presenceSubtitleColor"),
    "Color of every subtitle.", { indent = true, enabled = function() return not SubtitleByType() end })
colors:ColorSwatch("Discovery Line Color", GetColor("presenceDiscoveryColor"), SetColor("presenceDiscoveryColor"),
    "Color of the \"Discovered\" line under the zone name.")

colors:Header("Zone Type Colors")
local ZoneTypeOn = Get("presenceZoneTypeColoring")
colors:Checkbox("Color by Zone Type", ZoneTypeOn, Set("presenceZoneTypeColoring"),
    "Zone and subzone names take the color of the zone's PvP type: friendly, hostile, contested or sanctuary.")
for _, zoneType in ipairs({ "Friendly", "Hostile", "Contested", "Sanctuary" }) do
    local key = "presenceZoneColor" .. zoneType
    colors:ColorSwatch(zoneType .. " Zone Color", GetColor(key), SetColor(key),
        "Color of " .. zoneType:lower() .. " zone names.", { indent = true, enabled = ZoneTypeOn })
end

-- Each type's own main title, divider line and subtitle colors, which win over everything above
colors:Header("Notification Types")
local TYPE_PARTS = {
    { "title", "Main Title", "the main title" },
    { "line", "Divider Line", "the divider line" },
    { "sub", "Subtitle", "the subtitle" },
}

-- The color a part has before it's customized: the type's own color (the divider line follows the main title)
local function TypeDefaultColor(typeName, part)
    local title, sub = addon.Presence.GetTypeDefaultColors(typeName)
    return part == "sub" and sub or title
end

for _, entry in ipairs(PREVIEW_TYPES) do
    local typeName, typeLabel = entry[1], entry[2]
    colors:Expandable(typeLabel, { key = "colors" .. typeName, expanded = false })
    for _, part in ipairs(TYPE_PARTS) do
        local partKey, partLabel, partText = part[1], part[2], part[3]
        local onKey = "presenceTypeColorOn_" .. typeName .. "_" .. partKey
        local colorKey = "presenceTypeColor_" .. typeName .. "_" .. partKey
        local function GetPartColor()
            local c = GetDB(colorKey)
            if type(c) == "table" and type(c[1]) == "number" then return c[1], c[2], c[3] end
            return unpack(TypeDefaultColor(typeName, partKey))
        end
        colors:CheckboxColorSwatch(partLabel, Get(onKey), function(value)
            -- turning it on starts from the color the swatch shows
            if value and type(GetDB(colorKey)) ~= "table" then
                ToastBannersDB[colorKey] = { GetPartColor() }
            end
            SetDB(onKey, value)
        end, GetPartColor, function(r, g, b) SetDB(colorKey, { r, g, b }) end,
            "Use your own color for " .. partText .. " of " .. typeLabel:lower() .. " banners, in place of the "
            .. "colors set above.", { indent = true })
    end
end
colors:EndExpandable()

local COLOR_KEYS = {
    "presenceTitleColorByType", "presenceTitleColor", "presenceDividerMatchesTitle", "presenceDividerColor",
    "presenceSubtitleColorByType", "presenceSubtitleColor", "presenceBossEmoteColor", "presenceDiscoveryColor",
    "presenceZoneTypeColoring", "presenceZoneColorFriendly", "presenceZoneColorHostile", "presenceZoneColorContested",
    "presenceZoneColorSanctuary",
}
colors:Spacer(20)
colors:Button("Reset Colors", function()
    for _, key in ipairs(COLOR_KEYS) do ToastBannersDB[key] = nil end
    for key in pairs(ToastBannersDB) do
        if key:find("^presenceTypeColor") then ToastBannersDB[key] = nil end
    end
    addon.ApplySettings()
end, "Sets every color on this tab back to its default.")

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
