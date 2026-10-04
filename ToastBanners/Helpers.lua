-- Toast Banners - Helpers
-- Instance, delve, quest category and rare helpers the banners use, copied from Horizon Suite (Utilities.lua and
-- the Focus module's FocusCategories.lua and FocusDungeons.lua) so the addon runs on its own.

local _, addon = ...
local L = addon.L

-- ============================================================================
-- INSTANCE & DELVE HELPERS
-- ============================================================================

-- True when the player is in any party dungeon (Normal, Heroic, Mythic, or Mythic+). Guarded.
function addon.IsInPartyDungeon()
    local ok, _, instanceType = pcall(GetInstanceInfo)
    return ok and instanceType == "party"
end

-- True when the player is in an active Delve (guarded API). Clients without Delves (WoW: Forever) answer true from
-- C_PartyInfo.IsDelveInProgress inside ordinary dungeons, so a client with no Delves UI can never be in one.
function addon.IsDelveActive()
    if not C_DelvesUI then return false end
    if C_PartyInfo and C_PartyInfo.IsDelveInProgress then
        local ok, v = pcall(C_PartyInfo.IsDelveInProgress)
        -- Truthiness, not ==: a secret return would throw on comparison.
        if ok and v then return true end
    end
    return false
end

local TIER_MIN, TIER_MAX = 1, 12
local WIDGET_TYPE_SCENARIO_HEADER_DELVES = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.ScenarioHeaderDelves) or 29

-- Current Delve tier (1-12) or nil if unknown/not in delve. Guarded API.
function addon.GetActiveDelveTier()
    if not addon.IsDelveActive() then return nil end

    if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID and C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo then
        local setID
        if C_Scenario and C_Scenario.GetStepInfo then
            local sOk, t = pcall(function() return { C_Scenario.GetStepInfo() } end)
            if sOk and t and type(t) == "table" and #t >= 12 then
                local ws = t[12]
                if type(ws) == "number" and ws ~= 0 then setID = ws end
            end
        end
        if not setID and C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
            local oOk, objSet = pcall(C_UIWidgetManager.GetObjectiveTrackerWidgetSetID)
            if oOk and objSet and type(objSet) == "number" then setID = objSet end
        end
        if setID then
            local wOk, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
            if wOk and widgets and type(widgets) == "table" then
                for _, wInfo in pairs(widgets) do
                    local widgetID = (wInfo and type(wInfo) == "table" and type(wInfo.widgetID) == "number") and wInfo.widgetID
                        or (type(wInfo) == "number" and wInfo > 0) and wInfo
                    local wType = (wInfo and type(wInfo) == "table") and wInfo.widgetType
                    if widgetID and (not wType or wType == WIDGET_TYPE_SCENARIO_HEADER_DELVES) then
                        local dOk, widgetInfo = pcall(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo, widgetID)
                        if dOk and widgetInfo and type(widgetInfo) == "table" then
                            local tierText = widgetInfo.tierText
                            if tierText and type(tierText) == "string" and tierText ~= "" then
                                local tier = tonumber(tierText:match("%d+"))
                                if tier and tier >= TIER_MIN and tier <= TIER_MAX then
                                    return tier
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- Vista-style last-known-good delve name. Updated whenever a valid name is found;
-- never cleared on IsDelveActive() false because the reward stage may return false
-- while the player is still physically inside the delve instance.
local cachedDelveName = nil

-- Returns the name of the current Delve. Uses C_Map.GetMapInfo first, then zone/subzone, C_Scenario.GetInfo, GetInstanceInfo.
-- Returns the last cached valid name when all APIs return "Delves" or empty (e.g. on the reward stage).
function addon.GetDelveNameFromAPIs()
    -- Try all sources without the IsDelveActive() guard so the reward stage still resolves.
    -- Primary: map API
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local ok, info = pcall(C_Map.GetMapInfo, mapID)
            if ok and info and info.name and info.name ~= "" and info.name ~= "Delves" then
                cachedDelveName = info.name
                return info.name
            end
        end
    end
    -- Fallbacks: zone, subzone, C_Scenario.GetInfo, GetInstanceInfo
    local zone = (GetZoneText and GetZoneText()) or ""
    local sub = (GetSubZoneText and GetSubZoneText()) or ""
    if zone ~= "" and zone ~= "Delves" then cachedDelveName = zone; return zone end
    if sub  ~= "" and sub  ~= "Delves" then cachedDelveName = sub;  return sub  end
    local ok, name = pcall(C_Scenario.GetInfo)
    if ok and name and name ~= "" and name ~= "Delves" then cachedDelveName = name; return name end
    local instOk, instanceName = pcall(GetInstanceInfo)
    if instOk and instanceName and instanceName ~= "" and instanceName ~= "Delves" then
        cachedDelveName = instanceName; return instanceName
    end
    -- All APIs returned "Delves" or empty (completion stage) — return last known good name.
    return cachedDelveName
