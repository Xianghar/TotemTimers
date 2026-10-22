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
-- d-pad down Totemic Recall, d-pad left Totemic Projection.
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

-- button index of a face button on a Gamepad UI action bar (GAMEPAD_ACTION_BAR_BUTTON_INDICES)
local FaceButtonIndices = {
    PAD3 = 5, -- left
    PAD4 = 6, -- top
    PAD2 = 7, -- right
    PAD1 = 8, -- bottom
}

-- slots of the d-pad on a Gamepad UI action bar
local DPAD_LEFT_INDEX = 1
local OPEN_BUTTON_INDEX = 2 -- d-pad up (OPEN_KEY)
local DPAD_RIGHT_INDEX = 3
local DPAD_DOWN_INDEX = 4
local OPEN_ICON = "Interface\\AddOns\\TotemTimers\\textures\\totemtimers"

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

-- Neighbor(m, vertical, forward): next usable menu on screen. Vertical menus are ordered left to right
-- (then top to bottom), horizontal menus top to bottom (then left to right), wrapping around at the end.
local NEIGHBOR = [[
    local m, vertical, forward = ...
    local cl, cb, cw, ch = self:GetFrameRef("menu" .. m):GetRect()
    if not cl then return end
    local c1, c2
    if vertical then c1, c2 = cl + cw / 2, -(cb + ch / 2) else c1, c2 = -(cb + ch / 2), cl + cw / 2 end
    if not forward then c1, c2 = -c1, -c2 end
    local best, b1, b2, first, f1, f2
    for k = 1, self:GetAttribute("nmenus") or 0 do
        if k ~= m and self:RunAttribute("Usable", k) then
            local l, b, w, h = self:GetFrameRef("menu" .. k):GetRect()
            if l then
                local k1, k2
                if vertical then k1, k2 = l + w / 2, -(b + h / 2) else k1, k2 = -(b + h / 2), l + w / 2 end
                if not forward then k1, k2 = -k1, -k2 end
                if ((k1 > c1 + 1) or (abs(k1 - c1) <= 1 and k2 > c2))
                        and (not best or k1 < b1 - 1 or (abs(k1 - b1) <= 1 and k2 < b2)) then
                    best, b1, b2 = k, k1, k2
                end
                if not first or k1 < f1 - 1 or (abs(k1 - f1) <= 1 and k2 < f2) then
                    first, f1, f2 = k, k1, k2
                end
            end
        end
    end
    return best or first
]]

