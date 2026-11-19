if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...
local GamePad = TotemTimers.GamePad

local TimerKeys = GamePad.TimerKeys
local LayerKeyBars = GamePad.LayerKeyBars
local FaceButtonIndices = GamePad.FaceButtonIndices
local DPAD_LEFT_INDEX = GamePad.DPAD_LEFT_INDEX
local OPEN_BUTTON_INDEX = GamePad.OPEN_BUTTON_INDEX
local DPAD_RIGHT_INDEX = GamePad.DPAD_RIGHT_INDEX
local DPAD_DOWN_INDEX = GamePad.DPAD_DOWN_INDEX
local GetAvailableSpellName = GamePad.GetAvailableSpellName
local SpellIDs = TotemTimers.SpellIDs

-- icons (and the remaining totem durations) of the layer's actions over the slots of the Gamepad UI action bar of
-- the layer key. They are on frames of our own above the slots' cooldowns (so the swipes of the slots' own actions
-- are covered), nothing of the slots is changed, and everything can be updated in combat.
-- As the game doesn't see the layer key, it doesn't expand that bar while the key is held. The overlays copy the
-- expanded look instead (bigger slots at the expanded positions, focus shadows, the bar's focus background);
-- the slots themselves are secure buttons and can't be resized by addons in combat.
local barIcons = {}

local CIRCLE_SWIPE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_SWIPE = "Interface\\Buttons\\WHITE8X8"

-- mask inset from the slot edges, like the CircleMask/SquareMask of the gamepad buttons (ActionBarButton.xml)
local MASK_INSET = 3

-- icon of the active totem (with hidden timers): size and offset downwards relative to the slot's size,
-- mask inset scaled like the size, border of the round gamepad slots (ActionBarButton.lua CIRCLE_NORMAL_FRAME_ATLAS)
local ACTIVE_SIZE = 0.6
local ACTIVE_OFFSET_X = 0.1
local ACTIVE_OFFSET_Y = 0.3
local ACTIVE_MASK_INSET = MASK_INSET * ACTIVE_SIZE
local ROUND_SLOT_BORDER = "gamepad-actionbar-circleslot-border-normal"

-- the active totem icon is shown on the totem slots (option GamePadHideTimers in bar mode)
-- option GamePadTimers: timers on the Gamepad UI buttons (totem durations on the bar slots, shield charges, weapon
-- enchant times and glow); without it the slots only show the icons and GamePadHideTimers is ignored

-- slots showing the active totem of a timer, by the timer button's icon (which shows the active totem)
local activeIconSlots = {}
local activeIconHooked = {}

-- expanded look of the Gamepad UI action bars (ActionBarStyles.lua, LEFTSQUARE_RIGHTCIRCLE_STYLE):
-- slot centers relative to the bar's center by slot index (d-pad left, up, right, down, then the face buttons
-- left, top, right, bottom), slot sizes and the distance of the focus shadow
local ExpandedOffsets = {
    { -119, 0 }, { -75, 23 }, { -31, 0 }, { -75, -23 },
    { 32, 0 }, { 70, 23 }, { 108, 0 }, { 70, -23 },
}
local EXPANDED_SIZE_ROUND = 38
local EXPANDED_SIZE_SQUARE = 40
local EXPANDED_SHADOW_DISTANCE = 13
local FOCUS_SHADOW_ROUND = "gamepad-actionbar-focus-bg-circ"
local FOCUS_SHADOW_SQUARE = "gamepad-actionbar-focus-bg-square"

local layerExpanded = false

-- range dots of the totem slots (like on the totem timer buttons, see TotemTimers.AddRangeDots)
local RANGE_DOT_TEXTURE = "Interface\\AddOns\\TotemTimers\\textures\\dot"
local RANGE_DOT_SIZE = 6
local RangeDotKeys = { "playerDot", "party1", "party2", "party3", "party4" }

-- the first party dot takes the place of the player's dot unless the player has a dot (option PlayerRangeStyle);
-- only own hidden anchor textures are moved, so this works in combat
local function UpdateRangeDotLayout(slot)
    local dots = slot.rangeDots
    if not dots then return end
    local playerDot = TotemTimers.ActiveProfile and TotemTimers.ActiveProfile.PlayerRangeStyle == "dot"
    dots.party1:ClearAllPoints()
    if playerDot then
        dots.party1:SetPoint("LEFT", dots.playerDot, "RIGHT", 1, 0)
    else
        dots.party1:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
    end
