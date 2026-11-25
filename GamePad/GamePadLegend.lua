if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...
local GamePad = TotemTimers.GamePad

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers", true)
local GetPadIconMarkup = GamePad.GetPadIconMarkup
local LayerKeyBars = GamePad.LayerKeyBars
local barModeSlots = GamePad.barModeSlots
local TimerKeys = GamePad.TimerKeys
local FaceButtonIndices = GamePad.FaceButtonIndices
local DPAD_LEFT_INDEX = GamePad.DPAD_LEFT_INDEX
local OPEN_BUTTON_INDEX = GamePad.OPEN_BUTTON_INDEX
local DPAD_RIGHT_INDEX = GamePad.DPAD_RIGHT_INDEX
local DPAD_DOWN_INDEX = GamePad.DPAD_DOWN_INDEX
local GetAvailableSpellName = GamePad.GetAvailableSpellName
local GetWeaponButton = GamePad.GetWeaponButton
local SpellIDs = TotemTimers.SpellIDs

-- Input legend (bar mode): while the triggers of the layer key are held, a legend of TotemTimers' slots is shown in
-- place of the Gamepad UI's persistent input legend (GamepadPersistentInputLegend, which has no group for the
-- action bar triggers). It is a frame of our own built from the game's legend templates and laid out like the
-- game's groups (Blizzard_Gamepad/UI/PersistentInputLegend); the game's legend is only faded out meanwhile.
-- Visual only, so the state of the triggers is taken from the game (GamepadMode, not secure).
local LEGEND_ROW_HEIGHT = 24
local LEGEND_INDENT = 20
local LEGEND_HEADER_OFFSET = 10
local LEGEND_ICON_SIZE = 18
local LEGEND_COLUMN_WIDTH = 230
local LEGEND_ROWS = 4

-- entries: column 0 the d-pad, column 1 the face buttons, rows 1-4 (row 0 is the header)
local LegendEntries = {
    { key = "PADDUP", column = 0, row = 1, slot = OPEN_BUTTON_INDEX },
    { key = "PADDRIGHT", column = 0, row = 2, slot = DPAD_RIGHT_INDEX },
    { key = "PADDDOWN", column = 0, row = 3, slot = DPAD_DOWN_INDEX },
    { key = "PADDLEFT", column = 0, row = 4, slot = DPAD_LEFT_INDEX },
    { key = "PAD1", column = 1, row = 1, element = EARTH_TOTEM_SLOT },
    { key = "PAD3", column = 1, row = 2, element = FIRE_TOTEM_SLOT },
    { key = "PAD4", column = 1, row = 3, element = WATER_TOTEM_SLOT },
    { key = "PAD2", column = 1, row = 4, element = AIR_TOTEM_SLOT },
}

-- the triggers of a bar mode layer key
local LayerKeyTriggers = {
    PADLTRIGGER = { "PADLTRIGGER" },
    PADRTRIGGER = { "PADRTRIGGER" },
    ["PADLTRIGGER+PADRTRIGGER"] = { "PADLTRIGGER", "PADRTRIGGER" },
}

local legend

local function CreateLegendEntry(parent, keys, column, row)
    local template = #keys > 1 and "GamepadPersistentInputLegendEntryWithTwoIconsTemplate"
            or "GamepadPersistentInputLegendEntryTemplate"
    local entry = CreateFrame("Frame", nil, parent, template)
    for i, key in ipairs(keys) do
        entry:SetPromptInputIconKey(i, key)
        entry:SetInputIconSize(i, LEGEND_ICON_SIZE, LEGEND_ICON_SIZE)
    end
    entry:EnablePrompt()
    local y = -LEGEND_INDENT - LEGEND_ROW_HEIGHT * row
    if row > 0 then y = y - LEGEND_HEADER_OFFSET end
    entry:ClearAllPoints()
    entry:SetPoint("TOPLEFT", parent, "TOPLEFT", LEGEND_INDENT + column * LEGEND_COLUMN_WIDTH, y)
    return entry
end

