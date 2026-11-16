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
local SHIELD_SLOT = "shield"
local shieldDisplays = {} -- AuraDisplay by Gamepad UI button, kept once created (frames can't be destroyed)
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
        overlay.binding = XiTimers.CreateDurationTextBinding()
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

local function SetGlow(frame, shown)
    if ActionButtonSpellAlertManager then
        if shown then
            ActionButtonSpellAlertManager:ShowAlert(frame)
        else
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
    if glow ~= overlay.glowing then
        overlay.glowing = glow
        SetGlow(overlay.glow, glow)
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
        if shown ~= slot.glowing then
            slot.glowing = shown
            SetGlow(slot.glow, shown)
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
    local spell = GamePad.actionOverlaysShown and not covered and GetActionSpell(button.action)
    local name = spell and C_Spell.GetSpellName(spell)
    if IsSecret(name) then name = nil end
    UpdateShieldButton(button, name)
    UpdateWeaponButton(button, name)
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
