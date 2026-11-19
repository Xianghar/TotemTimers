if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...

TotemTimers.AvailableSpells = {}
TotemTimers.AvailableTalents = {}

TotemTimers.SpellTextures = {}
TotemTimers.SpellNames = {}
TotemTimers.NameToSpellID = {}
TotemTimers.TextureToSpellID = {}
TotemTimers.ForceSpellNames = {}

local SpellIDs = TotemTimers.SpellIDs
local SpellIDsForceNames = TotemTimers.SpellIDsForceNames or {}
local ForceSpellNames = TotemTimers.ForceSpellNames
local AvailableSpells = TotemTimers.AvailableSpells
local SpellNames = TotemTimers.SpellNames
local SpellTextures = TotemTimers.SpellTextures
local NameToSpellID = TotemTimers.NameToSpellID
local TextureToSpellID = TotemTimers.TextureToSpellID


-- populate SpellNames and NameToSpellID with unranked spells first
-- TT inits with that info and upgrades ranks later when ranks are available

for _, spellID in pairs(SpellIDs) do
    local info = C_Spell.GetSpellInfo(spellID)
    if info and info.name then
        NameToSpellID[info.name] = spellID
        SpellNames[spellID] = info.name
        SpellTextures[spellID] = info.iconID
        TextureToSpellID[info.iconID] = spellID
        -- needed for Season of Discovery
        if (spellID > 400000 or SpellIDsForceNames[spellID]) then
            ForceSpellNames[info.name] = true
        end
    end
    AvailableSpells[spellID] = IsPlayerSpell(spellID) or IsSpellKnownOrOverridesKnown(spellID)
end

-- get ranked spell names from spell book
function TotemTimers.GetSpells()
    wipe(AvailableSpells)
    for _, spellID in pairs(SpellIDs) do
        AvailableSpells[spellID] = IsPlayerSpell(spellID) or IsSpellKnownOrOverridesKnown(spellID)
    end
end


-- spells (by ID and by name) of the talents with a rank in the active loadout of the talent tree
local function GetSelectedTalentSpells()
    local ids, names = {}, {}
    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID()
    local configInfo = configID and C_Traits.GetConfigInfo(configID)
    if not configInfo then return ids, names end
    for _, treeID in ipairs(configInfo.treeIDs) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
            local node = C_Traits.GetNodeInfo(configID, nodeID)
            local entryID = node and node.activeRank > 0 and node.activeEntry and node.activeEntry.entryID
            local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
            local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
            if definition then
                for _, spellID in pairs({ definition.spellID, definition.overriddenSpellID }) do
                    ids[spellID] = true
                    local name = C_Spell.GetSpellName(spellID)
                    if name then names[name] = true end
                end
            end
        end
    end
    return ids, names
end

-- AvailableTalents[key] is true if a talent of TotemTimers.TalentSpells[key] (TotemData) is taken in the talent
-- tree; the spells are compared by ID and by name, so other IDs of the same talent count, too. Without loaded talent
-- data (early at login) nothing is available, the trait events (TRAIT_CONFIG_LIST_UPDATED, TRAIT_CONFIG_UPDATED)
-- read the talents again.
function TotemTimers.GetTalents()
    wipe(TotemTimers.AvailableTalents)
    local ids, names = GetSelectedTalentSpells()
    for key, spells in pairs(TotemTimers.TalentSpells or {}) do
        for _, spell in ipairs(spells) do
            local name = C_Spell.GetSpellName(spell)
            if ids[spell] or (name and names[name]) then
                TotemTimers.AvailableTalents[key] = true
                break
            end
        end
    end
end



function TotemTimers.GetBaseSpellID(spell)
    local name = C_Spell.GetSpellName(spell)
    if not name then
        return spell
    end
    return NameToSpellID[name] or spell
end

local function UpdateSpellRank(spell, useName)
    local name = C_Spell.GetSpellName(spell)

    return useName and name or (name and C_Spell.GetSpellIDForSpellIdentifier(name))
