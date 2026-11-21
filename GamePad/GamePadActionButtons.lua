if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...
local GamePad = TotemTimers.GamePad

local barIcons = GamePad.barIcons
local CIRCLE_SWIPE = GamePad.CIRCLE_SWIPE
local SQUARE_SWIPE = GamePad.SQUARE_SWIPE
local MASK_INSET = GamePad.MASK_INSET
local SpellIDs = TotemTimers.SpellIDs

-- Overlays on the Gamepad UI action buttons, by the spell of the button's action (also of a macro showing a spell,
-- compared by name, so all ranks count). Buttons covered by an overlay of the totem bar (see above) are skipped.
-- The buttons' UpdateAction is hooked, so action changes and paging are followed.
-- - Lightning Shield and Water Shield: like the shield tracker with "charges only", an AuraDisplay (see
--   AuraDisplay.lua) laid over the button shows the charges while the shield is up. The game shows the aura, it's
--   never read in Lua.
-- - Weapon enchants (Rockbiter, Flametongue, Frostbrand, Windfury Weapon): the remaining time of the enchant on the
--   weapon (swipe and time), from the DurationObject of the weapon tracker (never read in Lua), on the button of that
--   enchant, and the glow of the weapon tracker in combat. Weapon.lua calls GamePad.UpdateActionButtons when an
--   enchant starts or ends and GamePad.SetWeaponGlow on its updates.
-- - Flame Shock, while the Flame Shock timer (CombatCDs.lua) is active: two AuraDisplays on the target show the
--   player's Flame Shock debuff, one its remaining time (swipe and time like the enchant buttons), the other a green
--   tint over the icon. CombatCDs.lua calls GamePad.UpdateActionButtons when the timer is (de)activated.
-- - Lightning Bolt (while the Maelstrom tracker is enabled, with option GamePadTimers or Maelstrom layout "gamepad"):
--   two AuraDisplays on the player's Maelstrom Weapon buff, one shows the stacks (like the shield
--   charges), the other the action bar's proc glow around the button from TotemTimers.MaelstromMaxStacks stacks on
--   (AuraDisplay glow mode, the game decides when to glow, the stacks are never read in Lua).
local SHIELD_SLOT = "shield"
local MAELSTROM_SLOT = "maelstrom"
-- Maelstrom displays by Gamepad UI button and shape (round: true/false), { count = AuraDisplay, glow = AuraDisplay }
local maelstromDisplays = {}
local FLAMESHOCK_SLOT = "flameshock"
local FLAMESHOCK_TINT = { 0, 1, 0, 0.3 } -- like the player's range tint (SetupTimers.lua)
local shieldDisplays = {} -- AuraDisplay by Gamepad UI button, kept once created (frames can't be destroyed)
-- Flame Shock displays by Gamepad UI button and shape (round: true/false), { time = AuraDisplay, tint = AuraDisplay }
local flameShockDisplays = {}
local weaponOverlays = {} -- time overlay by Gamepad UI button
local actionHooked = {}
local shieldAuraSpells

-- aura spell ids of all ranks of both shields
local function GetShieldAuraSpells()
    if not shieldAuraSpells then
        shieldAuraSpells = {}
        local auraSpells = TotemTimers.ShieldAuraSpells or {}
        for _, spell in ipairs({ SpellIDs.LightningShield, SpellIDs.WaterShield }) do
            for _, id in pairs(auraSpells[spell] or {}) do
                shieldAuraSpells[id] = true
            end
        end
    end
    return shieldAuraSpells
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- spell of an action slot, also of a macro showing a spell
local function GetActionSpell(action)
    if not action or IsSecret(action) or action == 0 then return end
    local actionType, id, subType = GetActionInfo(action)
    if IsSecret(actionType) or IsSecret(id) then return end
    if actionType == "spell" then return id end
    if actionType == "macro" and id then
        if subType == "spell" then return id end
        local spell = GetMacroSpell(id)
        if not IsSecret(spell) then return spell end
    end
end

-- the name is the name of one of the spells
local function IsSpellName(name, ...)
    local names = TotemTimers.SpellNames
    for i = 1, select("#", ...) do
        local spellID = select(i, ...)
        if spellID and name == names[spellID] then return true end
    end
    return false
end

-- frame level above the button's cooldown swipe
local function GetOverlayLevel(button)
    return (button.cooldown and button.cooldown:GetFrameLevel() or button:GetFrameLevel()) + 2
end

local function UpdateShieldButton(button, name)
    local show = name and IsSpellName(name, SpellIDs.LightningShield, SpellIDs.WaterShield) or false
    local display = shieldDisplays[button]
    if show and not display then
        display = TotemTimers.AuraDisplay:new(button, "player", { textAnchor = button, noIcon = true })
        if not display then return end
        display:SetTimeShown(false)
        display:AddSlot(SHIELD_SLOT, GetShieldAuraSpells(), math.max(GetOverlayLevel(button) - button:GetFrameLevel(), 2))
        shieldDisplays[button] = display
    end
    if display then
        display:SetSlotEnabled(SHIELD_SLOT, show)
    end
end

-- the glow's shape is fixed when the slot buttons are built, so each shape has its own displays (round: the own round
-- glow, see AuraDisplay.CreateRoundGlow)
local function CreateMaelstromDisplays(button, round)
    local spells = {}
    for _, id in pairs(TotemTimers.MaelstromAuraSpells or {}) do
        spells[id] = true
    end
    local level = math.max(GetOverlayLevel(button) - button:GetFrameLevel(), 2)
    local displays = {}
    displays.glow = TotemTimers.AuraDisplay:new(button, "player", {
        glow = { region = button, minApplications = TotemTimers.MaelstromMaxStacks or 5, round = round },
    })
    if displays.glow then
        displays.glow:AddSlot(MAELSTROM_SLOT, spells, level)
    end
    displays.count = TotemTimers.AuraDisplay:new(button, "player", { textAnchor = button, noIcon = true })
    if displays.count then
        displays.count:SetTimeShown(false)
        displays.count:AddSlot(MAELSTROM_SLOT, spells, level + 1)
    end
    return displays