end


-- ============================================================================
-- QUEST CATEGORY HELPERS
-- ============================================================================

-- Single source of truth: QuestUtils_IsQuestWorldQuest (Blizzard) or C_QuestLog.IsWorldQuest.
function addon.IsQuestWorldQuest(questID)
    if not questID or questID <= 0 then return false end
    if _G.QuestUtils_IsQuestWorldQuest and _G.QuestUtils_IsQuestWorldQuest(questID) then return true end
    if C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then return true end
    return false
end

local function IsPreyQuest(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetTitleForQuestID then return false end
    local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
    if not ok or not title then return false end
    local preyLabel = L["UI_PREY"]
    return title:find(preyLabel, 1, true) ~= nil
end

function addon.GetQuestFrequency(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetLogIndexForQuestID then return nil end
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then return nil end
    if C_QuestLog.GetInfo then
        local ok, info = pcall(C_QuestLog.GetInfo, logIndex)
        if ok and info and info.frequency ~= nil then return info.frequency end
    end
    return nil
end

-- Single source of truth: C_QuestInfoSystem.GetQuestClassification + frequency + IsQuestWorldQuest.
function addon.GetQuestBaseCategory(questID)
    if not questID or questID <= 0 then return "DEFAULT" end
    if addon.IsQuestWorldQuest(questID) then
        if IsPreyQuest(questID) then return "PREY" end
        return "WORLD"
    end
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local ok, tagInfo = pcall(C_QuestLog.GetQuestTagInfo, questID)
        if ok and tagInfo then
            if tagInfo.tagID == 62 then return "RAID" end
            if tagInfo.tagID == 81 then return "DUNGEON" end
        end
    end
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        local qc = C_QuestInfoSystem.GetQuestClassification(questID)
        if qc == Enum.QuestClassification.Calling then return "CALLING" end
        if qc == Enum.QuestClassification.Campaign then return "CAMPAIGN" end
        if qc == Enum.QuestClassification.Recurring then
            if IsPreyQuest(questID) then return "PREY" end
            -- Recurring covers both daily and weekly quests; disambiguate via frequency.
            local freq = addon.GetQuestFrequency(questID)
            if freq == (Enum.QuestFrequency and Enum.QuestFrequency.Daily)
                or freq == 1
                or (LE_QUEST_FREQUENCY_DAILY and freq == LE_QUEST_FREQUENCY_DAILY) then
                return "DAILY"
            end
            return "WEEKLY"
        end
        if qc == Enum.QuestClassification.Meta then
            if IsPreyQuest(questID) then return "PREY" end
            return "WEEKLY"
        end
        if qc == Enum.QuestClassification.Important then return "IMPORTANT" end
        if qc == Enum.QuestClassification.Legendary then return "LEGENDARY" end
    end
    local freq = addon.GetQuestFrequency(questID)
    if freq ~= nil then
        if Enum.QuestFrequency and Enum.QuestFrequency.Weekly and freq == Enum.QuestFrequency.Weekly then
            if IsPreyQuest(questID) then return "PREY" end
            return "WEEKLY"
        end
        if freq == 2 or (LE_QUEST_FREQUENCY_WEEKLY and freq == LE_QUEST_FREQUENCY_WEEKLY) then
            if IsPreyQuest(questID) then return "PREY" end
            return "WEEKLY"
        end
        if Enum.QuestFrequency and Enum.QuestFrequency.Daily and freq == Enum.QuestFrequency.Daily then
            return "DAILY"
        end
        if freq == 1 or (LE_QUEST_FREQUENCY_DAILY and freq == LE_QUEST_FREQUENCY_DAILY) then
            return "DAILY"
        end
    end
    return "DEFAULT"
end

function addon.GetQuestCategory(questID)
    if not questID or questID <= 0 then return "DEFAULT" end
    if C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then
        local base = addon.GetQuestBaseCategory(questID)
        if base == "CAMPAIGN" and addon.GetDB and addon.GetDB("keepCampaignInCategory", false) then
            return "CAMPAIGN"
        end
        if base == "IMPORTANT" and addon.GetDB and addon.GetDB("keepImportantInCategory", false) then
            return "IMPORTANT"
        end
        return "COMPLETE"
    end
    return addon.GetQuestBaseCategory(questID)
end

-- ============================================================================
-- RARE NAMES FOR PRESENCE
-- ============================================================================

local function IsNpcVignetteAtlas(atlasName)
    if not atlasName or atlasName == "" then return false end
    local lower = atlasName:lower()
    if lower:find("loot") or lower:find("treasure") or lower:find("container") or lower:find("chest") or lower:find("object") then
        return false
    end
    if lower:find("rare") or lower:find("elite") or lower:find("npc") or lower:find("vignettekill") then
        return true
    end
    return false
end

-- Returns { entryKey -> title } for rares on the current map (vignette-based rares), for the Rare Defeated banner.
function addon.GetRareNamesOnMap()
    local out = {}
    if not C_VignetteInfo or not C_VignetteInfo.GetVignettes or not C_VignetteInfo.GetVignetteInfo then return out end
    local vignettes = C_VignetteInfo.GetVignettes()
    if not vignettes then return out end
    local seen = {}
    for _, vignetteGUID in ipairs(vignettes) do
        local vi = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
        if vi and (vi.name and vi.name ~= "") and IsNpcVignetteAtlas(vi.atlasName) then
            local creatureID = vi.npcID or vi.creatureID
            if not creatureID and vi.objectGUID then
                local _, _, _, _, _, id, _ = strsplit("-", vi.objectGUID)
                creatureID = tonumber(id)
            end
            if creatureID then
                local dedupeKey = ("c:" .. tostring(creatureID)) or ("n:" .. (vi.name or ""))
                if not seen[dedupeKey] then
                    seen[dedupeKey] = true
                    local entryKey = "vignette:" .. tostring(vignetteGUID)
                    out[entryKey] = vi.name or "Unknown"
                end
            end
        end
    end
    return out
end

-- Quest type icon atlas (Focus module)
local function GetQuestTypeAtlas(questID, category)
    if not questID or questID <= 0 then return nil end
    if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID) then
        return "QuestTurnin"
    end
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        local qc = C_QuestInfoSystem.GetQuestClassification(questID)
        if qc then
            local atlas = (qc == Enum.QuestClassification.Important and "importantavailablequesticon")
                or (qc == Enum.QuestClassification.Campaign and "Quest-Campaign-Available")
                or (qc == Enum.QuestClassification.Legendary and "UI-QuestPoiLegendary-QuestBang")
                or (qc == Enum.QuestClassification.Calling and "Quest-DailyCampaign-Available")
                or (qc == Enum.QuestClassification.Recurring and "quest-recurring-available")
                or (qc == Enum.QuestClassification.Meta and "quest-wrapper-available")
            if atlas then return atlas end
        end
    end
    if category == "COMPLETE" then return "QuestTurnin" end
    if category == "IMPORTANT" then return "importantavailablequesticon" end
    if category == "CAMPAIGN" then return "Quest-Campaign-Available" end
    if category == "LEGENDARY" then return "UI-QuestPoiLegendary-QuestBang" end
    if category == "CALLING" then return "Quest-DailyCampaign-Available" end
    if category == "WORLD" then return "quest-recurring-available" end
    if category == "WEEKLY" then return "quest-recurring-available" end
    if category == "PREY" then return "quest-recurring-available" end
    if category == "DAILY" then return "quest-recurring-available" end
    if category == "DUNGEON" then return "questlog-questtypeicon-dungeon" end
    if category == "RAID" then return "questlog-questtypeicon-raid" end
    if C_QuestLog.GetQuestTagInfo then
        local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
        if tagInfo and tagInfo.tagID then
            local tagAtlas = (tagInfo.tagID == 41 and "questlog-questtypeicon-pvp")
                or (tagInfo.tagID == 81 and "questlog-questtypeicon-dungeon")
                or (tagInfo.tagID == 62 and "questlog-questtypeicon-raid")
                or (tagInfo.tagID == 1 and "questlog-questtypeicon-group")
            if tagAtlas then return tagAtlas end
        end
    end
    return "QuestNormal"
end

addon.GetQuestTypeAtlas = GetQuestTypeAtlas

-- True in a Mythic or Mythic+ dungeon
function addon.IsInMythicDungeon()
    local ok, _, instanceType, difficultyID = pcall(GetInstanceInfo)
    return ok and instanceType == "party" and (difficultyID == 8 or difficultyID == 23)
end
