if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...
local GamePad = TotemTimers.GamePad

local overriddenSlots = GamePad.overriddenSlots

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- Option GamePadUpdateRanks: when a new rank of a spell is learned (at the trainer), the lower ranks of that spell
-- in the Gamepad UI action slots (all standard pages, storage slots of GamepadActionBarBindingUtil) are replaced by
-- the highest known rank. Only spells learned now are replaced, other lower ranks placed on purpose stay.
-- Option GamePadUpdateRanksOnLogin: on login and UI reload the lower ranks of all spells in these slots are replaced.
-- The slots taken over by TotemTimers in bar mode (on all pages) are skipped. Actions can't be placed in combat, the
-- replacement then waits for the end of combat.
local pendingRankNames = {}
local pendingAllRanks = false

local function GetTotemTimersPageUnitSlots()
    local slots = {}
    for slot in pairs(overriddenSlots) do
        local id = slot.GetGamepadPageUnitSlotID and slot:GetGamepadPageUnitSlotID()
        if id then slots[id] = true end
    end
    return slots
end

-- highest known rank by name: by name the spell API returns the highest rank the player knows
local function GetHighestRank(name)
    local info = C_Spell.GetSpellInfo(name)
    if info and info.spellID and IsPlayerSpell(info.spellID) then return info.spellID end
end

local function ReplaceLowerRanks()
    local profile = TotemTimers.ActiveProfile
    if not profile then return end
    if not (profile.GamePad and profile.GamePadUpdateRanks) then wipe(pendingRankNames) end
    if not (profile.GamePad and profile.GamePadUpdateRanksOnLogin) then pendingAllRanks = false end
    if not (pendingAllRanks or next(pendingRankNames)) then return end
    -- the Gamepad UI action bars can be loaded later (ADDON_LOADED)
    local util = GamepadActionBarBindingUtil
    local constants = Constants.GamepadActionBarConstants
    if not (util and util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID and constants) then return end
    -- in combat, or something on the cursor that placing would drop: later
    if InCombatLockdown() then return end
    if GetCursorInfo() then
        C_Timer.After(1, ReplaceLowerRanks)
        return
    end

    -- all spells (login) or the learned ones; false: no known rank
    local all = pendingAllRanks
    local highest = {}
    if not all then
        for name in pairs(pendingRankNames) do highest[name] = GetHighestRank(name) or false end
    end
    wipe(pendingRankNames)
    pendingAllRanks = false

    local skipped = GetTotemTimersPageUnitSlots()
    for page = 1, constants.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT do
        for pageUnitSlotID = 1, constants.NUM_PAGEABLE_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT_STANDARD_PAGE do
            local action = not skipped[pageUnitSlotID]
                    and util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(page, pageUnitSlotID)
            if action then
                local actionType, id = GetActionInfo(action)
                if actionType == "spell" and id and not IsSecret(id) then
                    local name = C_Spell.GetSpellName(id)
                    if name and all and highest[name] == nil then highest[name] = GetHighestRank(name) or false end
                    local target = name and highest[name]
                    if target and target ~= id then
                        C_Spell.PickupSpell(target)
                        PlaceAction(action)
                        -- the replaced rank is on the cursor now
                        ClearCursor()
                    end
                end
            end
        end
    end
end

-- the setup can come later than the delay after PLAYER_ENTERING_WORLD (it waits for SPELLS_CHANGED), then the
-- profile isn't selected yet and the login replacement runs after the setup
hooksecurefunc(TotemTimers, "SetupGlobals", function()
    if pendingAllRanks then C_Timer.After(1, ReplaceLowerRanks) end
end)

local rankFrame = CreateFrame("Frame")
rankFrame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
rankFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rankFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
rankFrame:RegisterEvent("ADDON_LOADED")
rankFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "LEARNED_SPELL_IN_SKILL_LINE" then
        local profile = TotemTimers.ActiveProfile
        if not (profile and profile.GamePad and profile.GamePadUpdateRanks) then return end
        local spellID = ...
        local name = spellID and C_Spell.GetSpellName(spellID)
        if not name then return end
        pendingRankNames[name] = true
        -- the spell book is updated after the event
        C_Timer.After(0.2, ReplaceLowerRanks)
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        if not (isLogin or isReload) then return end
        -- the profile is selected on PLAYER_ENTERING_WORLD, checked when the replacement runs
        pendingAllRanks = true
        -- after the setup (profile, bar mode slots) and the spell book
        C_Timer.After(1, ReplaceLowerRanks)
    elseif event == "ADDON_LOADED" then
        if ... == "Blizzard_GamepadActionBars" then ReplaceLowerRanks() end
    else
        ReplaceLowerRanks()
    end
end)