end

local function UpdateMaelstromButton(button, name)
    -- while the Maelstrom tracker is enabled (CombatCDs.lua), with option GamePadTimers like the other overlays, with
    -- layout "gamepad" (the tracker only on these buttons) always
    local enabled = TotemTimers.IsMaelstromEnabled and TotemTimers.IsMaelstromEnabled()
    local shown = GamePad.actionOverlaysShown
        or (TotemTimers.GetMaelstromLayout and TotemTimers.GetMaelstromLayout() == "gamepad")
    local show = enabled and shown and name and IsSpellName(name, SpellIDs.LightningBolt) or false
    local round = not (button.SquareMask and button.SquareMask:IsShown())
    local byShape = maelstromDisplays[button]
    if show and not (byShape and byShape[round]) then
        byShape = byShape or {}
        byShape[round] = CreateMaelstromDisplays(button, round)
        maelstromDisplays[button] = byShape
    end
    if not byShape then return end
    for shape, displays in pairs(byShape) do
        local enabled = show and shape == round
        for _, display in pairs(displays) do
            display:SetSlotEnabled(MAELSTROM_SLOT, enabled)
        end
    end
end

local flameShockAuraSpells

-- aura spell ids of all ranks of Flame Shock
local function GetFlameShockAuraSpells()
    if not flameShockAuraSpells then
        flameShockAuraSpells = {}
        for _, id in pairs(TotemTimers.FlameShockAuraSpells or { SpellIDs.FlameShock }) do
            flameShockAuraSpells[id] = true
        end
    end
    return flameShockAuraSpells
end

-- swipe and tint are cut out like the button's icon; the shape is fixed when the slot buttons are built, so each
-- shape has its own displays
local function CreateFlameShockDisplays(button, round)
    local level = math.max(GetOverlayLevel(button) - button:GetFrameLevel(), 2)
    local spells = GetFlameShockAuraSpells()
    local displays = {}
    displays.tint = TotemTimers.AuraDisplay:new(button, "target", {
        dot = button, tint = true, maskAtlas = round and "CircleMask" or "SquareMask", maskInset = MASK_INSET,
    })
    if displays.tint then
        displays.tint:SetDotColor(unpack(FLAMESHOCK_TINT))
        displays.tint:AddSlot(FLAMESHOCK_SLOT, spells, level, "HARMFUL|PLAYER")
    end
    displays.time = TotemTimers.AuraDisplay:new(button, "target", {
        textAnchor = button, noIcon = true, swipeTexture = round and CIRCLE_SWIPE or SQUARE_SWIPE, swipeInset = MASK_INSET,
        forGamePad = true,
    })
    if displays.time then
        displays.time:AddSlot(FLAMESHOCK_SLOT, spells, level + 1, "HARMFUL|PLAYER")
    end
    return displays
