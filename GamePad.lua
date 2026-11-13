if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...

-- GamePad support, active while the game's Gamepad UI is enabled (C_InputInterfaceStyle, WoW Forever).
--
-- Layer key (setting GamePadLayerKey, LT + RT by default) + d-pad up opens the multicast menu, or the earth totem
-- menu if the multicast button isn't available. The layer key is bound to a secure layer button, whose click
-- snippet binds d-pad up while the key is held. The game loses the layer key while gamepad support is active
-- (for LT: the Gamepad UI's LT action bar). In the Gamepad UI the triggers aren't modifiers, even if CVars like
-- GamePadEmulateShift name them ([mod:shift] stays false while LT is held), so the key can't be shared.
-- The Gamepad UI sets priority override bindings of its own (e.g. while a UI frame has gamepad focus); bindings set
-- later win, so the d-pad bindings are only set when the layer key goes down or a menu button is selected.
-- While the layer key is held, the face buttons click the totem timer buttons (cast the totem):
-- Cross/A earth, Square/X fire, Triangle/Y water, Circle/B air. D-pad right casts the selected multicast spell,
-- d-pad down Totemic Recall, d-pad left Totemic Call.
-- If the layer key is a trigger, the icons (and the totem durations) are laid over the slots of the Gamepad UI
-- action bar of that trigger (only visually, the action slots aren't changed).
--
-- While a menu is open (also one opened by the mouse), a secure navigation handler binds the d-pad, Cross/A (PAD1)
-- for a leftclick and Square/X (PAD3) for a rightclick on the selected menu button, and Circle/B (PAD2) to close.
-- Along the menu direction the d-pad selects the menu button, across it the d-pad switches to the next menu on
-- screen. Everything that changes in combat runs in the restricted environment of the navigation handler;
-- bindings of the layer key, frame references and wraps are only set out of combat.

local GamePad = {}
TotemTimers.GamePad = GamePad

local NAV_NAME = "TotemTimers_GamePadNav"
local LAYER_NAME = "TotemTimers_GamePadLayer"
local OPEN_KEY = "PADDUP"

-- face buttons of the layer, by totem element
local TimerKeys = {
    [EARTH_TOTEM_SLOT] = "PAD1", -- Cross/A
    [FIRE_TOTEM_SLOT] = "PAD3", -- Square/X
    [WATER_TOTEM_SLOT] = "PAD4", -- Triangle/Y
    [AIR_TOTEM_SLOT] = "PAD2", -- Circle/B
}

-- Gamepad UI action bar of a layer key (actionBars of GamepadMainActionBarFrame.PageUnit)
-- (LT + RT isn't a key, it's only available in bar mode: the game focuses the bottom bar while both are held)
local LayerKeyBars = {
    PADLTRIGGER = "leftBar",
    PADRTRIGGER = "rightBar",
    ["PADLTRIGGER+PADRTRIGGER"] = "bottomBar",
}
GamePad.BOTH_TRIGGERS = "PADLTRIGGER+PADRTRIGGER"

-- the layer key uses bar mode (LT, RT or LT + RT)
function GamePad.IsBarModeKey(key)
    return key ~= nil and LayerKeyBars[key] ~= nil
end

-- layer key in use: the profile setting, or a temporary override (the tutorial uses LT + RT), not saved
local layerKeyOverride
function GamePad.GetLayerKey()
    return layerKeyOverride or (TotemTimers.ActiveProfile and TotemTimers.ActiveProfile.GamePadLayerKey)
end

-- nil restores the profile setting; applied out of combat (GamePad.Apply defers it in combat)
function GamePad.SetLayerKeyOverride(key)
    if layerKeyOverride == key then return end
    layerKeyOverride = key
    GamePad.Apply()
end

-- button index of a face button on a Gamepad UI action bar (GAMEPAD_ACTION_BAR_BUTTON_INDICES)
local FaceButtonIndices = {
    PAD3 = 5, -- left
    PAD4 = 6, -- top
    PAD2 = 7, -- right
    PAD1 = 8, -- bottom
}
GamePad.FaceButtonIndices = FaceButtonIndices

-- slots of the d-pad on a Gamepad UI action bar
local DPAD_LEFT_INDEX = 1
local OPEN_BUTTON_INDEX = 2 -- d-pad up (OPEN_KEY)
local DPAD_RIGHT_INDEX = 3
local DPAD_DOWN_INDEX = 4
GamePad.OPEN_BUTTON_INDEX = OPEN_BUTTON_INDEX
GamePad.DPAD_RIGHT_INDEX = DPAD_RIGHT_INDEX

local nav, layer, keyOwner
local wrapped = {}
local pending = false

local function IsGamepadUI()
    if not (C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle and Enum.InputDeviceInterfaceType) then
        return false
    end
    local style = C_InputInterfaceStyle.GetCurrentStyle()
    if issecretvalue and issecretvalue(style) then return false end
    return style == Enum.InputDeviceInterfaceType.Gamepad
end
GamePad.IsGamepadUI = IsGamepadUI

local SpellIDs = TotemTimers.SpellIDs
local AvailableSpells = TotemTimers.AvailableSpells

-- name of a spell the player knows (for spell bindings), nil otherwise
local function GetAvailableSpellName(spellID)
    if spellID and AvailableSpells[spellID] then
        return C_Spell.GetSpellName(spellID)
    end
end


-- restricted snippets of the navigation handler, the environment variables cur (open menu), idx (selected button)
-- and switching (menus are shown/hidden by the handler itself) are shared by all of them and the wraps

-- Count(m): number of usable buttons of menu m, active buttons are always the first ones
local COUNT = [[
    local m = ...
    local n = 0
    for i = 1, self:GetAttribute("nbuttons" .. m) or 0 do
        local b = self:GetFrameRef("m" .. m .. "b" .. i)
        if not b or b:GetAttribute("inactive")
                or not (b:GetAttribute("*spell1") or b:GetAttribute("doublespell1")) then
            break
        end
        n = i
    end
    return n
]]

-- Usable(m): menu m can be opened
local USABLE = [[
    local m = ...
    local parent = self:GetFrameRef("menu" .. m)
    if not parent or not parent:IsVisible() then return false end
    return self:RunAttribute("Count", m) > 0
]]

-- ShowMenu(m, show): shows or hides menu m, menus that are always visible are left alone
local SHOW_MENU = [[
    local m, show = ...
    local first = self:GetFrameRef("m" .. m .. "b1")
    if not first or first:GetAttribute("alwaysshow") then return end
    switching = true
    self:GetFrameRef("menu" .. m):ChildUpdate("show", show)
    switching = false
]]

-- Select(m, i, byPad): opens menu m, selects its button i and binds the pad keys,
-- byPad: selected by the gamepad, shows the tooltip of the button (not for menus opened by the mouse)
local SELECT = [[
    local m, i, byPad = ...
    local n = self:RunAttribute("Count", m)
    if n == 0 then return end
    if i > n then i = n elseif i < 1 then i = 1 end
    if cur ~= m then
        if cur then self:RunAttribute("ShowMenu", cur, false) end
        self:RunAttribute("ShowMenu", m, true)
    end
    cur, idx = m, i
    local b = self:GetFrameRef("m" .. m .. "b" .. i)
    self:ClearBindings()
    self:SetBindingClick(true, "PADDUP", self, "up")
    self:SetBindingClick(true, "PADDDOWN", self, "down")
    self:SetBindingClick(true, "PADDLEFT", self, "left")
    self:SetBindingClick(true, "PADDRIGHT", self, "right")
    self:SetBindingClick(true, "PAD2", self, "close")
    self:SetBindingClick(true, "PAD1", b, "LeftButton")
    self:SetBindingClick(true, "PAD3", b, "RightButton")
    self:CallMethod("SetHighlight", b:GetName(), byPad)
]]

-- Stop(hide): ends the navigation, hide: also close the open menu
local STOP = [[
    local hide = ...
    self:ClearBindings()
    if cur and hide then self:RunAttribute("ShowMenu", cur, false) end
    cur = nil
    self:CallMethod("SetHighlight", nil)
]]

-- Neighbor(currentMenu, vertical, forward): next usable menu on screen. Vertical menus are ordered left to right
-- (then top to bottom), horizontal menus top to bottom (then left to right), wrapping around at the end.
-- Each menu gets a sort position from the center of its parent button: a primary value (x for vertical menus,
-- -y for horizontal ones, so that the values grow in the order above) and a secondary value for menus at the same
-- primary position. Positions within 1 pixel count as the same. Going backward the values are negated, so the same
-- search for the next bigger position works in both directions.
local NEIGHBOR = [[
    local currentMenu, vertical, forward = ...
    local left, bottom, width, height = self:GetFrameRef("menupos" .. currentMenu):GetRect()
    if not left then return end

    local currentPrimary, currentSecondary
    if vertical then
        currentPrimary, currentSecondary = left + width / 2, -(bottom + height / 2)
    else
        currentPrimary, currentSecondary = -(bottom + height / 2), left + width / 2
    end
    if not forward then currentPrimary, currentSecondary = -currentPrimary, -currentSecondary end

    -- nextMenu: the menu with the smallest position after the current one,
    -- firstMenu: the menu with the smallest position overall (wrapping around if there is no next one)
    local nextMenu, nextPrimary, nextSecondary
    local firstMenu, firstPrimary, firstSecondary
    for menu = 1, self:GetAttribute("nmenus") or 0 do
        if menu ~= currentMenu and self:RunAttribute("Usable", menu) then
            left, bottom, width, height = self:GetFrameRef("menupos" .. menu):GetRect()
            if left then
                local primary, secondary
                if vertical then
                    primary, secondary = left + width / 2, -(bottom + height / 2)
                else
                    primary, secondary = -(bottom + height / 2), left + width / 2
                end
                if not forward then primary, secondary = -primary, -secondary end

                local afterCurrent = primary > currentPrimary + 1
                        or (abs(primary - currentPrimary) <= 1 and secondary > currentSecondary)
                local beforeNext = not nextMenu or primary < nextPrimary - 1
                        or (abs(primary - nextPrimary) <= 1 and secondary < nextSecondary)
                if afterCurrent and beforeNext then
                    nextMenu, nextPrimary, nextSecondary = menu, primary, secondary
                end

                local beforeFirst = not firstMenu or primary < firstPrimary - 1
                        or (abs(primary - firstPrimary) <= 1 and secondary < firstSecondary)
                if beforeFirst then
                    firstMenu, firstPrimary, firstSecondary = menu, primary, secondary
                end
            end
        end
    end
    return nextMenu or firstMenu
]]

-- clicks of the bindings: "open" (layer key + d-pad up), d-pad directions and "close"
local NAV_ONCLICK = [[
    -- Square/X and Circle/B while a wheel stays open after the release (see HOLD_WRAP)
    if button == "wheelassign" then
        if down then self:RunAttribute("WheelAssign") end
        return
    end
    if button == "wheelclose" then
        if down then self:RunAttribute("CloseWheel") end
        return
    end
    if not self:GetAttribute("enabled") then return end
    -- the bar slot of d-pad up (bar mode) hands on its click as a LeftButton release, the bindings click on key down
    -- (their releases arrive, too, as the button is registered for LeftButton releases)
    if button == "LeftButton" then
        button = "open"
    elseif not down then
        return
    end
    if button == "open" then
        if cur then
            self:RunAttribute("Stop", true)
            return
        end
        local m = self:GetAttribute("multimenu")
        if not (m and self:RunAttribute("Usable", m)) then
            m = self:GetAttribute("earthmenu")
        end
        if m and self:RunAttribute("Usable", m) then
            self:RunAttribute("Select", m, 1, true)
        end
        return
    end
    if not cur then return end
    if button == "close" then
        self:RunAttribute("Stop", true)
        return
    end
    local dir = self:GetFrameRef("menu" .. cur):GetAttribute("ttMenuDirection") or "up"
    local vertical = dir == "up" or dir == "down"
    if (vertical and (button == "up" or button == "down")) or (not vertical and (button == "left" or button == "right")) then
        local n = self:RunAttribute("Count", cur)
        if n == 0 then return end
        local step = (button == dir) and 1 or -1
        self:RunAttribute("Select", cur, (idx - 1 + step) % n + 1, true)
    else
        local m = self:RunAttribute("Neighbor", cur, vertical, button == "right" or button == "down")
        if m then self:RunAttribute("Select", m, idx, true) end
    end
]]

-- wraps of the menu buttons: a menu opened by other means (mouse) starts the navigation,
-- a menu closed by other means (click on a menu button, mouse leaving) ends it
local MENU_ONSHOW = [[
    if switching or not control:GetAttribute("enabled") or self:GetAttribute("alwaysshow") then return end
    local m = self:GetAttribute("ttGamePadMenu")
    if m and cur ~= m then control:RunAttribute("Select", m, 1) end
]]

local MENU_ONHIDE = [[
    if switching then return end
    local m = self:GetAttribute("ttGamePadMenu")
    if m and m == cur then control:RunAttribute("Stop", false) end
]]

-- the layer key, held down: d-pad up opens a menu, the face buttons (attributes key1..n) click the totem timer
-- buttons (frame refs timer1..n) that are shown, d-pad right clicks the multicast button (casts the selected
-- multicast spell), d-pad down and left cast Totemic Recall and Totemic Call (attributes recall, call).
-- The bindings are set when the key goes down, so they are newer than the Gamepad UI's own bindings of the keys.
local LAYER_ONCLICK = [[
    self:ClearBindings()
    if down then
        self:SetBindingClick(true, self:GetAttribute("openkey"), self:GetAttribute("nav"), "open")
        for i = 1, self:GetAttribute("ntimers") or 0 do
            local timer = self:GetFrameRef("timer" .. i)
            if timer and timer:IsShown() then
                self:SetBindingClick(true, self:GetAttribute("key" .. i), timer, "LeftButton")
            end
        end
        local multiSpell = self:GetFrameRef("multispell")
        if multiSpell and multiSpell:GetAttribute("active") then
            self:SetBindingClick(true, "PADDRIGHT", multiSpell, "LeftButton")
        end
        local recall = self:GetAttribute("recall")
        if recall then self:SetBindingSpell(true, "PADDDOWN", recall) end
        local call = self:GetAttribute("call")
        if call then self:SetBindingSpell(true, "PADDLEFT", call) end
    end
    self:CallMethod("SetLayerExpanded", down)
]]


local highlighted

-- highlight of the selected menu button, not protected
local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers", true)

-- label styles of the controllers (InputDeviceIconSetManager) and the suffixes of their binding strings
local LabelStyleSuffixes = {
    Letters = "_LTR",
    Shapes = "_SHP",
    Reverse = "_REV",
}

-- inline icon of a pad button in the style of the active controller (Blizzard's KEY_ABBR_ binding strings)
local function GetPadIconMarkup(key)
    local style = InputDeviceIconSetManager and InputDeviceIconSetManager.GetActiveInputDeviceIconSet
            and InputDeviceIconSetManager:GetActiveInputDeviceIconSet()
    local suffix = style and LabelStyleSuffixes[style]
    return (suffix and _G["KEY_ABBR_" .. key .. suffix]) or _G["KEY_ABBR_" .. key] or GetBindingText(key)
end
GamePad.GetPadIconMarkup = GetPadIconMarkup

-- left/rightclick in the tooltip lines are replaced by the icons of the pad buttons that click
local function ReplaceClickTexts()
    local replacements = {
        { L["Leftclick"], GetPadIconMarkup("PAD1") },
        { L["Rightclick"], GetPadIconMarkup("PAD3") },
    }
    for i = 1, GameTooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text then
            local replaced = text
            for _, replacement in ipairs(replacements) do
                local pattern = replacement[1]:gsub("(%W)", "%%%1")
                replaced = replaced:gsub(pattern, (replacement[2]:gsub("%%", "%%%%")))
            end
            if replaced ~= text then line:SetText(replaced) end
        end
    end
end

local tooltipButton

-- highlight of the selected menu button and (if selected by the gamepad) its tooltip, not protected
local function SetHighlight(self, name, showTooltip)
    if highlighted then highlighted:Hide() end
    highlighted = nil
    if tooltipButton then
        if GameTooltip:IsOwned(tooltipButton) then GameTooltip:Hide() end
        tooltipButton = nil
    end
    local button = name and _G[name]
    if not button then return end
    if not button.ttGamePadHighlight then
        local texture = button:CreateTexture(nil, "OVERLAY", nil, 7)
        texture:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        texture:SetBlendMode("ADD")
        texture:SetAllPoints(button)
        button.ttGamePadHighlight = texture
    end
    button.ttGamePadHighlight:Show()
    highlighted = button.ttGamePadHighlight

    if showTooltip and button.tooltip and button:GetAttribute("tooltip") then
        button.tooltip:Show()
        ReplaceClickTexts()
        GameTooltip:Show() -- resizes to the changed lines
        tooltipButton = button
    end
end

local function Build()
    if nav then return true end
    if InCombatLockdown() then return false end

    keyOwner = CreateFrame("Frame", nil, UIParent)

    nav = CreateFrame("Button", NAV_NAME, UIParent, "SecureHandlerClickTemplate")
    nav:Hide() -- a hidden button still receives the clicks of its bindings
    -- bindings click on key down; the click handed on by a bar slot (bar mode) is a LeftButton release
    nav:RegisterForClicks("AnyDown", "LeftButtonUp")
    nav:SetAttribute("Count", COUNT)
    nav:SetAttribute("Usable", USABLE)
    nav:SetAttribute("ShowMenu", SHOW_MENU)
    nav:SetAttribute("Select", SELECT)
    nav:SetAttribute("Stop", STOP)
    nav:SetAttribute("Neighbor", NEIGHBOR)
    nav:SetAttribute("_onclick", NAV_ONCLICK)
    nav.SetHighlight = SetHighlight

    layer = CreateFrame("Button", LAYER_NAME, UIParent, "SecureHandlerClickTemplate")
    layer:Hide()
    layer:RegisterForClicks("AnyDown", "AnyUp") -- the binding sends the press and the release
    layer:SetAttribute("nav", NAV_NAME)
    layer:SetAttribute("openkey", OPEN_KEY)
    layer:SetAttribute("_onclick", LAYER_ONCLICK)
    layer.SetLayerExpanded = function(self, down) GamePad.SetLayerExpanded(self, down) end
    return true
end

-- menus (parent button and its action bar): multicast button first (if there is one), then the totem timers
-- menu index (nav frame refs "menu<m>") by parent button
local menuIndices = {}
-- the menu buttons by menu index, for the totem wheel
local menuButtons = {}
local menuParents = {}

-- the weapon tracker's button (bar mode: d-pad up casts its enchant, holding it opens the wheel of its menu)
local function GetWeaponButton()
    local weapon = TotemTimers.WeaponTracker
    return weapon and weapon.button
end

-- attribute with the spell a source button casts: the weapon tracker uses spell1 (leftclick, main hand),
-- the totem timers and the multicast button *spell1
local function GetSpellAttribute(source)
    return source == GetWeaponButton() and "spell1" or "*spell1"
end

local function UpdateMenus()
    local menus = {}
    local multiMenu, earthMenu
    if TotemTimers_MultiSpell and TotemTimers_MultiSpell.actionBar then
        table.insert(menus, { parent = TotemTimers_MultiSpell, bar = TotemTimers_MultiSpell.actionBar })
        multiMenu = #menus
    end
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and timer.actionBar then
            table.insert(menus, { parent = timer.button, bar = timer.actionBar })
            if timer.nr == EARTH_TOTEM_SLOT then earthMenu = #menus end
        end
    end
    local weapon = TotemTimers.WeaponTracker
    if weapon and weapon.actionBar then
        table.insert(menus, { parent = weapon.button, bar = weapon.actionBar })
    end

    for m, menu in ipairs(menus) do
        SecureHandlerSetFrameRef(nav, "menu" .. m, menu.parent)
        -- the frame where the menu is shown, for the order of the menus on screen (see SetMenusAtBar)
        SecureHandlerSetFrameRef(nav, "menupos" .. m, menu.parent)
        menuIndices[menu.parent] = m
        local buttons = menu.bar.buttons
        menuButtons[m] = buttons
        menuParents[m] = menu.parent
        nav:SetAttribute("nbuttons" .. m, #buttons)
        for i, button in ipairs(buttons) do
            SecureHandlerSetFrameRef(nav, "m" .. m .. "b" .. i, button)
            button:SetAttribute("ttGamePadMenu", m)
            if not wrapped[button] then
                SecureHandlerWrapScript(button, "OnShow", nav, MENU_ONSHOW)
                SecureHandlerWrapScript(button, "OnHide", nav, MENU_ONHIDE)
                wrapped[button] = true
            end
        end
    end
    nav:SetAttribute("nmenus", #menus)
    nav:SetAttribute("multimenu", multiMenu)
    nav:SetAttribute("earthmenu", earthMenu)
end

local eventFrame = CreateFrame("Frame")

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
local showActiveTotems = false
-- option GamePadTimers: timers on the Gamepad UI buttons (totem durations on the bar slots, shield charges, weapon
-- enchant times and glow); without it the slots only show the icons and GamePadHideTimers is ignored
local timersShown = true

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
local barMode = false
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
        local function UpdateActiveSize()
            local width, height = slot:GetSize()
            active:SetSize(width * ACTIVE_SIZE, height * ACTIVE_SIZE)
            active:ClearAllPoints()
            active:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", width * ACTIVE_OFFSET_X, -height * ACTIVE_OFFSET_Y)
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
        durObj = timersShown and slot.timer.timers[1]
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
    slot.active:SetShown(showActiveTotems and slot.timer and not slot.notTotem and durObj
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

-- shows a slot with the texture, timer: totem timer whose duration is shown, cooldownSpell: spell whose cooldown
-- is shown (slots without timer), notTotem: the timer isn't a totem timer (weapon tracker: its first timer is shown,
-- no active totem icon, no range dots), spell: the slot's spell, whose global cooldown is shown without a duration
local function ShowSlot(bar, index, texture, timer, cooldownSpell, notTotem, spell)
    if barMode and not barModeSlots[index] then return end
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
            TotemTimers.AddRangeDots(timer, slot, slot.rangeDots, function() return timersShown end,
                    { slot.round and "CircleMask" or "SquareMask", MASK_INSET })
        end
    end
    UpdateSlotDuration(slot)
    slot:Show()
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
    local bar = nav and nav:GetAttribute("enabled") and GetLayerKeyBar()
    -- in bar mode the game focuses the bar itself
    SetFocusBackground(not barMode and bar or nil)
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
    local bar = nav and nav:GetAttribute("enabled") and GetLayerKeyBar()
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
local actionOverlaysShown = false
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
    local glow = timersShown and (weaponGlowAll or next(weaponGlowNames) ~= nil) or false
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
    local spell = actionOverlaysShown and not covered and GetActionSpell(button.action)
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

-- learned spells (Totemic Recall, Totemic Call, multicast spells), runs out of combat
table.insert(TotemTimers.SpellUpdaters, function() GamePad.Apply() end)

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

-- Bar mode: the totem slots cast on the release of the key (attribute useOnKeyDown false, the Gamepad UI sets it to
-- true on its slots), the multicast slot (d-pad right) as well. Layer key + holding a totem slot opens a totem wheel
-- of its timer's menu, holding the multicast slot a wheel of the multicast menu (attribute
-- ttHoldMenu: menu index of the navigation, see UpdateMenus) while the key is still held. Either stick selects a
-- totem (both pushed: the one pushed further), releasing the key casts the totem the stick points at; with the sticks
-- in the center nothing is cast (the wheel closes). Like Blizzard's wheels, a stick only selects after it was in the
-- center while the wheel is open (wheelArmed1/2 per stick), so a stick still pushed from moving doesn't pick a totem.
-- Secure code has no clock, so the hold is measured in ticks of the secure state driver: a hidden secure frame with
-- a unit watch on "player" is shown by SecureStateDriverManager on every update, its OnShow wrap counts the tick and
-- hides it again. The update interval of the state driver (0.2 s by default) is set to HOLD_UPDATE_TIME while bar
-- mode is active (its attribute "updatetime", set by a secure snippet; this applies to all state drivers) and set
-- back to 0.2 s with the slots. The unit watch is registered when the key goes down (first tick right away) and
-- removed on the release; HOLD_TICKS ticks open the wheel (0.2 - 0.3 s: the first tick comes right away, the next one within 0.1 s), the following ticks read the stick (every
-- 0.1 s) and arm each stick once it is in the center. The wraps run in the navigation handler's environment
-- (holdTicks, holdSlot, wheelOpen, wheelArmed1/2).
-- The stick directions aren't keys (no PADRSTICK* key events), so the cast comes from the key release: the wraps
-- read the sticks with GetGamePadState() (nav attributes wheelstickindex1/2: 1-based indices of the sticks "Movement"
-- and "Camera", C_GamePad.StickIndexToConfigName is 0-based) and the release computes the wheel segment like the display
-- (ShowWheel): one segment per totem (n, at most 8), segment i is centered at the angle (i - 1) * 360 / n, clockwise
-- from the top; it casts the *spell1 of menu button i (snippet WheelSelection). Totem wheels (slot attribute
-- ttTotemSlot: the totem slot of the timer's element) have one more segment at the top that destroys the totem of the
-- element (secure action "destroytotem", like a rightclick on the timer button); the totems follow it.
-- Releasing the key with the sticks in the center leaves the wheel open (wheelSticky): the ticker frame then binds
-- Cross/A to the hidden secure button TotemTimers_GamePadWheelCast (casts the selected totem and closes the wheel,
-- nothing with the sticks in the center, WHEEL_CAST_WRAP), Square/X to the navigation button ("wheelassign", snippet
-- WheelAssign: the selected totem becomes the timer button's totem, the wheel stays open) and Circle/B to it
-- ("wheelclose", snippet CloseWheel). These keys are only bound after the release: bound while the key is held, they
-- would take the release of a held face button. Pressing a wheel slot again closes a wheel left open first. The ticks
-- go on while the wheel stays open (arming the sticks).
local HOLD_TICKS = 4
local HOLD_UPDATE_TIME = 0.1
local DEFAULT_STATE_DRIVER_UPDATE_TIME = 0.2

-- ReadWheelSticks: reads both sticks (GetGamePadState inside a snippet), arms the sticks in the center and sets
-- wheelX/wheelY to the armed stick pushed furthest; returns whether an armed stick is pushed
local WHEEL_STICKS = [[
    local state = GetGamePadState()
    local sticks = state and state.sticks
    local best
    wheelX, wheelY = 0, 0
    for n = 1, 2 do
        local index = self:GetAttribute("wheelstickindex" .. n)
        local stick = sticks and index and sticks[index]
        local length = stick and (stick.x * stick.x + stick.y * stick.y) or 0
        if length < 0.25 then
            if n == 1 then wheelArmed1 = true else wheelArmed2 = true end
        elseif (n == 1 and wheelArmed1 or n == 2 and wheelArmed2) and (not best or length > best) then
            best = length
            wheelX, wheelY = stick.x, stick.y
        end
    end
    return best ~= nil
]]

-- WheelSelection(m, extra): the selected segment of the wheel of menu m with extra segments before the menu's (at
-- most 8) buttons (segment i shows menu button i - extra), and the number of the menu's buttons on the wheel; nil: no
-- armed stick is pushed
local WHEEL_SELECTION = [[
    local m, extra = ...
    local n = m and self:RunAttribute("Count", m) or 0
    if n == 0 or not self:RunAttribute("ReadWheelSticks") then return end
    if n > 8 then n = 8 end
    local total = n + (extra or 0)
    local segment = 2 * math.pi / total
    local angle = (math.atan2(wheelX, wheelY) + segment / 2) % (2 * math.pi)
    local i = math.floor(angle / segment) + 1
    if i > total then i = total end
    return i, n
]]

-- WheelAssign: the selected totem becomes the totem of the timer button of the open wheel
local WHEEL_ASSIGN = [[
    if not (wheelOpen and wheelSlot) then return end
    local m = wheelSlot:GetAttribute("ttHoldMenu")
    local i, n
    if m then i, n = self:RunAttribute("WheelSelection", m, wheelSlot:GetAttribute("ttTotemSlot") and 1 or 0) end
    local extra = wheelSlot:GetAttribute("ttTotemSlot") and 1 or 0
    -- the destroy segment (the first one) can't be assigned
    if not i or i <= extra then return end
    local b = self:GetFrameRef("m" .. m .. "b" .. (i - extra))
    local spell = b and b:GetAttribute("*spell1")
    local source = wheelSlot:GetFrameRef("ttGamePadSource")
    if spell and source then
        if source:GetAttribute("ttspellattr") == "spell1" then
            -- weapon tracker: the leftclick (main hand), like its menu without modifier
            source:SetAttribute("doublespell1", nil)
            source:SetAttribute("doublespell2", nil)
            source:SetAttribute("type1", "spell")
            source:SetAttribute("spell1", spell)
        else
            source:SetAttribute("*type1", "spell")
            source:SetAttribute("*spell1", spell)
        end
        self:CallMethod("WheelAssigned", i)
    end
]]

-- CloseWheel: closes the open wheel (also one left open after the release) and ends the ticks
local CLOSE_WHEEL = [[
    local ticker = self:GetFrameRef("holdticker")
    if ticker then
        UnregisterUnitWatch(ticker)
        ticker:Hide()
        ticker:ClearBindings()
    end
    if wheelSlot then wheelSlot:SetAttribute("ttWheelOpen", nil) end
    if wheelOpen then self:CallMethod("HideWheel") end
    holdSlot, wheelSlot = nil, nil
    wheelOpen, wheelSticky, wheelArmed1, wheelArmed2 = false, false, false, false
]]

-- Cross/A on a wheel left open: casts the selected totem (or destroys the element's totem) and closes the wheel,
-- with the sticks in the center nothing happens (pre-click wrap of TotemTimers_GamePadWheelCast)
local WHEEL_CAST_WRAP = [[
    if not (down and wheelOpen and wheelSticky and wheelSlot) then return false end
    local m = wheelSlot:GetAttribute("ttHoldMenu")
    local totemSlot = wheelSlot:GetAttribute("ttTotemSlot")
    local extra = totemSlot and 1 or 0
    local i = m and control:RunAttribute("WheelSelection", m, extra)
    if not i then return false end
    if totemSlot and i == 1 then
        self:SetAttribute("type", "destroytotem")
        self:SetAttribute("totem-slot", totemSlot)
    else
        local b = control:GetFrameRef("m" .. m .. "b" .. (i - extra))
        local spell = b and b:GetAttribute("*spell1")
        if not spell then return false end
        self:SetAttribute("type", "spell")
        self:SetAttribute("spell", spell)
    end
    control:RunAttribute("CloseWheel")
]]

local HOLD_TICK_ONSHOW = [[
    holdTicks = (holdTicks or 0) + 1
    self:Hide()
    if not (holdSlot or wheelOpen) then return end
    if not wheelOpen then
        if holdTicks < (control:GetAttribute("holdticks") or 4) then return end
        local m = holdSlot:GetAttribute("ttHoldMenu")
        if not (m and control:RunAttribute("Count", m) > 0) then
            UnregisterUnitWatch(self)
            return
        end
        wheelOpen = true
        wheelSlot = holdSlot
        control:RunAttribute("ReadWheelSticks")
        holdSlot:SetAttribute("ttWheelOpen", true)
        control:CallMethod("ShowWheel", m, wheelArmed1, wheelArmed2)
    elseif not (wheelArmed1 and wheelArmed2) then
        local armed1, armed2 = wheelArmed1, wheelArmed2
        control:RunAttribute("ReadWheelSticks")
        if armed1 ~= wheelArmed1 or armed2 ~= wheelArmed2 then
            control:CallMethod("ArmWheel", wheelArmed1, wheelArmed2)
        end
    end
]]

local HOLD_WRAP = [[
    if self:GetAttribute("ttGamePadOverride") ~= "spell" or not self:GetAttribute("ttHoldMenu") then return end
    local ticker = control:GetFrameRef("holdticker")
    if down then
        -- a wheel left open closes
        if wheelOpen then control:RunAttribute("CloseWheel") end
        holdTicks = 0
        holdSlot = self
        wheelOpen, wheelSticky, wheelArmed1, wheelArmed2 = false, false, false, false
        if ticker then RegisterUnitWatch(ticker) end
        return
    end
    -- a release without its press (the key went down before the wheel was left open): ignored while it is open
    local held = holdSlot == self
    if held then
        holdSlot = nil
    elseif wheelSticky then
        return false
    end
    -- the slot's own totem (the wheel may have changed the spell)
    local source = self:GetFrameRef("ttGamePadSource")
    local spell = source and source:GetAttribute(source:GetAttribute("ttspellattr") or "*spell1")
    if self:GetAttribute("ttWheelOpen") then
        -- the totem the stick points at
        local m = self:GetAttribute("ttHoldMenu")
        local totemSlot = self:GetAttribute("ttTotemSlot")
        local i, n = control:RunAttribute("WheelSelection", m, totemSlot and 1 or 0)
        if not i then
            -- the sticks in the center: the wheel stays open, Cross/A casts, Square/X assigns, Circle/B closes
            wheelSticky = true
            if ticker then
                ticker:SetBindingClick(true, "PAD1", control:GetFrameRef("wheelcast"), "LeftButton")
                ticker:SetBindingClick(true, "PAD3", control, "wheelassign")
                ticker:SetBindingClick(true, "PAD2", control, "wheelclose")
            end
            control:CallMethod("SetWheelSticky")
            return false
        end
        control:RunAttribute("CloseWheel")
        if totemSlot and i == 1 then
            -- the destroy segment (at the top): destroys the totem of the timer's element (like a rightclick on the
            -- timer)
            self:SetAttribute("type", "destroytotem")
            self:SetAttribute("totem-slot", totemSlot)
            return
        end
        local b = control:GetFrameRef("m" .. m .. "b" .. (i - (totemSlot and 1 or 0)))
        spell = b and b:GetAttribute("*spell1")
        if not spell then return false end
    elseif held then
        -- released before the wheel opened
        if ticker then
            UnregisterUnitWatch(ticker)
            ticker:Hide()
        end
        wheelOpen, wheelSticky, wheelArmed1, wheelArmed2 = false, false, false, false
    end
    -- a former destroy segment changed the type
    self:SetAttribute("type", "spell")
    self:SetAttribute("spell", spell)
]]

-- the totem wheel (display only, not protected), in the style of the Gamepad UI's game menu wheel (GamepadRadial),
-- with one segment per totem (at most 8): own textures (tools/wheel_textures.py) for the wheel without dividers, a
-- divider rotated onto each segment border and the highlight wedge of the segment count, rotated onto the selected
-- segment; each segment shows its icon with the name on the side toward the center (below the icon in the upper
-- half, above it in the lower half). The segment the armed stick pushed furthest points at is highlighted (sticks are
-- armed by the secure ticks, see HOLD_TICK_ONSHOW). While it is shown the frame takes both sticks (handled stick input
-- doesn't move the character or the camera); the other sticks (gyro) are passed on.
local WHEEL_TEXTURES = "Interface\\AddOns\\TotemTimers\\textures\\wheel_"
local WHEEL_SIZE = 400 -- displayed size of the wheel textures (UI units, see tools/wheel_textures.py)
local WHEEL_MAX_TOTEMS = 8 -- menu buttons on the wheel
local WHEEL_MAX_SEGMENTS = 9 -- totems and the destroy segment
local WHEEL_DESTROY_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local WHEEL_INNER_RIM = 66 -- segment area between the rims, like the textures
local WHEEL_OUTER_RIM = 188
local WHEEL_ICON_DISTANCE = 134 -- icon center, the label beside it stays between the rims in every direction
local WHEEL_LABEL_OFFSET = 34 -- vertical distance of the label center from the icon center, toward the center
local WHEEL_ICON_SHIFT = 12 -- icons of the upper half are moved up by this, icons of the lower half down
local WHEEL_DEADZONE_SQ = 0.25
local WHEEL_HELP_WIDTH = 100 -- help text in the inner circle (diameter 116)
local wheel

-- segment of the stick direction for n segments: segment 1 at the top, clockwise
local function WheelSegment(x, y, n)
    if n == 0 or x * x + y * y < WHEEL_DEADZONE_SQ then return end
    local segment = 2 * math.pi / n
    local angle = (math.atan2(x, y) + segment / 2) % (2 * math.pi)
    return math.min(math.floor(angle / segment) + 1, n)
end

-- labels: the totem of the timer button green with a check mark on its icon (also while selected), the selected
-- totem white
local function UpdateWheelLabelColors()
    for i, segment in ipairs(wheel.segments) do
        local color = (i == wheel.assigned and GREEN_FONT_COLOR) or (i == wheel.selected and HIGHLIGHT_FONT_COLOR)
                or NORMAL_FONT_COLOR
        segment.label:SetTextColor(color:GetRGB())
        segment.check:SetShown(i == wheel.assigned and i <= wheel.count)
    end
end

-- the wheel's sticks by the names of the stick events: 1 left, 2 right
local WheelStickNumbers = { Movement = 1, Camera = 2 }

local SetWheelSelection

-- selection by the armed stick pushed furthest
local function UpdateWheelStickSelection()
    local best, x, y
    for n = 1, 2 do
        local sx, sy = wheel.sticks[n][1], wheel.sticks[n][2]
        local length = sx * sx + sy * sy
        if wheel.armed[n] and length >= WHEEL_DEADZONE_SQ and (not best or length > best) then
            best, x, y = length, sx, sy
        end
    end
    SetWheelSelection(best and WheelSegment(x, y, wheel.count) or nil)
end

function SetWheelSelection(index)
    if wheel.selected == index then return end
    wheel.selected = index
    if index then
        -- the wedge texture is centered at the top, SetRotation turns counterclockwise
        wheel.highlight:SetRotation(-(index - 1) * 2 * math.pi / wheel.count)
        wheel.highlight:Show()
        if SOUNDKIT and SOUNDKIT.GAMEPAD_RADIAL_MENU_HIGHLIGHT then PlaySound(SOUNDKIT.GAMEPAD_RADIAL_MENU_HIGHLIGHT) end
    else
        wheel.highlight:Hide()
    end
    UpdateWheelLabelColors()
end

local function CreateWheel()
    wheel = CreateFrame("Frame", "TotemTimers_GamePadWheel", UIParent)
    wheel:SetFrameStrata("DIALOG")
    wheel:SetSize(WHEEL_SIZE, WHEEL_SIZE)
    wheel:SetPoint("CENTER")
    wheel:Hide()
    wheel.background = wheel:CreateTexture(nil, "BACKGROUND")
    wheel.background:SetTexture(WHEEL_TEXTURES .. "base")
    wheel.background:SetAllPoints()
    wheel.highlight = wheel:CreateTexture(nil, "BORDER")
    wheel.highlight:SetAllPoints()
    wheel.highlight:Hide()
    -- help in the inner circle, in the color of the help lines of the tooltips (ToolTips.lua)
    wheel.help = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wheel.help:SetPoint("CENTER")
    wheel.help:SetWidth(WHEEL_HELP_WIDTH)
    wheel.help:SetJustifyH("CENTER")
    wheel.help:SetTextColor(0, 0.9, 1)
    wheel.dividers = {}
    wheel.segments = {}
    for i = 1, WHEEL_MAX_SEGMENTS do
        local divider = wheel:CreateTexture(nil, "BORDER", nil, 1)
        divider:SetTexture(WHEEL_TEXTURES .. "divider")
        divider:SetSize(WHEEL_OUTER_RIM - WHEEL_INNER_RIM, WHEEL_OUTER_RIM - WHEEL_INNER_RIM)
        wheel.dividers[i] = divider
        local segment = {}
        segment.icon = wheel:CreateTexture(nil, "ARTWORK")
        segment.icon:SetSize(38, 38)
        segment.check = wheel:CreateTexture(nil, "OVERLAY")
        segment.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        segment.check:SetSize(24, 24)
        segment.check:SetPoint("CENTER", segment.icon, "TOPRIGHT", -2, -2)
        segment.check:Hide()
        segment.label = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        segment.label:SetSize(84, 30)
        segment.label:SetWordWrap(true)
        segment.label:SetJustifyH("CENTER")
        segment.label:SetJustifyV("MIDDLE")
        wheel.segments[i] = segment
    end
    wheel.count = 0
    wheel.armed = {}
    wheel.sticks = { {0, 0}, {0, 0} }
    wheel:SetScript("OnGamePadStick", function(self, stick, x, y)
        local n = WheelStickNumbers[stick]
        if not n then return true end
        self.sticks[n][1], self.sticks[n][2] = x, y
        UpdateWheelStickSelection()
        return false
    end)
end

-- the layout of n segments: dividers on the borders, icons and labels at the segment centers
local function LayoutWheel(n)
    if wheel.layout == n then return end
    wheel.layout = n
    wheel.highlight:SetTexture(WHEEL_TEXTURES .. "highlight" .. n)
    local middle = (WHEEL_INNER_RIM + WHEEL_OUTER_RIM) / 2
    for i = 1, WHEEL_MAX_SEGMENTS do
        -- clockwise angle from the top
        local center = (i - 1) * 2 * math.pi / n
        local border = center + math.pi / n
        local divider = wheel.dividers[i]
        divider:SetShown(n > 1 and i <= n)
        divider:ClearAllPoints()
        divider:SetPoint("CENTER", wheel, "CENTER", middle * math.sin(border), middle * math.cos(border))
        divider:SetRotation(-border)
        local segment = wheel.segments[i]
        -- upper half (segments exactly at the side count as upper half)
        local upper = math.cos(center) >= -0.01
        segment.icon:ClearAllPoints()
        segment.icon:SetPoint("CENTER", wheel, "CENTER", WHEEL_ICON_DISTANCE * math.sin(center),
                WHEEL_ICON_DISTANCE * math.cos(center) + (upper and WHEEL_ICON_SHIFT or -WHEEL_ICON_SHIFT))
        segment.label:ClearAllPoints()
        segment.label:SetPoint("CENTER", segment.icon, "CENTER", 0, upper and -WHEEL_LABEL_OFFSET or WHEEL_LABEL_OFFSET)
    end
end

local FillWheel

-- called by the hold tick (secure, CallMethod of the navigation button), also in combat
local function ShowWheel(_, m, armed1, armed2)
    if not wheel then CreateWheel() end
    -- help with the icon of the held face button (the key of the menu's timer)
    local key
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and timer.button == menuParents[m] then key = TimerKeys[timer.nr] end
    end
    -- the multicast and the weapon wheel hold spells, not totems
    local parent = menuParents[m]
    local multiSpell = parent and (parent == TotemTimers_MultiSpell or parent == GetWeaponButton())
    if parent and parent == TotemTimers_MultiSpell then
        key = "PADDRIGHT"
    elseif parent and parent == GetWeaponButton() then
        key = "PADDUP"
    end
    wheel.multiSpell = multiSpell
    wheel.help:SetText(format(L[multiSpell and "Spell Wheel Cast Help" or "Totem Wheel Cast Help"],
            key and GetPadIconMarkup(key) or ""))
    -- the usable buttons of the menu, like COUNT (at most 8, one per segment)
    local spells = {}
    for _, button in ipairs(menuButtons[m] or {}) do
        local spell = button:GetAttribute("*spell1")
        if #spells == WHEEL_MAX_TOTEMS or button:GetAttribute("inactive")
                or not (spell or button:GetAttribute("doublespell1")) then
            break
        end
        table.insert(spells, spell or false)
    end
    -- totem wheels: the first segment (at the top) destroys the element's totem (see HOLD_WRAP), the totems follow
    FillWheel(spells, not multiSpell and #spells > 0, parent and parent:GetAttribute(GetSpellAttribute(parent)))
    wheel.armed[1], wheel.armed[2] = armed1, armed2
    wheel.demo = nil
    -- the tutorial's wheel may have moved it
    wheel:ClearAllPoints()
    wheel:SetPoint("CENTER")
    wheel:EnableGamePadStick(true)
    wheel:Show()
end

-- segments of the wheel: the spells (false: a button without spell), destroy: a destroy segment first,
-- assigned: the spell of the timer button (marked)
function FillWheel(spells, destroy, assigned)
    local extra = destroy and 1 or 0
    wheel.count = #spells + extra
    LayoutWheel(math.max(wheel.count, 1))
    for i, segment in ipairs(wheel.segments) do
        local spell = spells[i - extra] or nil
        if destroy and i == 1 then
            segment.icon:SetTexture(WHEEL_DESTROY_ICON)
            segment.label:SetText(L["Destroy Totem"])
        else
            segment.icon:SetTexture(spell and (C_Spell.GetSpellTexture(spell)) or 134400)
            segment.label:SetText(spell and C_Spell.GetSpellName(spell) or "")
        end
        segment.icon:SetShown(i <= wheel.count)
        segment.label:SetShown(i <= wheel.count)
    end
    -- the totem of the timer button
    wheel.assigned = nil
    for i, spell in ipairs(spells) do
        if spell and assigned and C_Spell.GetSpellName(spell) == C_Spell.GetSpellName(assigned) then
            wheel.assigned = i + extra
        end
    end
    wheel.selected = false
    wheel.armed[1], wheel.armed[2] = false, false
    for n = 1, 2 do wheel.sticks[n][1], wheel.sticks[n][2] = 0, 0 end
    SetWheelSelection(nil)
end

-- the wheel of the tutorial: display only (no sticks, no secure state), spells: totems of the wheel with a destroy
-- segment (multicast spells without it if multiSpell), key: the pad button named in the help, beside: a frame (the
-- tutorial window), the wheel is moved right of it (at the height of the screen center, like the real wheel),
-- sticky: the help of a wheel left open after the release
local DEMO_WHEEL_GAP = 20
function GamePad.ShowDemoWheel(spells, key, beside, sticky, multiSpell)
    if not wheel then CreateWheel() end
    -- a real wheel is open
    if wheel:IsShown() and not wheel.demo then return end
    wheel:ClearAllPoints()
    local right = beside and beside:GetRight()
    if right then
        -- in UIParent units (the frames have the same scale)
        local x = right + DEMO_WHEEL_GAP + WHEEL_SIZE / 2 - UIParent:GetWidth() / 2
        wheel:SetPoint("CENTER", UIParent, "CENTER", math.max(x, 0), 0)
    else
        wheel:SetPoint("CENTER")
    end
    wheel:SetClampedToScreen(true)
    wheel.multiSpell = multiSpell
    if sticky then
        wheel.help:SetText(format(L[multiSpell and "Spell Wheel Sticky Help" or "Totem Wheel Sticky Help"],
                GetPadIconMarkup("PAD1"), GetPadIconMarkup("PAD3"), GetPadIconMarkup("PAD2")))
    else
        wheel.help:SetText(format(L[multiSpell and "Spell Wheel Cast Help" or "Totem Wheel Cast Help"],
                GetPadIconMarkup(key)))
    end
    FillWheel(spells, not multiSpell)
    wheel.demo = true
    wheel:Show()
end

function GamePad.HideDemoWheel()
    if wheel and wheel.demo then
        wheel.demo = nil
        wheel:Hide()
    end
end

-- the key was released with the sticks in the center, the wheel stays open (secure, HOLD_WRAP)
local function SetWheelSticky()
    if not (wheel and wheel:IsShown()) then return end
    wheel.help:SetText(format(L[wheel.multiSpell and "Spell Wheel Sticky Help" or "Totem Wheel Sticky Help"],
            GetPadIconMarkup("PAD1"), GetPadIconMarkup("PAD3"), GetPadIconMarkup("PAD2")))
end

-- Square/X assigned the totem of segment i to the timer button (WheelAssign)
local function WheelAssigned(_, i)
    if not wheel then return end
    wheel.assigned = i
    UpdateWheelLabelColors()
    if SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
end

-- a stick was in the center, it selects from now on (secure tick)
local function ArmWheel(_, armed1, armed2)
    if not wheel then return end
    wheel.armed[1], wheel.armed[2] = armed1, armed2
    UpdateWheelStickSelection()
end

-- 1-based index of a stick ("Movement", "Camera") in the sticks of GetGamePadState()
local function GetStickIndex(name)
    if not (C_GamePad and C_GamePad.StickIndexToConfigName) then return end
    local state = C_GamePad.GetDeviceMappedState and C_GamePad.GetDeviceMappedState()
    for i = 1, (state and state.stickCount or 8) do
        if C_GamePad.StickIndexToConfigName(i - 1) == name then return i end
    end
end

-- After the wheel closes with a stick still pushed, that stick only moves the character or the camera again after it
-- was in the center once (like the "wait for centering" of Blizzard's axis bindings): an invisible frame keeps taking
-- the sticks that aren't centered until they are. Stick events only come with changes, so a stick is only blocked if
-- it isn't centered when the wheel closes.
local stickBlocker

local function StickCentered(name)
    local state = C_GamePad.GetDeviceMappedState and C_GamePad.GetDeviceMappedState()
    local index = GetStickIndex(name)
    local stick = index and state and state.sticks and state.sticks[index]
    return not stick or (stick.x * stick.x + stick.y * stick.y) < 0.01
end

local function BlockSticksUntilCentered()
    if not stickBlocker then
        stickBlocker = CreateFrame("Frame", nil, UIParent)
        stickBlocker:SetSize(1, 1)
        stickBlocker:SetPoint("CENTER")
        stickBlocker.blocked = {}
        stickBlocker:SetScript("OnGamePadStick", function(self, stick, x, y)
            if not self.blocked[stick] then return true end
            if x * x + y * y < 0.01 then
                self.blocked[stick] = nil
                if not next(self.blocked) then self:EnableGamePadStick(false) end
            end
            return false
        end)
    end
    wipe(stickBlocker.blocked)
    for name in pairs(WheelStickNumbers) do
        if not StickCentered(name) then stickBlocker.blocked[name] = true end
    end
    stickBlocker:EnableGamePadStick(next(stickBlocker.blocked) ~= nil)
end

local function HideWheel()
    if not (wheel and wheel:IsShown()) then return end
    wheel:EnableGamePadStick(false)
    wheel:Hide()
    if wheel.demo then
        wheel.demo = nil
        return
    end
    BlockSticksUntilCentered()
end

-- update interval of the secure state driver (the hold ticks), set by a secure snippet so the state driver isn't
-- tainted
local stateDriverTimeChanged = false
local function SetStateDriverUpdateTime(time)
    if not (nav and SecureStateDriverManager) then return end
    SecureHandlerSetFrameRef(nav, "statedriver", SecureStateDriverManager)
    nav:SetAttribute("statedrivertime", time)
    SecureHandlerExecute(nav, [[
        local manager = self:GetFrameRef("statedriver")
        if manager then manager:SetAttribute("updatetime", self:GetAttribute("statedrivertime")) end
    ]])
    stateDriverTimeChanged = time ~= DEFAULT_STATE_DRIVER_UPDATE_TIME
end

local holdWrapped = {}
local holdTicker

local function GetHoldTicker()
    if not holdTicker then
        holdTicker = CreateFrame("Frame", "TotemTimers_GamePadHoldTicker", UIParent, "SecureFrameTemplate")
        holdTicker:Hide()
        holdTicker:SetAttribute("unit", "player")
        SecureHandlerWrapScript(holdTicker, "OnShow", nav, HOLD_TICK_ONSHOW)
        SecureHandlerSetFrameRef(nav, "holdticker", holdTicker)
        nav:SetAttribute("holdticks", HOLD_TICKS)
        nav.ShowWheel = ShowWheel
        nav.ArmWheel = ArmWheel
        nav.HideWheel = HideWheel
        nav:SetAttribute("ReadWheelSticks", WHEEL_STICKS)
        nav:SetAttribute("WheelSelection", WHEEL_SELECTION)
        nav:SetAttribute("WheelAssign", WHEEL_ASSIGN)
        nav:SetAttribute("CloseWheel", CLOSE_WHEEL)
        nav.WheelAssigned = WheelAssigned
        nav.SetWheelSticky = SetWheelSticky
        -- Cross/A of a wheel left open casts through this button (WHEEL_CAST_WRAP), on key down
        local cast = CreateFrame("Button", "TotemTimers_GamePadWheelCast", UIParent, "SecureActionButtonTemplate")
        cast:RegisterForClicks("AnyDown")
        cast:SetAttribute("useOnKeyDown", true)
        SecureHandlerWrapScript(cast, "OnClick", nav, WHEEL_CAST_WRAP)
        SecureHandlerSetFrameRef(nav, "wheelcast", cast)
    end
    nav:SetAttribute("wheelstickindex1", GetStickIndex("Movement"))
    nav:SetAttribute("wheelstickindex2", GetStickIndex("Camera"))
    return holdTicker
end

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
        SecureHandlerWrapScript(source, "OnAttributeChanged", nav, SPELL_SOURCE_WRAP)
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
    -- a wheel left open (bindings of the ticker, state of the secure environment)
    if holdTicker then
        SecureHandlerExecute(nav, [[ self:RunAttribute("CloseWheel") ]])
        ClearOverrideBindings(holdTicker)
    end
    HideWheel()
    if stateDriverTimeChanged then SetStateDriverUpdateTime(DEFAULT_STATE_DRIVER_UPDATE_TIME) end
end

-- the slot of a source button (totem timer, multicast button) casts on the release, holding the key opens the
-- wheel of the source's menu
-- totemSlot: totem slot of the timer's element (totem wheels get a destroy segment)
local function SetupHoldWheel(bar, index, source, totemSlot)
    local slot = bar:GetActionButtonByIndex(index)
    if not (slot and overriddenSlots[slot]) then return end
    slot:SetAttribute("useOnKeyDown", false)
    local menu = menuIndices[source]
    if not menu then return end
    GetHoldTicker()
    if not stateDriverTimeChanged then SetStateDriverUpdateTime(HOLD_UPDATE_TIME) end
    slot:SetAttribute("ttHoldMenu", menu)
    slot:SetAttribute("ttTotemSlot", totemSlot)
    if not holdWrapped[slot] then
        SecureHandlerWrapScript(slot, "OnClick", nav, HOLD_WRAP)
        holdWrapped[slot] = true
    end
end

local function ApplyBarMode(bar)
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and timer.button:IsShown() then
            local index = FaceButtonIndices[TimerKeys[timer.nr]]
            OverrideSlotWithSource(bar, index, timer.button)
            SetupHoldWheel(bar, index, timer.button, timer.nr)
        end
    end
    -- d-pad up casts the weapon tracker's enchant (main hand), holding it opens the wheel of its menu
    local weaponButton = GetWeaponButton()
    if weaponButton and TotemTimers.ActiveProfile.WeaponTracker then
        OverrideSlotWithSource(bar, OPEN_BUTTON_INDEX, weaponButton)
        SetupHoldWheel(bar, OPEN_BUTTON_INDEX, weaponButton)
    end
    -- a click on the multicast button would be handed on as a release, which it ignores (it casts on key down),
    -- so the slot casts its spell itself
    local multiSpell = TotemTimers_MultiSpell
    if multiSpell and multiSpell:GetAttribute("active") then
        OverrideSlotWithSource(bar, DPAD_RIGHT_INDEX, multiSpell)
        -- like the totems: cast on the release, holding opens the wheel of the multicast menu
        SetupHoldWheel(bar, DPAD_RIGHT_INDEX, multiSpell)
    end
    local recall = GetAvailableSpellName(SpellIDs.TotemicRecall)
    if recall then OverrideSlot(bar, DPAD_DOWN_INDEX, "spell", recall) end
    local call = GetAvailableSpellName(SpellIDs.TotemicCall)
    if call then OverrideSlot(bar, DPAD_LEFT_INDEX, "spell", call) end
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
    if m then SecureHandlerSetFrameRef(nav, "menupos" .. m, slot or parent) end
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
        local spell = TotemTimers_MultiSpell and TotemTimers_MultiSpell:GetAttribute("*spell1")
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
    local triggers = barMode and LayerKeyTriggers[key]
    local show = triggers and nav and nav:GetAttribute("enabled") and AreLayerTriggersDown(triggers)
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

-- sets up or releases everything, out of combat only (a call in combat waits for the end of combat)
function GamePad.Apply()
    if not TotemTimers.ActiveProfile or not (XiTimers.timers[1] and XiTimers.timers[1].actionBar) then
        return
    end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false

    local active = TotemTimers.ActiveProfile.GamePad and IsGamepadUI()
    timersShown = TotemTimers.ActiveProfile.GamePadTimers and true or false
    actionOverlaysShown = active and timersShown or false
    GamePad.UpdateActionButtons()
    TotemTimers.UpdateRangeDots()
    if not active and not nav then return end
    if not Build() then return end

    ClearOverrideBindings(keyOwner)
    ClearOverrideBindings(layer)
    RestoreSlots()
    barMode = false
    SecureHandlerExecute(nav, [[ self:RunAttribute("Stop", true) ]])
    UpdateMenus()
    nav:SetAttribute("enabled", active)
    HookTimers()
    GamePad.SetLayerExpanded(nil, false)

    local key = GamePad.GetLayerKey()
    if active and key and LayerKeyBars[key] then
        local bar = GetLayerKeyBar()
        if bar then
            barMode = true
            ApplyBarMode(bar)
        end
    end
    GamePad.UpdateBarIcons()
    local hideTimers = barMode and timersShown and TotemTimers.ActiveProfile.GamePadHideTimers
    showActiveTotems = hideTimers and true or false
    GamePad.UpdateBarDurations()
    SetTimersHidden(hideTimers)
    SetMenusAtBar(hideTimers and GetLayerKeyBar())
    HookLegend()
    GamePad.UpdateLegend()
    if not active or barMode then return end
    -- LT + RT can't be bound as a key
    if not key or key == "" or key == GamePad.BOTH_TRIGGERS then return end

    local n = 0
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and TimerKeys[timer.nr] then
            n = n + 1
            SecureHandlerSetFrameRef(layer, "timer" .. n, timer.button)
            layer:SetAttribute("key" .. n, TimerKeys[timer.nr])
        end
    end
    layer:SetAttribute("ntimers", n)

    if TotemTimers_MultiSpell then
        SecureHandlerSetFrameRef(layer, "multispell", TotemTimers_MultiSpell)
    end
    layer:SetAttribute("recall", GetAvailableSpellName(SpellIDs.TotemicRecall))
    layer:SetAttribute("call", GetAvailableSpellName(SpellIDs.TotemicCall))

    SetOverrideBindingClick(keyOwner, true, key, LAYER_NAME, "LeftButton")
end

-- debugging, the output is shown in the debug window (copyable):
-- /run TotemTimers.GamePad.Debug() shows state and bindings,
-- /run TotemTimers.GamePad.LogClicks() logs the clicks of the layer and navigation buttons until the next /reload
local function Line(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

function GamePad.Debug()
    local profile = TotemTimers.ActiveProfile
    local key = GamePad.GetLayerKey()
    local lines = {}
    table.insert(lines, Line("UI:", IsGamepadUI(), "option:", profile and profile.GamePad, "key:", key,
            "enabled:", nav and nav:GetAttribute("enabled"), "pending:", pending))
    table.insert(lines, Line("bar mode:", barMode))
    for slot in pairs(overriddenSlots) do
        table.insert(lines, Line("  slot", slot:GetName(), "type:", slot:GetAttribute("type"),
                "spell:", slot:GetAttribute("spell"), "typerelease:", slot:GetAttribute("typerelease")))
    end
    local keys = { OPEN_KEY }
    if key then table.insert(keys, 1, key) end
    for _, k in ipairs(keys) do
        table.insert(lines, Line("  ", k, "=", GetBindingAction(k), "/ override:", GetBindingAction(k, true)))
    end
    TotemTimers.ShowDebugText(table.concat(lines, "\n"))
end

local clickLog
local function LogClick(...)
    table.insert(clickLog, Line(format("%.2f", GetTime()), ...))
    TotemTimers.ShowDebugText(table.concat(clickLog, "\n"))
end

function GamePad.LogClicks()
    if clickLog then
        TotemTimers.ShowDebugText(table.concat(clickLog, "\n"))
        return
    end
    clickLog = { "Clicks (until the next /reload):" }
    if not nav then
        table.insert(clickLog, "not set up, gamepad support was never active")
    else
        layer:HookScript("OnClick", function(_, button, down)
            LogClick("layer", button, down, GetBindingAction(OPEN_KEY, true))
        end)
        nav:HookScript("OnClick", function(_, button, down) LogClick("nav", button, down) end)
    end
    TotemTimers.ShowDebugText(table.concat(clickLog, "\n"))
end

eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
if C_EventUtils.IsEventValid("INPUT_DEVICE_INTERFACE_TRANSITION") then
    eventFrame:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
end
eventFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then
            GamePad.Apply()
        else
            -- weapon enchant overlays needed in combat are created now
            GamePad.UpdateActionButtons()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        UpdateSlotCooldowns()
    elseif event == "ADDON_LOADED" then
        -- the Gamepad UI action bars can be loaded after TotemTimers
        if addon == "Blizzard_GamepadActionBars" then GamePad.Apply() end
    else
        GamePad.Apply()
    end
end)