end

-- bar mode (layer key is a trigger): the key stays with the game, slots of its bar are TotemTimers buttons;
-- only those slots get overlays (by bar button index)
local barModeSlots = {}

local function GetLayerKeyBar()
    local barKey = LayerKeyBars[GamePad.GetLayerKey()]
    local pageUnit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
    local bar = barKey and pageUnit and pageUnit.actionBars and pageUnit.actionBars[barKey]
    if bar and bar.GetActionButtonByIndex then return bar end
end
GamePad.GetLayerKeyBar = GetLayerKeyBar

local function GetBarIcon(button, index)
    local slot = barIcons[button]
    if not slot then
        slot = CreateFrame("Frame", nil, button)
        slot:SetFrameLevel((button.cooldown and button.cooldown:GetFrameLevel() or button:GetFrameLevel()) + 1)
        slot:EnableMouse(false)
        slot.button = button

        -- focus shadow below the icon while the bar is expanded
        slot.shadow = slot:CreateTexture(nil, "BACKGROUND")
        slot.shadow:SetPoint("TOPLEFT", -EXPANDED_SHADOW_DISTANCE, EXPANDED_SHADOW_DISTANCE)
        slot.shadow:SetPoint("BOTTOMRIGHT", EXPANDED_SHADOW_DISTANCE, -EXPANDED_SHADOW_DISTANCE)
        slot.shadow:Hide()

        -- like on the gamepad buttons the icon covers the whole slot with full tex coords and the mask (inset from
        -- the slot's edges) cuts out the visible part
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints(slot)
        slot.icon:SetTexCoord(0, 1, 0, 1)
        slot.mask = slot:CreateMaskTexture()
        slot.mask:SetPoint("TOPLEFT", MASK_INSET, -MASK_INSET)
        slot.mask:SetPoint("BOTTOMRIGHT", -MASK_INSET, MASK_INSET)
        slot.icon:AddMaskTexture(slot.mask)

        slot.cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
        slot.cooldown:SetPoint("TOPLEFT", MASK_INSET, -MASK_INSET)
        slot.cooldown:SetPoint("BOTTOMRIGHT", -MASK_INSET, MASK_INSET)
        slot.cooldown:SetDrawEdge(false)
        slot.cooldown:SetDrawBling(false)

        -- above the swipe: the border of the gamepad button (copy of its normal texture)
        local overlay = CreateFrame("Frame", nil, slot)
        overlay:SetAllPoints(slot)
        overlay:SetFrameLevel(slot.cooldown:GetFrameLevel() + 1)
        slot.border = overlay:CreateTexture(nil, "ARTWORK")
        slot.border:SetAllPoints(slot)

        -- above the border: the icon of the active totem (with hidden timers), a round button in the bottom right
        -- corner of the slot (ACTIVE_SIZE of the slot's size, moved right and down by ACTIVE_OFFSET_X/Y of the
        -- slot's width/height),
        -- following the slot's size (the bar expands)
        local active = CreateFrame("Frame", nil, slot)
        -- the element is excluded from the active multicast spell: the icon of the timer buttons
        -- (TotemTimers.CreateExcludedIcon) in the bottom left corner like there, 0.4 of the slot's size
        slot.excluded = TotemTimers.CreateExcludedIcon(slot)
        local function UpdateActiveSize()
            local width, height = slot:GetSize()
            active:SetSize(width * ACTIVE_SIZE, height * ACTIVE_SIZE)
            active:ClearAllPoints()
            active:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", width * ACTIVE_OFFSET_X, -height * ACTIVE_OFFSET_Y)
            slot.excluded:SetSize(width * 0.4, height * 0.4)
            slot.excluded:ClearAllPoints()
            slot.excluded:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", MASK_INSET, MASK_INSET - height * 0.06)
        end
        UpdateActiveSize()
        slot:SetScript("OnSizeChanged", UpdateActiveSize)
        active:SetFrameLevel(overlay:GetFrameLevel() + 1)
        active.icon = active:CreateTexture(nil, "ARTWORK")
        active.icon:SetAllPoints(active)
        active.mask = active:CreateMaskTexture()
        active.mask:SetAtlas("CircleMask", false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        active.mask:SetPoint("TOPLEFT", ACTIVE_MASK_INSET, -ACTIVE_MASK_INSET)
        active.mask:SetPoint("BOTTOMRIGHT", -ACTIVE_MASK_INSET, ACTIVE_MASK_INSET)
        active.icon:AddMaskTexture(active.mask)
        active.border = active:CreateTexture(nil, "OVERLAY")
        active.border:SetAtlas(ROUND_SLOT_BORDER)
        active.border:SetAllPoints(active)
        active:Hide()
        slot.active = active

        -- above everything: remaining time like on the timer buttons, bound to the DurationObject; without text
        -- bindings the cooldown's countdown numbers are used instead
        local texts = CreateFrame("Frame", nil, slot)
        texts:SetAllPoints(slot)
        texts:SetFrameLevel(active:GetFrameLevel() + 1)
        if XiTimers.CanBindDurationText then
            slot.cooldown:SetHideCountdownNumbers(true)
            slot.time = texts:CreateFontString(nil, "OVERLAY")
            slot.time:SetFontObject(TotemTimersButtonTimeFont)
            slot.time:SetPoint("CENTER", slot, "CENTER")
            slot.timeBinding = XiTimers.CreateDurationTextBinding()
            slot.timeBinding:SetFontString(slot.time)
        else
            slot.cooldown:SetHideCountdownNumbers(false)
        end

        -- glow of the weapon tracker on its slot (d-pad up in bar mode, see UpdateWeaponSlotGlow), on a frame of
        -- its own above everything
        slot.glow = CreateFrame("Frame", nil, slot)
        slot.glow:SetAllPoints(slot)
        slot.glow:SetFrameLevel(texts:GetFrameLevel() + 1)
        -- behind the texts (duration)
        slot.excluded:SetFrameLevel(active:GetFrameLevel())

        -- anchors of the range dots (see ShowSlot), hidden: the dots are drawn by aura containers over them;
        -- a row along the top edge, the player's dot first (option PlayerRangeStyle "dot", otherwise the party dots
        -- move to its place and the player's buff tints the icon, see UpdateRangeDotLayout)
        slot.rangeDots = { player = slot.icon }
        local previous
        for _, key in ipairs(RangeDotKeys) do
            local dot = slot:CreateTexture(nil, "OVERLAY")
            dot:SetTexture(RANGE_DOT_TEXTURE)
            dot:SetSize(RANGE_DOT_SIZE, RANGE_DOT_SIZE)
            if previous then
                dot:SetPoint("LEFT", previous, "RIGHT", 1, 0)
            else
                dot:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
            end
            dot:Hide()
            slot.rangeDots[key] = dot
            previous = dot
        end
        UpdateRangeDotLayout(slot)
        barIcons[button] = slot
    end
    slot.index = index
    return slot
end

-- shape of the slot (round or square), the gamepad buttons switch between their masks
local function UpdateSlotShape(slot, button)
    local round = not (button.SquareMask and button.SquareMask:IsShown())
    if slot.round == round then return end
    slot.round = round
    slot.mask:SetAtlas(round and "CircleMask" or "SquareMask", false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    slot.cooldown:SetSwipeTexture(round and CIRCLE_SWIPE or SQUARE_SWIPE)
    slot.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    slot.shadow:SetAtlas(round and FOCUS_SHADOW_ROUND or FOCUS_SHADOW_SQUARE)
end

-- border of the gamepad button: its normal texture (round or square slot frame, covering the whole button)
local function UpdateSlotBorder(slot, button)
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if not normal then
        slot.border:Hide()
        return
    end
    local atlas = normal:GetAtlas()
    if atlas then
        slot.border:SetAtlas(atlas)
    else
        slot.border:SetTexture(normal:GetTexture())
        slot.border:SetTexCoord(normal:GetTexCoord())
    end
    slot.border:SetVertexColor(normal:GetVertexColor())
    slot.border:Show()
end

-- position and size of the slot: over its button, or expanded like the game expands a focused bar
local function UpdateSlotLayout(slot, bar)
    slot:ClearAllPoints()
    local offset = layerExpanded and ExpandedOffsets[slot.index]
    if offset then
        local size = slot.round and EXPANDED_SIZE_ROUND or EXPANDED_SIZE_SQUARE
        slot:SetPoint("CENTER", bar, "CENTER", offset[1], offset[2])
        slot:SetSize(size, size)
        slot.shadow:Show()
    else
        slot:SetAllPoints(slot.button)
        slot.shadow:Hide()
    end
end

-- the active totem of the timer (timer.activeTotem, from the own cast) differs from the totem assigned to its
-- button (*spell1). Compared by name, so ranks don't matter; an unknown active totem counts as different.
local function IsOtherTotemActive(timer)
    local active = timer and timer.activeTotem
    if not active or (issecretvalue and issecretvalue(active)) then return true end
    local assigned = timer.button:GetAttribute("*spell1")
    if not assigned then return true end
    return C_Spell.GetSpellName(active) ~= C_Spell.GetSpellName(assigned)
end

-- remaining duration of the totem, from the DurationObject of the running totem timer (never read in Lua),
-- and the icon of the active totem while the timer runs and it isn't the assigned totem; on slots of a spell with
-- a cooldown (slot.cooldownSpell) its cooldown instead (without the global cooldown, shown without option
-- GamePadTimers too, like the cooldown of the game's own button)
-- DurationObject of the global cooldown of the spell, nil while it isn't on the GCD (only the never secret isActive and
-- isOnGCD flags are read)
local function GetGCDDuration(spell)
    if not spell or spell == 0 then return end
    local info = C_Spell.GetSpellCooldown(spell)
    if info and info.isActive and info.isOnGCD then
        return C_Spell.GetSpellCooldownDuration(spell)
    end
end

-- without a duration the slot shows the global cooldown of its spell (slot.spell) like the game's buttons, swipe
-- only (no time)
local function UpdateSlotDuration(slot)
    local durObj
    if slot.timer then
        durObj = GamePad.timersShown and slot.timer.timers[1]
    elseif slot.cooldownSpell then
        local info = C_Spell.GetSpellCooldown(slot.cooldownSpell)
        if not (info and info.isOnGCD) then
            durObj = C_Spell.GetSpellCooldownDuration(slot.cooldownSpell, true)
        end
    end
    local swipe = durObj or GetGCDDuration(slot.spell)
    if swipe then
        slot.cooldown:SetCooldownFromDurationObject(swipe)
    else
        slot.cooldown:Clear()
    end
    slot.active:SetShown(GamePad.showActiveTotems and slot.timer and not slot.notTotem and durObj
            and IsOtherTotemActive(slot.timer) or false)
    if slot.timeBinding then
        if durObj then
            slot.timeBinding:SetDuration(durObj)
            slot.timeBinding:SetEnabled(true)
        else
            slot.timeBinding:SetEnabled(false)
            slot.time:SetText("")
        end
    end
end

-- the slot's icon is tinted blue while the player lacks the power (mana) for its spell (slot.spell), like the timer
-- buttons (XiTimers' rangeManaUpdate); insufficientPower of C_Spell.IsSpellUsable isn't secret
-- (a field of GamePad, not a local: the main chunk is at Lua's limit of 200 locals)
function GamePad.UpdateSlotManaColor(slot)
    local outOfMana = false
    if slot:IsShown() and slot.spell and slot.spell ~= 0 then
        local _, noMana = C_Spell.IsSpellUsable(slot.spell)
        outOfMana = noMana and true or false
    end
    if (slot.outOfMana or false) == outOfMana then return end
    slot.outOfMana = outOfMana
    if outOfMana then
        slot.icon:SetVertexColor(0.5, 0.5, 1)
    else
        slot.icon:SetVertexColor(1, 1, 1)
    end
end

-- shows a slot with the texture, timer: totem timer whose duration is shown, cooldownSpell: spell whose cooldown
-- is shown (slots without timer), notTotem: the timer isn't a totem timer (weapon tracker: its first timer is shown,
-- no active totem icon, no range dots), spell: the slot's spell, whose global cooldown is shown without a duration
local function ShowSlot(bar, index, texture, timer, cooldownSpell, notTotem, spell)
    if GamePad.barMode and not barModeSlots[index] then return end
    local button = texture and index and bar:GetActionButtonByIndex(index)
    if not (button and button.icon) then return end
    local slot = GetBarIcon(button, index)
    UpdateSlotShape(slot, button)
    UpdateSlotBorder(slot, button)
    UpdateSlotLayout(slot, bar)
    slot.icon:SetTexture(texture)
    slot.timer = timer
    slot.notTotem = notTotem
    slot.cooldownSpell = not timer and cooldownSpell or nil
    slot.spell = spell or cooldownSpell
    TotemTimers.SetExcludedIcon(slot.excluded, timer and not notTotem and TotemTimers.GetExcludedMultiSpell(timer))
    if timer and not notTotem then
        -- the timer button's icon shows the active totem while the timer runs, its texture is handed on without
        -- being read (it might be secret)
        local sourceIcon = timer.button.icons[1]
        activeIconSlots[sourceIcon] = slot
        if not activeIconHooked[sourceIcon] then
            hooksecurefunc(sourceIcon, "SetTexture", function(icon, ...)
                local activeSlot = activeIconSlots[icon]
                if activeSlot then
                    activeSlot.active.icon:SetTexture(...)
                    -- a new totem is set after the timer was started (StartTotem), compare it again
                    UpdateSlotDuration(activeSlot)
                end
            end)
            activeIconHooked[sourceIcon] = true
        end
        slot.active.icon:SetTexture(sourceIcon:GetTexture())
        -- range dots of the timer's totem, created once per slot (a slot always shows the timer of the same
        -- element, its button index is fixed by the element); shown with option GamePadTimers
        if not slot.rangeDotTimer and TotemTimers.AddRangeDots then
            slot.rangeDotTimer = timer
            -- the player's tint is cut out like the icon (shape of the slot when the dots are created)
            TotemTimers.AddRangeDots(timer, slot, slot.rangeDots, function() return GamePad.timersShown end,
                    { slot.round and "CircleMask" or "SquareMask", MASK_INSET })
        end
    end
    UpdateSlotDuration(slot)
    slot:Show()
    GamePad.UpdateSlotManaColor(slot)
end

-- the bar's focus background, a texture of the bar shown like the game does for the focused bar
local focusBackgroundBar
local function SetFocusBackground(bar)
    if focusBackgroundBar and focusBackgroundBar ~= bar and focusBackgroundBar.BackgroundFocus then
        focusBackgroundBar.BackgroundFocus:Hide()
    end
    focusBackgroundBar = bar
    if bar and bar.BackgroundFocus then
        bar.BackgroundFocus:SetShown(layerExpanded)
    end
end

function GamePad.UpdateBarIcons()
    for _, slot in pairs(barIcons) do
        slot.timer = nil
        slot.cooldownSpell = nil
        slot:Hide()
    end
    wipe(activeIconSlots)
    local bar = GamePad.nav and GamePad.nav:GetAttribute("enabled") and GetLayerKeyBar()
    -- in bar mode the game focuses the bar itself
    SetFocusBackground(not GamePad.barMode and bar or nil)
    if not bar then
        GamePad.UpdateActionButtons()
        return
    end
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and timer.button:IsShown() then
            local spell = timer.button:GetAttribute("*spell1")
            local texture = spell and spell ~= 0 and C_Spell.GetSpellTexture(spell)
            ShowSlot(bar, FaceButtonIndices[TimerKeys[timer.nr]], texture, timer, nil, nil, spell)
        end
    end

    -- d-pad: up casts the weapon tracker's enchant (with the remaining time of the main hand's enchant), right the
    -- selected multicast spell, down Totemic Recall, left Totemic Call
    local multiSpell = TotemTimers_MultiSpell
    local multiSpellID = multiSpell and multiSpell:GetAttribute("active") and multiSpell:GetAttribute("*spell1")
    local weapon = TotemTimers.WeaponTracker
    local weaponSpell = weapon and weapon.button:GetAttribute("spell1")
    ShowSlot(bar, OPEN_BUTTON_INDEX, weaponSpell and C_Spell.GetSpellTexture(weaponSpell), weapon, nil, true,
            weaponSpell)
    ShowSlot(bar, DPAD_RIGHT_INDEX, multiSpellID and C_Spell.GetSpellTexture(multiSpellID), nil, nil, nil,
            multiSpellID)
    ShowSlot(bar, DPAD_DOWN_INDEX,
            GetAvailableSpellName(SpellIDs.TotemicRecall) and C_Spell.GetSpellTexture(SpellIDs.TotemicRecall),
            nil, nil, nil, SpellIDs.TotemicRecall)
    ShowSlot(bar, DPAD_LEFT_INDEX,
            GetAvailableSpellName(SpellIDs.TotemicCall) and C_Spell.GetSpellTexture(SpellIDs.TotemicCall), nil,
            SpellIDs.TotemicCall)
    GamePad.UpdateWeaponSlotGlow()
    -- the buttons covered by the overlays changed
    GamePad.UpdateActionButtons()
end

-- the layer key went down or up (called by the layer button's click snippet, not protected)
local function SetLayerExpanded(self, expanded)
    expanded = expanded and true or false
    if layerExpanded == expanded then return end
    layerExpanded = expanded
    local bar = GamePad.nav and GamePad.nav:GetAttribute("enabled") and GetLayerKeyBar()
    SetFocusBackground(bar or nil)
    if not bar then return end
    for _, slot in pairs(barIcons) do
        if slot:IsShown() then UpdateSlotLayout(slot, bar) end
    end
end
GamePad.SetLayerExpanded = SetLayerExpanded

function GamePad.UpdateBarDurations()
    for _, slot in pairs(barIcons) do
        if slot.timer then UpdateSlotDuration(slot) end
    end
end

-- mana tint of the slots every 0.2 s (in a do block: the main chunk is at Lua's limit of 200 locals)
do
    local SLOT_MANA_CHECK_INTERVAL = 0.2
    local nextSlotManaCheck = 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
        nextSlotManaCheck = nextSlotManaCheck - elapsed
        if nextSlotManaCheck > 0 then return end
        nextSlotManaCheck = SLOT_MANA_CHECK_INTERVAL
        for _, slot in pairs(barIcons) do
            GamePad.UpdateSlotManaColor(slot)
        end
    end)
end

-- cooldowns of the slots of spells with a cooldown (Totemic Call)
local function UpdateSlotCooldowns()
    for _, slot in pairs(barIcons) do
        if (slot.cooldownSpell or slot.spell) and slot:IsShown() then UpdateSlotDuration(slot) end
    end
end

-- option PlayerRangeStyle changed
function GamePad.UpdateRangeDotLayout()
    for _, slot in pairs(barIcons) do
        UpdateRangeDotLayout(slot)
    end
end



-- the selected totem of a timer changed (*spell1), a totem was dropped or ended (timer 1 of the totem timer)
local hookedTimers = {}
local function HookTimers()
    local function TimerChanged(self, timer)
        if timer == 1 then GamePad.UpdateBarDurations() end
    end
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and not hookedTimers[timer] and timer.button.UpdateMiniIconAndProfile then
            hooksecurefunc(timer.button, "UpdateMiniIconAndProfile", GamePad.UpdateBarIcons)
            -- the element was excluded from / included in the active multicast spell
            hooksecurefunc(timer.button, "UpdateMultiSpellExcluded", GamePad.UpdateBarIcons)
            hooksecurefunc(timer, "Start", TimerChanged)
            hooksecurefunc(timer, "Stop", TimerChanged)
            hookedTimers[timer] = true
        end
    end
    -- the selected multicast spell changed, the multicast button was (de)activated
    local multiSpell = TotemTimers_MultiSpell
    if multiSpell and multiSpell.UpdateTexture and not hookedTimers[multiSpell] then
        hooksecurefunc(multiSpell, "UpdateTexture", GamePad.UpdateBarIcons)
        -- (de)activation changes the bar slot of the multicast spell (bar mode), out of combat
        hooksecurefunc(TotemTimers, "MultiSpellActivate", function() GamePad.Apply() end)
        hookedTimers[multiSpell] = true
    end
    -- the weapon tracker's enchant changed (SaveLastEnchant runs on each change of its spells)
    local weapon = TotemTimers.WeaponTracker
    if weapon and weapon.button.SaveLastEnchant and not hookedTimers[weapon] then
        hooksecurefunc(weapon.button, "SaveLastEnchant", GamePad.UpdateBarIcons)
        hookedTimers[weapon] = true
    end
end


-- shared with GamePad.lua, GamePadActionButtons.lua, GamePadBarMode.lua and GamePadLegend.lua
GamePad.barIcons = barIcons
GamePad.barModeSlots = barModeSlots
GamePad.CIRCLE_SWIPE = CIRCLE_SWIPE
GamePad.SQUARE_SWIPE = SQUARE_SWIPE
GamePad.MASK_INSET = MASK_INSET
GamePad.UpdateSlotCooldowns = UpdateSlotCooldowns
GamePad.HookTimers = HookTimers