end

local function UpdateFlameShockButton(button, name)
    -- while the Flame Shock timer is enabled (CombatCDs.lua), with option GamePadTimers like the other overlays, with
    -- option FlameShockDurationGamePadOnly (the timer only on these buttons) always
    local enabled = TotemTimers.IsFlameShockEnabled and TotemTimers.IsFlameShockEnabled()
    local shown = GamePad.actionOverlaysShown
        or (TotemTimers.IsFlameShockGamePadOnly and TotemTimers.IsFlameShockGamePadOnly())
    local show = enabled and shown and name and IsSpellName(name, SpellIDs.FlameShock) or false
    local round = not (button.SquareMask and button.SquareMask:IsShown())
    local byShape = flameShockDisplays[button]
    if show and not (byShape and byShape[round]) then
        byShape = byShape or {}
        byShape[round] = CreateFlameShockDisplays(button, round)
        flameShockDisplays[button] = byShape
    end
    if not byShape then return end
    for shape, displays in pairs(byShape) do
        local enabled = show and shape == round
        for _, display in pairs(displays) do
            display:SetSlotEnabled(FLAMESHOCK_SLOT, enabled)
        end
    end
end

-- overlay of a weapon enchant button: the cooldown swipe and the time of the enchant, like the remaining time on
-- the totem bar overlays (without text bindings the countdown numbers of the cooldown), and the glow of the weapon
-- tracker.
-- Created for every enchant button out of combat (child of a protected button), so the glow is available in combat;
-- the end of combat updates the buttons again.
local function GetWeaponOverlay(button)
    local overlay = weaponOverlays[button]
    if overlay or InCombatLockdown() then return overlay end
    overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(GetOverlayLevel(button))
    overlay:EnableMouse(false)

    -- swipe like on the weapon tracker, inset like the icons of the totem bar overlays (the button's mask)
    overlay.cooldown = CreateFrame("Cooldown", nil, overlay, "CooldownFrameTemplate")
    overlay.cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", MASK_INSET, -MASK_INSET)
    overlay.cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -MASK_INSET, MASK_INSET)
    overlay.cooldown:SetDrawEdge(false)
    overlay.cooldown:SetDrawBling(false)
    overlay.cooldown.noCooldownCount = true

    if XiTimers.CanBindDurationText then
        overlay.cooldown:SetHideCountdownNumbers(true)
        -- the time above the swipe
        local texts = CreateFrame("Frame", nil, overlay)
        texts:SetAllPoints(button)
        texts:SetFrameLevel(overlay.cooldown:GetFrameLevel() + 1)
        overlay.time = texts:CreateFontString(nil, "OVERLAY")
        overlay.time:SetFontObject(TotemTimersButtonTimeFont)
        overlay.time:SetPoint("CENTER", button, "CENTER")
        overlay.binding = XiTimers.CreateDurationTextBinding(true)
        overlay.binding:SetFontString(overlay.time)
    else
        overlay.cooldown:SetHideCountdownNumbers(false)
    end
    -- the glow is shown on a frame of its own over the button, the game's own spell alerts of the button aren't touched
    overlay.glow = CreateFrame("Frame", nil, overlay)
    overlay.glow:SetAllPoints(button)
    overlay:Hide()
    weaponOverlays[button] = overlay
    return overlay
end

