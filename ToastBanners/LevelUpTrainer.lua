--[[
    Toast Banners - Trainer spells for the level up banner (WoW: Forever)
    Forever's spells are learned from class trainers, and the game has no list of what a level unlocks
    (C_SpellBook.GetCurrentLevelSpells is empty there). So each time you open a class trainer, what it teaches and the
    level each needs are saved, per class; at a level up the spells that just became available are listed.
    Saved in ToastBannersDB.trainerSpells[class]["name|rank"] = { name, rank, level, reqs }.
]]

local _, addon = ...
if not addon or not addon.Presence then return end

-- What the trainer list includes is set by its filters: all are shown while it's read, then put back
local FILTERS = { "available", "unavailable", "used" }

local function IsClassTrainer()
    if IsTradeskillTrainer and IsTradeskillTrainer() then return false end
    if C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType then
        return C_Trainer.GetTrainerType() == Enum.TrainerType.General
    end
    return true
end

local function ReadTrainer()
    local _, class = UnitClass("player")
    if not class then return end

    ToastBannersDB.trainerSpells = ToastBannersDB.trainerSpells or {}
    local spells = ToastBannersDB.trainerSpells[class] or {}
    ToastBannersDB.trainerSpells[class] = spells
    local count = 0
    for index = 1, GetNumTrainerServices() do
        local name, serviceType, _, reqLevel, rank = GetTrainerServiceInfo(index)
        if name and name ~= "" and serviceType ~= "header" and type(reqLevel) == "number" then
            local reqs
            for req = 1, (GetTrainerServiceNumAbilityReq and GetTrainerServiceNumAbilityReq(index) or 0) do
                local ability = GetTrainerServiceAbilityReq(index, req)
                if ability and ability ~= "" then
                    reqs = reqs or {}
                    reqs[#reqs + 1] = ability
                end
            end
            -- added to what earlier trainers taught (a weapon master or riding trainer doesn't replace them)
            spells[name .. "|" .. (rank or "")] = { name = name, rank = rank, level = reqLevel, reqs = reqs }
            count = count + 1
        end
    end
    if addon.Log.isEnabled() then
        local kinds = {}
        for index = 1, GetNumTrainerServices() do
            local _, serviceType = GetTrainerServiceInfo(index)
            kinds[tostring(serviceType)] = (kinds[tostring(serviceType)] or 0) + 1
        end
        local list = {}
        for kind, n in pairs(kinds) do list[#list + 1] = kind .. "=" .. n end
        addon.Trace("trainer read: %d spells for %s (list has %d: %s)", count, class, GetNumTrainerServices(),
            table.concat(list, ", "))
    end
end

local function StartRead()
    if addon.IS_RETAIL or not (GetNumTrainerServices and GetTrainerServiceInfo and IsClassTrainer()) then return end
    local filters = {}
    for _, filter in ipairs(FILTERS) do filters[#filters + 1] = filter .. "=" .. tostring(GetTrainerServiceTypeFilter(filter)) end
    addon.Trace("trainer opened: %d in the list, filters %s", GetNumTrainerServices(), table.concat(filters, " "))
    -- the list changes as soon as a filter does: every filter on, read, then the filters you had put back
    local turnedOn = {}
    for _, filter in ipairs(FILTERS) do
        if not GetTrainerServiceTypeFilter(filter) then
            turnedOn[#turnedOn + 1] = filter
            SetTrainerServiceTypeFilter(filter, true)
        end
    end
    ReadTrainer()
    for _, filter in ipairs(turnedOn) do SetTrainerServiceTypeFilter(filter, false) end
end

-- A spell a trainer lists needs these first; a talent or earlier rank you don't have keeps it off the banner
local function Known(ability)
    local name = ability:gsub("%s*%(.-%)%s*$", "")
    if C_Spell and C_Spell.GetSpellInfo then
        return C_Spell.GetSpellInfo(name) ~= nil
    end
    return GetSpellInfo and GetSpellInfo(name) ~= nil
end

-- The saved trainer spells that become available at this level, as shown on the banner ("Arcane Shot (Rank 2)")
function addon.Presence.TrainerSpellsAt(level)
    local _, class = UnitClass("player")
    local spells = ToastBannersDB and ToastBannersDB.trainerSpells and ToastBannersDB.trainerSpells[class]
    local names = {}
    for _, spell in pairs(spells or {}) do
        local ready = spell.level == level
        for _, ability in ipairs(ready and spell.reqs or {}) do
            if not Known(ability) then ready = false end
        end
        if ready then
            names[#names + 1] = (spell.rank and spell.rank ~= "") and (spell.name .. " (" .. spell.rank .. ")")
                or spell.name
        end
    end
    table.sort(names)
    return names
end

local events = CreateFrame("Frame")
events:RegisterEvent("TRAINER_SHOW")
events:SetScript("OnEvent", function()
    -- the list fills in just after the window opens
    C_Timer.After(0.2, StartRead)
end)
