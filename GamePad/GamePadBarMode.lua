if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...
local GamePad = TotemTimers.GamePad

local TimerKeys = GamePad.TimerKeys
local FaceButtonIndices = GamePad.FaceButtonIndices
local DPAD_LEFT_INDEX = GamePad.DPAD_LEFT_INDEX
local OPEN_BUTTON_INDEX = GamePad.OPEN_BUTTON_INDEX
local DPAD_RIGHT_INDEX = GamePad.DPAD_RIGHT_INDEX
local DPAD_DOWN_INDEX = GamePad.DPAD_DOWN_INDEX
local GetAvailableSpellName = GamePad.GetAvailableSpellName
local GetWeaponButton = GamePad.GetWeaponButton
local GetSpellAttribute = GamePad.GetSpellAttribute
local menuIndices = GamePad.menuIndices
local barModeSlots = GamePad.barModeSlots
local SpellIDs = TotemTimers.SpellIDs

-- Bar mode: the layer key is a trigger (LT/RT). The trigger stays with the Gamepad UI (its bar expands, LT+RT works),
-- and the secure attributes of slots of the trigger's bar are changed so that pressing them casts TotemTimers'
-- spells: the game's own click handling of the slot (TriggerSecureClick -> SecureActionButton_OnClick) then runs
-- type "spell" instead of the slot's action. The game sets type "action" once and only changes the slot's ID when
-- paging, so the attributes stay; the slot's original action is unusable on all pages of the bar meanwhile.
-- The totem of a timer slot follows the timer's *spell1 by a secure wrap of the timer button (also in combat).

-- slots of the bar in bar mode: face buttons cast the totems of the timers, d-pad up opens the totem menus
-- (click on the navigation button), right casts the selected multicast spell, down Totemic Recall,
-- left Totemic Call

local overriddenSlots = {}

-- a source button (totem timer, multicast button) sets the spell of its bar slot when its spell changes,
-- also in combat
local SPELL_SOURCE_WRAP = [[
    if name == (self:GetAttribute("ttspellattr") or "*spell1") then
        local slot = self:GetFrameRef("ttGamePadSlot")
        if slot and slot:GetAttribute("ttGamePadOverride") == "spell" then
            slot:SetAttribute("spell", value)
        end
    end
]]

local wrappedSources = {}


-- actionType "spell" (value: spell) or "click" (value: button to click)
local function OverrideSlot(bar, index, actionType, value)
    local slot = index and bar:GetActionButtonByIndex(index)
    if not slot then return end
    slot:SetAttribute("ttGamePadOverride", actionType)
    slot:SetAttribute("typerelease", nil)
    slot:SetAttribute("type", actionType)
    if actionType == "spell" then
        slot:SetAttribute("spell", value)
    else
        slot:SetAttribute("clickbutton", value)
    end
    overriddenSlots[slot] = true
    barModeSlots[index] = true
    return slot
end

-- the slot casts the *spell1 of the source button and follows its changes
local function OverrideSlotWithSource(bar, index, source)
    local attr = GetSpellAttribute(source)
    local slot = OverrideSlot(bar, index, "spell", source:GetAttribute(attr))
    if not slot then return end
    -- the attribute the wraps follow and assign (SPELL_SOURCE_WRAP, HOLD_WRAP, WHEEL_ASSIGN)
    source:SetAttribute("ttspellattr", attr)
    SecureHandlerSetFrameRef(source, "ttGamePadSlot", slot)
    SecureHandlerSetFrameRef(slot, "ttGamePadSource", source)
    if not wrappedSources[source] then
        SecureHandlerWrapScript(source, "OnAttributeChanged", GamePad.nav, SPELL_SOURCE_WRAP)
        wrappedSources[source] = true
    end
end

local function RestoreSlots()
    for slot in pairs(overriddenSlots) do
        slot:SetAttribute("ttGamePadOverride", nil)
        slot:SetAttribute("ttHoldMenu", nil)
        slot:SetAttribute("ttWheelOpen", nil)
        slot:SetAttribute("ttTotemSlot", nil)
        slot:SetAttribute("totem-slot", nil)
        slot:SetAttribute("useOnKeyDown", true)
        slot:SetAttribute("spell", nil)
        slot:SetAttribute("clickbutton", nil)
        slot:SetAttribute("type", "action")
        slot:SetAttribute("typerelease", "actionrelease")
    end
    wipe(overriddenSlots)
    wipe(barModeSlots)
    -- a wheel left open, the update interval of the state driver (GamePadWheel.lua)
    GamePad.ReleaseHoldWheels()
end

local function ApplyBarMode(bar)
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and timer.button:IsShown() then
            local index = FaceButtonIndices[TimerKeys[timer.nr]]
            OverrideSlotWithSource(bar, index, timer.button)
            GamePad.SetupHoldWheel(bar, index, timer.button, timer.nr)
        end
    end
    -- d-pad up casts the weapon tracker's enchant (main hand), holding it opens the wheel of its menu
    local weaponButton = GetWeaponButton()
    if weaponButton and TotemTimers.ActiveProfile.WeaponTracker then
        OverrideSlotWithSource(bar, OPEN_BUTTON_INDEX, weaponButton)
        GamePad.SetupHoldWheel(bar, OPEN_BUTTON_INDEX, weaponButton)
    end
    -- a click on the multicast button would be handed on as a release, which it ignores (it casts on key down),
    -- so the slot casts its spell itself
    local multiSpell = TotemTimers_MultiSpell
    if multiSpell and multiSpell:GetAttribute("active") then
        OverrideSlotWithSource(bar, DPAD_RIGHT_INDEX, multiSpell)
        -- like the totems: cast on the release, holding opens the wheel of the multicast menu
        GamePad.SetupHoldWheel(bar, DPAD_RIGHT_INDEX, multiSpell)
    end
    local recall = GetAvailableSpellName(SpellIDs.TotemicRecall)
    if recall then OverrideSlot(bar, DPAD_DOWN_INDEX, "spell", recall) end
    local call = GetAvailableSpellName(SpellIDs.TotemicCall)
    if call then OverrideSlot(bar, DPAD_LEFT_INDEX, "spell", call) end