-- frame: the glow frame over a Gamepad UI button or bar slot; round: the button is round (own round glow, see
-- AuraDisplay.CreateRoundGlow, created on first use), otherwise the action bar's square spell alert
local function SetGlow(frame, shown, round)
    if shown and round and not frame.roundGlow and TotemTimers.AuraDisplay then
        frame.roundGlow = TotemTimers.AuraDisplay.CreateRoundGlow(frame)
    end
    -- the shape can change while glowing: the other glow off
    local roundShown = shown and round and frame.roundGlow ~= nil
    if frame.roundGlow then frame.roundGlow:SetShown(roundShown) end
    shown = shown and not roundShown
    if ActionButtonSpellAlertManager then
        if shown then
            ActionButtonSpellAlertManager:ShowAlert(frame)
        elseif ActionButtonSpellAlertManager:HasAlert(frame) then
            ActionButtonSpellAlertManager:HideAlert(frame)
        end
    elseif ActionButton_ShowOverlayGlow then
        if shown then ActionButton_ShowOverlayGlow(frame) else ActionButton_HideOverlayGlow(frame) end
    end
end

-- glow of the weapon tracker (see TotemTimers.WeaponUpdate): all enchant buttons glow while an enchant is missing,
-- the buttons of enchants about to expire glow (weaponGlowNames, by enchant name)
local NO_GLOW_NAMES = {}
local weaponGlowAll = false
local weaponGlowNames = NO_GLOW_NAMES

local function UpdateWeaponGlow(overlay)
    local glow = overlay.enchantName and (weaponGlowAll or weaponGlowNames[overlay.enchantName]) and true or false
    if glow ~= overlay.glowing or overlay.round ~= overlay.glowRound then
        overlay.glowing = glow
        overlay.glowRound = overlay.round
        SetGlow(overlay.glow, glow, overlay.round)
    end
end

-- the bar slot of the weapon tracker (d-pad up in bar mode) glows like the weapon tracker: while an enchant is
-- missing or about to expire (with option GamePadTimers); the game's button below it is covered, so its enchant
-- overlay isn't used
function GamePad.UpdateWeaponSlotGlow()
    local weapon = TotemTimers.WeaponTracker
    local glow = GamePad.timersShown and (weaponGlowAll or next(weaponGlowNames) ~= nil) or false
    for _, slot in pairs(barIcons) do
        local shown = glow and weapon ~= nil and slot.timer == weapon
        if shown ~= slot.glowing or slot.round ~= slot.glowRound then
            slot.glowing = shown
            slot.glowRound = slot.round
            SetGlow(slot.glow, shown, slot.round)
        end
    end
end

-- called by the weapon tracker on every update, names: set of enchant names, kept by the caller
function GamePad.SetWeaponGlow(all, names)
    weaponGlowAll = all and true or false
    weaponGlowNames = names or NO_GLOW_NAMES
    for _, overlay in pairs(weaponOverlays) do
        UpdateWeaponGlow(overlay)
    end
    GamePad.UpdateWeaponSlotGlow()
end

-- Glow of a cooldown reset (CombatCDs.lua RESET_GLOW, e.g. Stormstrike): the buttons of the spells whose combat
-- cooldown button glows after an early end of the cooldown glow too (with option GamePadTimers). The glow is shown on
-- a frame of its own over the button, created out of combat (child of a protected button) for every button of such
-- a spell, so it is available in combat.
local RESET_GLOW_SPELLS = { SpellIDs.StormStrike }
local resetGlowFrames = {} -- glow frame by Gamepad UI button

local function UpdateResetGlow(button)
    local frame = resetGlowFrames[button]
    if not frame then return end
    local names = TotemTimers.GetResetGlowNames and TotemTimers.GetResetGlowNames()
    local glow = frame.spellName and names and names[frame.spellName] and true or false
    local round = not (button.SquareMask and button.SquareMask:IsShown())
    if glow ~= frame.glowing or round ~= frame.glowRound then
        frame.glowing = glow
        frame.glowRound = round
        SetGlow(frame, glow, round)
    end
end

local function UpdateResetGlowButton(button, name)
    local isResetSpell = name and IsSpellName(name, unpack(RESET_GLOW_SPELLS)) or false
    local frame = resetGlowFrames[button]
    if isResetSpell and not frame and not InCombatLockdown() then
        frame = CreateFrame("Frame", nil, button)
        frame:SetAllPoints(button)
        frame:SetFrameLevel(GetOverlayLevel(button) + 1)
        frame:EnableMouse(false)
        resetGlowFrames[button] = frame
    end
    if not frame then return end
    frame.spellName = isResetSpell and name or nil
    UpdateResetGlow(button)