end

if LE_EXPANSION_LEVEL_CURRENT < 2 then
    UpdateSpellRank = function(spell, useName)
        local name = C_Spell.GetSpellName(spell)
        if not name then return nil end
        -- ... or spell is a workaround for SOD GetSpellInfo not working immediately on login
        return (useName or ForceSpellNames[name]) and name or (C_Spell.GetSpellIDForSpellIdentifier(name) or spell)
    end
end

if LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_MISTS_OF_PANDARIA then
    UpdateSpellRank = function(spell)
        local name = C_Spell.GetSpellName(spell)
        return name
    end
end

TotemTimers.UpdateSpellRank = UpdateSpellRank

local function UpdateRank(button)
    for i = 1, 3 do
        for _, type in pairs({ "*spell", "spell", "doublespell" }) do
            local spell = button:GetAttribute(type .. i)
            if spell then
                local newRank = UpdateSpellRank(spell, (type == "doublespell") or button.useSpellNames)
                -- lower rank for ft for ft/ft-button on weapon tracker
                if type == "doublespell" and i == 1 and newRank == SpellNames[SpellIDs.FlametongueWeapon] then
                    local rank = GetSpellSubtext(SpellNames[SpellIDs.FlametongueWeapon])
                    if rank then
                        local lowerRank = string.gsub(rank, "(%d+)", function(rank) return tostring(tonumber(rank) -1) end)
                        newRank = SpellNames[SpellIDs.FlametongueWeapon].."("..lowerRank..")"
                    end
                end
                if newRank then
                    button:SetAttribute(type .. i, newRank)
                end
            end
        end
    end
end

TotemTimers.UpdateRank = UpdateRank

function TotemTimers.UpdateSpellRanks()
    for _, timer in pairs(XiTimers.timers) do
        UpdateRank(timer.button)
        if timer.actionBar then
            for _, actionButton in pairs(timer.actionBar.buttons) do
                UpdateRank(actionButton)
            end
        end
    end
    if TotemTimers.MaelstromButton then
        UpdateRank(TotemTimers.MaelstromButton)
    end
end

TotemTimers.Specialization = 2

-- get specialization, if no points are spent (e.g. talents reset) do not change specialization

if LE_EXPANSION_LEVEL_CURRENT >= LE_EXPANSION_CATACLYSM then
    function TotemTimers.GetSpecialization()
        local specfunc = GetPrimaryTalentTree or C_SpecializationInfo.GetSpecialization
        local spec = specfunc()
        if spec and spec > 0 then
            TotemTimers.Specialization = spec
        elseif not TotemTimers.Specialization then
            TotemTimers.Specialization = 2
        end
        TotemTimers.AddDebug("Spec: "..TotemTimers.Specialization)
    end
else

    if not GetTalentTabInfo then
        function TotemTimers.GetSpecialization()
            TotemTimers.Specialization = 2
        end
    else
        function TotemTimers.GetSpecialization()
            local pointsSpent = 0
            for i=1,3 do
                local points = select(LE_EXPANSION_LEVEL_CURRENT < LE_EXPANSION_WRATH_OF_THE_LICH_KING and 5 or 3, GetTalentTabInfo(i))
                if points and points > pointsSpent then
                    pointsSpent = points
                    TotemTimers.Specialization = i
                end
            end
            TotemTimers.AddDebug("Spec: "..TotemTimers.Specialization)
        end
    end
end

function TotemTimers.ChangedTalents()
    TotemTimers.GetSpecialization()
    TotemTimers.GetSpells()
    TotemTimers.GetTalents()
    TotemTimers.SelectActiveProfile()
    TotemTimers.ExecuteProfile()
    TotemTimers.UpdateSpellRanks()

    if TotemTimers.SpellUpdaters then
        for _, updater in pairs(TotemTimers.SpellUpdaters) do
            updater()
        end
    end
end
