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

local layer, keyOwner
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
    -- Circle/B while a wheel stays open after the release (see HOLD_WRAP)
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
    if GamePad.nav then return true end
    if InCombatLockdown() then return false end

    keyOwner = CreateFrame("Frame", nil, UIParent)

    GamePad.nav = CreateFrame("Button", NAV_NAME, UIParent, "SecureHandlerClickTemplate")
    GamePad.nav:Hide() -- a hidden button still receives the clicks of its bindings
    -- bindings click on key down; the click handed on by a bar slot (bar mode) is a LeftButton release
    GamePad.nav:RegisterForClicks("AnyDown", "LeftButtonUp")
    GamePad.nav:SetAttribute("Count", COUNT)
    GamePad.nav:SetAttribute("Usable", USABLE)
    GamePad.nav:SetAttribute("ShowMenu", SHOW_MENU)
    GamePad.nav:SetAttribute("Select", SELECT)
    GamePad.nav:SetAttribute("Stop", STOP)
    GamePad.nav:SetAttribute("Neighbor", NEIGHBOR)
    GamePad.nav:SetAttribute("_onclick", NAV_ONCLICK)
    GamePad.nav.SetHighlight = SetHighlight

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
        SecureHandlerSetFrameRef(GamePad.nav, "menu" .. m, menu.parent)
        -- the frame where the menu is shown, for the order of the menus on screen (see SetMenusAtBar)
        SecureHandlerSetFrameRef(GamePad.nav, "menupos" .. m, menu.parent)
        menuIndices[menu.parent] = m
        local buttons = menu.bar.buttons
        menuButtons[m] = buttons
        menuParents[m] = menu.parent
        GamePad.nav:SetAttribute("nbuttons" .. m, #buttons)
        -- the multicast exclusion toggle of totem menus (the menu's extra button), the last segment of their wheels
        if menu.bar.extraButton then
            SecureHandlerSetFrameRef(GamePad.nav, "m" .. m .. "x", menu.bar.extraButton)
        end
        for i, button in ipairs(buttons) do
            SecureHandlerSetFrameRef(GamePad.nav, "m" .. m .. "b" .. i, button)
            button:SetAttribute("ttGamePadMenu", m)
            if not wrapped[button] then
                SecureHandlerWrapScript(button, "OnShow", GamePad.nav, MENU_ONSHOW)
                SecureHandlerWrapScript(button, "OnHide", GamePad.nav, MENU_ONHIDE)
                wrapped[button] = true
            end
        end
    end
    GamePad.nav:SetAttribute("nmenus", #menus)
    GamePad.nav:SetAttribute("multimenu", multiMenu)
    GamePad.nav:SetAttribute("earthmenu", earthMenu)
end

local eventFrame = CreateFrame("Frame")

-- shared with the other GamePad files (GamePadSlots.lua, GamePadActionButtons.lua, GamePadWheel.lua,
-- GamePadBarMode.lua, GamePadRanks.lua, GamePadLegend.lua), which are loaded after this one; state that changes at
-- runtime is kept in fields of GamePad (GamePad.nav, barMode, timersShown, showActiveTotems, actionOverlaysShown)
GamePad.TimerKeys = TimerKeys
GamePad.LayerKeyBars = LayerKeyBars
GamePad.FaceButtonIndices = FaceButtonIndices
GamePad.DPAD_LEFT_INDEX = DPAD_LEFT_INDEX
GamePad.OPEN_BUTTON_INDEX = OPEN_BUTTON_INDEX
GamePad.DPAD_RIGHT_INDEX = DPAD_RIGHT_INDEX
GamePad.DPAD_DOWN_INDEX = DPAD_DOWN_INDEX
GamePad.GetAvailableSpellName = GetAvailableSpellName
GamePad.GetPadIconMarkup = GetPadIconMarkup
GamePad.menuIndices = menuIndices
GamePad.menuButtons = menuButtons
GamePad.menuParents = menuParents
GamePad.GetWeaponButton = GetWeaponButton
GamePad.GetSpellAttribute = GetSpellAttribute
GamePad.barMode = false
GamePad.timersShown = true
GamePad.showActiveTotems = false
GamePad.actionOverlaysShown = false

-- learned spells (Totemic Recall, Totemic Call, multicast spells), runs out of combat
table.insert(TotemTimers.SpellUpdaters, function() GamePad.Apply() end)

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
    GamePad.timersShown = TotemTimers.ActiveProfile.GamePadTimers and true or false
    GamePad.actionOverlaysShown = active and GamePad.timersShown or false
    GamePad.UpdateActionButtons()
    TotemTimers.UpdateRangeDots()
    if not active and not GamePad.nav then return end
    if not Build() then return end

    ClearOverrideBindings(keyOwner)
    ClearOverrideBindings(layer)
    GamePad.RestoreSlots()
    GamePad.barMode = false
    SecureHandlerExecute(GamePad.nav, [[ self:RunAttribute("Stop", true) ]])
    UpdateMenus()
    GamePad.nav:SetAttribute("enabled", active)
    GamePad.HookTimers()
    GamePad.SetLayerExpanded(nil, false)

    local key = GamePad.GetLayerKey()
    if active and key and LayerKeyBars[key] then
        local bar = GamePad.GetLayerKeyBar()
        if bar then
            GamePad.barMode = true
            GamePad.ApplyBarMode(bar)
        end
    end
    GamePad.UpdateBarIcons()
    local hideTimers = GamePad.barMode and GamePad.timersShown and TotemTimers.ActiveProfile.GamePadHideTimers
    GamePad.showActiveTotems = hideTimers and true or false
    GamePad.UpdateBarDurations()
    GamePad.SetTimersHidden(hideTimers)
    GamePad.SetMenusAtBar(hideTimers and GamePad.GetLayerKeyBar())
    GamePad.HookLegend()
    GamePad.UpdateLegend()
    if not active or GamePad.barMode then return end
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
            "enabled:", GamePad.nav and GamePad.nav:GetAttribute("enabled"), "pending:", pending))
    table.insert(lines, Line("bar mode:", GamePad.barMode))
    for slot in pairs(GamePad.overriddenSlots) do
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
    if not GamePad.nav then
        table.insert(clickLog, "not set up, gamepad support was never active")
    else
        layer:HookScript("OnClick", function(_, button, down)
            LogClick("layer", button, down, GetBindingAction(OPEN_KEY, true))
        end)
        GamePad.nav:HookScript("OnClick", function(_, button, down) LogClick("nav", button, down) end)
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
        GamePad.UpdateSlotCooldowns()
    elseif event == "ADDON_LOADED" then
        -- the Gamepad UI action bars can be loaded after TotemTimers
        if addon == "Blizzard_GamepadActionBars" then GamePad.Apply() end
    else
        GamePad.Apply()
    end
end)