local function BuildLegend()
    if legend then return legend end
    -- the game's legend (and its templates) exist with the Gamepad UI addons only
    if not GamepadPersistentInputLegend then return end
    legend = CreateFrame("Frame", "TotemTimers_GamePadLegend", UIParent)
    legend:SetFrameStrata("LOW")
    legend:SetSize(10, 10)
    legend:SetPoint("TOPLEFT", GamepadPersistentInputLegend, "TOPLEFT")
    legend:Hide()

    local background = CreateFrame("Frame", nil, legend, "GamepadPersistentInputLegendBackgroundTemplate")
    background:SetSize(LEGEND_INDENT + 2 * LEGEND_COLUMN_WIDTH,
            LEGEND_ROW_HEIGHT * LEGEND_ROWS + LEGEND_INDENT * 2 - (LEGEND_ROW_HEIGHT - LEGEND_ICON_SIZE)
                    + LEGEND_ROW_HEIGHT + LEGEND_HEADER_OFFSET)
    background:SetPoint("TOPLEFT", legend, "TOPLEFT")
    background.HeaderTrim:Show()
    background.HeaderTrim:SetDesaturation(1.0)
    background:Show()

    legend.entries = {}
    for _, info in ipairs(LegendEntries) do
        legend.entries[info] = CreateLegendEntry(legend, { info.key }, info.column, info.row)
    end
    legend.headers = {}
    return legend
end

-- texts of the entries: the spells of the slots (totem names of the timers), nil hides the entry
local function GetLegendText(info)
    if info.element then
        for i = 1, 4 do
            local timer = XiTimers.timers[i]
            if timer and timer.nr == info.element then
                local index = FaceButtonIndices[TimerKeys[timer.nr]]
                local spell = barModeSlots[index] and timer.button:GetAttribute("*spell1")
                return spell and C_Spell.GetSpellName(spell)
            end
        end
        return nil
    end
    if not barModeSlots[info.slot] then return nil end
    if info.slot == OPEN_BUTTON_INDEX then
        local weaponButton = GetWeaponButton()
        local spell = weaponButton and weaponButton:GetAttribute("spell1")
        return spell and C_Spell.GetSpellName(spell)
    elseif info.slot == DPAD_RIGHT_INDEX then
        local multiSpell = TotemTimers_MultiSpell
        if multiSpell and multiSpell:GetAttribute("ttmacro") then return L["Castsequence Macro"] end
        local spell = multiSpell and multiSpell:GetAttribute("*spell1")
        return spell and C_Spell.GetSpellName(spell)
    elseif info.slot == DPAD_DOWN_INDEX then
        return GetAvailableSpellName(SpellIDs.TotemicRecall)
    elseif info.slot == DPAD_LEFT_INDEX then
        return GetAvailableSpellName(SpellIDs.TotemicCall)
    end
end

-- header: the icons of the layer key's triggers and "TotemTimers" (one entry per trigger combination)
local function GetLegendHeader(triggers)
    local id = table.concat(triggers, "+")
    if not legend.headers[id] then
        local header = CreateLegendEntry(legend, triggers, 0, 0)
        header:SetPromptText(WHITE_FONT_COLOR:WrapTextInColorCode("TotemTimers"))
        legend.headers[id] = header
    end
    return legend.headers[id]
end

local function AreLayerTriggersDown(triggers)
    if not (GamepadMode and GamepadMode.IsLeftModifierDown and GamepadMode.IsRightModifierDown) then return false end
    local left, right = GamepadMode.IsLeftModifierDown(), GamepadMode.IsRightModifierDown()
    if #triggers == 2 then return left and right end
    if triggers[1] == "PADLTRIGGER" then return left and not right end
    return right and not left
end

function GamePad.UpdateLegend()
    local key = GamePad.GetLayerKey()
    local triggers = GamePad.barMode and LayerKeyTriggers[key]
    local show = triggers and GamePad.nav and GamePad.nav:GetAttribute("enabled") and AreLayerTriggersDown(triggers)
            and GetCVarBool("GamepadShowPersistentInputLegend") and BuildLegend() and true or false

    if not legend then return end
    -- the game's legend is only touched when ours is shown or hidden
    if show ~= legend:IsShown() and GamepadPersistentInputLegend then
        GamepadPersistentInputLegend:SetAlpha(show and 0 or 1)
    end
    if not show then
        legend:Hide()
        return
    end

    for id, header in pairs(legend.headers) do header:Hide() end
    GetLegendHeader(triggers):Show()
    for info, entry in pairs(legend.entries) do
        local text = GetLegendText(info)
        if text then
            entry:SetPromptText(text)
            entry:Show()
        else
            entry:Hide()
        end
    end
    legend:Show()
end

-- the game's state of the action bar triggers changed (after its own handling, not secure)
local legendHooked = false
local function HookLegend()
    if legendHooked or not (GamepadMode and GamepadMode.OnCrossBarModifierChanged) then return end
    hooksecurefunc(GamepadMode, "OnCrossBarModifierChanged", GamePad.UpdateLegend)
    legendHooked = true
end

GamePad.HookLegend = HookLegend