end

-- called by CombatCDs.lua when a reset glow starts or ends
function GamePad.UpdateResetGlows()
    for button in pairs(resetGlowFrames) do
        UpdateResetGlow(button)
    end
end

-- DurationObject of the weapon tracker's timer of the enchant, nil if that enchant isn't on a weapon
local function GetWeaponEnchantDuration(name)
    local weapon = TotemTimers.WeaponTracker
    if not weapon then return end
    for hand = 1, weapon.numtimers or 1 do
        local durObj = weapon.timers[hand]
        if durObj and weapon["enchant" .. hand] == name then
            return durObj
        end
    end
end

local function UpdateWeaponButton(button, name)
    local isEnchant = name and IsSpellName(name, SpellIDs.RockbiterWeapon, SpellIDs.FlametongueWeapon,
            SpellIDs.FrostbrandWeapon, SpellIDs.WindfuryWeapon)
    local overlay = isEnchant and GetWeaponOverlay(button) or weaponOverlays[button]
    if not overlay then return end
    -- round or square swipe, the gamepad buttons switch between their masks
    local round = not (button.SquareMask and button.SquareMask:IsShown())
    if overlay.round ~= round then
        overlay.round = round
        overlay.cooldown:SetSwipeTexture(round and CIRCLE_SWIPE or SQUARE_SWIPE)
        overlay.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    end
    local durObj = isEnchant and GetWeaponEnchantDuration(name)
    if durObj then
        overlay.cooldown:SetCooldownFromDurationObject(durObj)
        if overlay.binding then
            overlay.binding:SetDuration(durObj)
            overlay.binding:SetEnabled(true)
        end
    else
        overlay.cooldown:Clear()
        if overlay.binding then
            overlay.binding:SetEnabled(false)
            overlay.time:SetText("")
        end
    end
    overlay.enchantName = isEnchant and name or nil
    overlay:SetShown(isEnchant and true or false)
    UpdateWeaponGlow(overlay)
end

local function UpdateActionButton(button)
    local covered = barIcons[button] and barIcons[button]:IsShown()
    local spell = GamePad.actionButtonsActive and not covered and GetActionSpell(button.action)
    local name = spell and C_Spell.GetSpellName(spell)
    if IsSecret(name) then name = nil end
    -- the timer overlays follow option GamePadTimers, Flame Shock and Maelstrom decide themselves (their options to
    -- show them only on the Gamepad UI buttons ignore it)
    local timerName = GamePad.actionOverlaysShown and name or nil
    UpdateShieldButton(button, timerName)
    UpdateWeaponButton(button, timerName)
    UpdateResetGlowButton(button, timerName)
    UpdateFlameShockButton(button, name)
    UpdateMaelstromButton(button, name)
end

-- a visible Gamepad UI button (not covered by a bar slot overlay) whose action is the spell (name), for the stop
-- pulse of hidden timers (GamePadBarMode.lua)
function GamePad.FindActionButton(name)
    local pageUnit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
    if not (name and pageUnit and pageUnit.actionBars) then return end
    for _, bar in pairs(pageUnit.actionBars) do
        for _, button in ipairs(bar.actionButtons or {}) do
            if button:IsVisible() and button:GetEffectiveAlpha() > 0
                    and not (barIcons[button] and barIcons[button]:IsShown()) then
                local spell = GetActionSpell(button.action)
                local spellName = spell and C_Spell.GetSpellName(spell)
                if spellName and not IsSecret(spellName) and spellName == name then
                    return button
                end
            end
        end
    end
end

function GamePad.UpdateActionButtons()
    local pageUnit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
    if not (pageUnit and pageUnit.actionBars) then return end
    for _, bar in pairs(pageUnit.actionBars) do
        for _, button in ipairs(bar.actionButtons or {}) do
            if not actionHooked[button] and button.UpdateAction then
                hooksecurefunc(button, "UpdateAction", UpdateActionButton)
                actionHooked[button] = true
            end
            UpdateActionButton(button)
        end
    end
end