end

-- Option GamePadHideTimers (bar mode only): the totem timer buttons and the multicast button are made invisible
-- (alpha 0, mouse disabled), so the timers are only shown on the overlays of the bar slots. The buttons keep
-- working (the slots and menus use them); their menus stay visible as the menu buttons ignore the parent's alpha.
-- The out-of-combat fader sets the buttons' alpha on every combat change, a hook keeps hidden buttons at 0.
local hiddenTimerButtons = {}
local alphaHooked = {}

local function KeepHidden(button)
    if hiddenTimerButtons[button] and button:GetAlpha() ~= 0 then
        button:SetAlpha(0)
    end
end

-- the buttons (and their menus) hidden by the option
local function GetHideableButtons()
    local list = {}
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer then table.insert(list, { button = timer.button, menu = timer.actionBar }) end
    end
    local multiSpell = TotemTimers_MultiSpell
    if multiSpell then table.insert(list, { button = multiSpell, menu = multiSpell.actionBar }) end
    -- the shield and weapon trackers, their timers are shown on the Gamepad UI buttons of the spells; their menus
    -- open from the (then mouse disabled) buttons only, so they stay hidden with them
    for _, tracker in ipairs({ TotemTimers.ShieldTracker, TotemTimers.WeaponTracker }) do
        if tracker then table.insert(list, { button = tracker.button }) end
    end
    -- the Totemic Call button, Totemic Call and Totemic Recall are on d-pad left and down of the bar
    if TotemTimers.TotemicCallTimer then
        table.insert(list, { button = TotemTimers.TotemicCallTimer.button })
    end
    return list
end

-- out of combat only (mouse of secure buttons)
local function SetTimersHidden(hide)
    hide = hide and true or false
    local restored = false
    for _, entry in ipairs(GetHideableButtons()) do
        local button = entry.button
        if hide ~= (hiddenTimerButtons[button] or false) then
            hiddenTimerButtons[button] = hide or nil
            if not alphaHooked[button] then
                hooksecurefunc(button, "SetAlpha", KeepHidden)
                alphaHooked[button] = true
            end
            if entry.menu then
                for _, menuButton in ipairs(entry.menu.buttons) do
                    menuButton:SetIgnoreParentAlpha(hide)
                end
                if entry.menu.extraButton then entry.menu.extraButton:SetIgnoreParentAlpha(hide) end
            end
            if hide then
                button:SetAlpha(0)
                button:EnableMouse(false)
            else
                button:EnableMouse(true)
                restored = true
            end
        end
    end
    if restored then
        -- alpha (out-of-combat fader) and clickthrough of the timers as set by their own options
        XiTimers.invokeOOCFader()
        TotemTimers.ProcessSetting("Timer_Clickthrough")
    end
end

-- With hidden timers the menus are shown at the bar slots of their buttons (totem timers: face button slots,
-- multicast: d-pad right), growing upwards. They are anchored to the game's slot buttons (not the overlays, which
-- have to stay movable in combat). The navigation orders the menus by the slots then (frame refs "menupos<m>").
-- bar: the bar of the layer key, nil restores the normal menu positions. Out of combat only.
local menusAtBar = {}

local function SetMenuAtBar(parent, actionBar, slot)
    if not actionBar then return end
    local m = menuIndices[parent]
    if m then SecureHandlerSetFrameRef(GamePad.nav, "menupos" .. m, slot or parent) end
    if slot then
        actionBar:SetMenuAnchor(slot, "up")
        menusAtBar[actionBar] = true
    elseif menusAtBar[actionBar] then
        actionBar:SetMenuAnchor(nil)
        menusAtBar[actionBar] = nil
    end
end

local function SetMenusAtBar(bar)
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer then
            local slot = bar and bar:GetActionButtonByIndex(FaceButtonIndices[TimerKeys[timer.nr]])
            SetMenuAtBar(timer.button, timer.actionBar, slot)
        end
    end
    local multiSpell = TotemTimers_MultiSpell
    if multiSpell then
        local slot = bar and bar:GetActionButtonByIndex(DPAD_RIGHT_INDEX)
        SetMenuAtBar(multiSpell, multiSpell.actionBar, slot)
    end
    local weapon = TotemTimers.WeaponTracker
    if weapon then
        local slot = bar and bar:GetActionButtonByIndex(OPEN_BUTTON_INDEX)
        SetMenuAtBar(weapon.button, weapon.actionBar, slot)
    end
end

-- shared with GamePad.lua (Apply, Debug) and GamePadWheel.lua
GamePad.overriddenSlots = overriddenSlots
GamePad.RestoreSlots = RestoreSlots
GamePad.ApplyBarMode = ApplyBarMode
GamePad.SetTimersHidden = SetTimersHidden
GamePad.SetMenusAtBar = SetMenusAtBar