-- clicks of the bindings: "open" (layer key + d-pad up), d-pad directions and "close"
local NAV_ONCLICK = [[
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
-- multicast spell), d-pad down and left cast Totemic Recall and Totemic Projection (attributes recall, projection).
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
        local projection = self:GetAttribute("projection")
        if projection then self:SetBindingSpell(true, "PADDLEFT", projection) end
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

    for m, menu in ipairs(menus) do
        SecureHandlerSetFrameRef(nav, "menu" .. m, menu.parent)
        local buttons = menu.bar.buttons
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

-- bar mode (layer key is a trigger): the key stays with the game, slots of its bar are TotemTimers buttons;
-- only those slots get overlays (by bar button index)
local barMode = false
local barModeSlots = {}

local function GetLayerKeyBar()
    local barKey = LayerKeyBars[TotemTimers.ActiveProfile.GamePadLayerKey]
    local pageUnit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
    local bar = barKey and pageUnit and pageUnit.actionBars and pageUnit.actionBars[barKey]
    if bar and bar.GetActionButtonByIndex then return bar end
end

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

        -- above the swipe: the border of the gamepad button (copy of its normal texture) and the time
        local overlay = CreateFrame("Frame", nil, slot)
        overlay:SetAllPoints(slot)
        overlay:SetFrameLevel(slot.cooldown:GetFrameLevel() + 1)
        slot.border = overlay:CreateTexture(nil, "ARTWORK")
        slot.border:SetAllPoints(slot)

        -- remaining time like on the timer buttons, bound to the DurationObject; without text bindings the
        -- cooldown's countdown numbers are used instead
        if XiTimers.CanBindDurationText then
            slot.cooldown:SetHideCountdownNumbers(true)
            slot.time = overlay:CreateFontString(nil, "OVERLAY")
            slot.time:SetFontObject(TotemTimersButtonTimeFont)
            slot.time:SetPoint("CENTER", slot, "CENTER")
            slot.timeBinding = C_DurationUtil.CreateDurationTextBinding()
            slot.timeBinding:SetFormatter(XiTimers.GetSecondsFormatter())
            slot.timeBinding:SetExpiredText("")
            slot.timeBinding:SetZeroDurationText("")
            slot.timeBinding:SetFontString(slot.time)
        else
            slot.cooldown:SetHideCountdownNumbers(false)
        end
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

-- remaining duration of the totem, from the DurationObject of the running totem timer (never read in Lua)
local function UpdateSlotDuration(slot)
    local durObj = slot.timer and slot.timer.timers[1]
    if durObj then
        slot.cooldown:SetCooldownFromDurationObject(durObj)
    else
        slot.cooldown:Clear()
    end
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

-- shows a slot with the texture, timer: totem timer whose duration is shown
local function ShowSlot(bar, index, texture, timer)
    if barMode and not barModeSlots[index] then return end
    local button = texture and index and bar:GetActionButtonByIndex(index)
    if not (button and button.icon) then return end
    local slot = GetBarIcon(button, index)
    UpdateSlotShape(slot, button)
    UpdateSlotBorder(slot, button)
    UpdateSlotLayout(slot, bar)
    slot.icon:SetTexture(texture)
    slot.timer = timer
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
        slot:Hide()
    end
    local bar = nav and nav:GetAttribute("enabled") and GetLayerKeyBar()
    -- in bar mode the game focuses the bar itself
    SetFocusBackground(not barMode and bar or nil)
    if not bar then return end
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and timer.button:IsShown() then
            local spell = timer.button:GetAttribute("*spell1")
            local texture = spell and spell ~= 0 and C_Spell.GetSpellTexture(spell)
            ShowSlot(bar, FaceButtonIndices[TimerKeys[timer.nr]], texture, timer)
        end
    end

    -- d-pad: up opens the totem menus, right casts the selected multicast spell,
    -- down Totemic Recall, left Totemic Projection
    local multiSpell = TotemTimers_MultiSpell
    local multiSpellID = multiSpell and multiSpell:GetAttribute("active") and multiSpell:GetAttribute("*spell1")
    ShowSlot(bar, OPEN_BUTTON_INDEX, OPEN_ICON)
    ShowSlot(bar, DPAD_RIGHT_INDEX, multiSpellID and C_Spell.GetSpellTexture(multiSpellID))
    ShowSlot(bar, DPAD_DOWN_INDEX,
            GetAvailableSpellName(SpellIDs.TotemicCall) and C_Spell.GetSpellTexture(SpellIDs.TotemicCall))
    ShowSlot(bar, DPAD_LEFT_INDEX,
            GetAvailableSpellName(SpellIDs.TotemicProjection) and C_Spell.GetSpellTexture(SpellIDs.TotemicProjection))
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
end

-- learned spells (Totemic Recall, Totemic Projection, multicast spells), runs out of combat
table.insert(TotemTimers.SpellUpdaters, function() GamePad.Apply() end)

-- Bar mode: the layer key is a trigger (LT/RT). The trigger stays with the Gamepad UI (its bar expands, LT+RT works),
-- and the secure attributes of slots of the trigger's bar are changed so that pressing them casts TotemTimers'
-- spells: the game's own click handling of the slot (TriggerSecureClick -> SecureActionButton_OnClick) then runs
-- type "spell" instead of the slot's action. The game sets type "action" once and only changes the slot's ID when
-- paging, so the attributes stay; the slot's original action is unusable on all pages of the bar meanwhile.
-- The totem of a timer slot follows the timer's *spell1 by a secure wrap of the timer button (also in combat).

-- slots of the bar in bar mode: face buttons cast the totems of the timers, d-pad up opens the totem menus
-- (click on the navigation button), right casts the selected multicast spell, down Totemic Recall,
-- left Totemic Projection

local overriddenSlots = {}

-- a source button (totem timer, multicast button) sets the spell of its bar slot when its spell changes,
-- also in combat
local SPELL_SOURCE_WRAP = [[
    if name == "*spell1" then
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
    local slot = OverrideSlot(bar, index, "spell", source:GetAttribute("*spell1"))
    if not slot then return end
    SecureHandlerSetFrameRef(source, "ttGamePadSlot", slot)
    if not wrappedSources[source] then
        SecureHandlerWrapScript(source, "OnAttributeChanged", nav, SPELL_SOURCE_WRAP)
        wrappedSources[source] = true
    end
end

local function RestoreSlots()
    for slot in pairs(overriddenSlots) do
        slot:SetAttribute("ttGamePadOverride", nil)
        slot:SetAttribute("spell", nil)
        slot:SetAttribute("clickbutton", nil)
        slot:SetAttribute("type", "action")
        slot:SetAttribute("typerelease", "actionrelease")
    end
    wipe(overriddenSlots)
    wipe(barModeSlots)
end

local function ApplyBarMode(bar)
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and timer.button:IsShown() then
            OverrideSlotWithSource(bar, FaceButtonIndices[TimerKeys[timer.nr]], timer.button)
        end
    end
    -- the click is handed on as a release, the navigation button takes the LeftButton click as "open"
    OverrideSlot(bar, OPEN_BUTTON_INDEX, "click", nav)
    -- a click on the multicast button would be handed on as a release, which it ignores (it casts on key down),
    -- so the slot casts its spell itself
    local multiSpell = TotemTimers_MultiSpell
    if multiSpell and multiSpell:GetAttribute("active") then
        OverrideSlotWithSource(bar, DPAD_RIGHT_INDEX, multiSpell)
    end
    local recall = GetAvailableSpellName(SpellIDs.TotemicCall)
    if recall then OverrideSlot(bar, DPAD_DOWN_INDEX, "spell", recall) end
    local projection = GetAvailableSpellName(SpellIDs.TotemicProjection)
    if projection then OverrideSlot(bar, DPAD_LEFT_INDEX, "spell", projection) end
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

    local key = TotemTimers.ActiveProfile.GamePadLayerKey
    if active and key and LayerKeyBars[key] then
        local bar = GetLayerKeyBar()
        if bar then
            barMode = true
            ApplyBarMode(bar)
        end
    end
    GamePad.UpdateBarIcons()
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
    layer:SetAttribute("recall", GetAvailableSpellName(SpellIDs.TotemicCall))
    layer:SetAttribute("projection", GetAvailableSpellName(SpellIDs.TotemicProjection))

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
    local key = profile and profile.GamePadLayerKey
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
if C_EventUtils.IsEventValid("INPUT_DEVICE_INTERFACE_TRANSITION") then
    eventFrame:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
end
eventFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then GamePad.Apply() end
    elseif event == "ADDON_LOADED" then
        -- the Gamepad UI action bars can be loaded after TotemTimers
        if addon == "Blizzard_GamepadActionBars" then GamePad.Apply() end
    else
        GamePad.Apply()
    end
end)
