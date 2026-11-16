if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...
local GamePad = TotemTimers.GamePad

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers", true)
local GetPadIconMarkup = GamePad.GetPadIconMarkup
local menuIndices = GamePad.menuIndices
local menuButtons = GamePad.menuButtons
local menuParents = GamePad.menuParents
local GetSpellAttribute = GamePad.GetSpellAttribute
local GetWeaponButton = GamePad.GetWeaponButton
local TimerKeys = GamePad.TimerKeys

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
-- nothing with the sticks in the center, WHEEL_CAST_WRAP), Square/X to the hidden secure button
-- TotemTimers_GamePadWheelAssign (WHEEL_ASSIGN_WRAP, snippet WheelAssign: does what a rightclick on the menu button
-- does, the selected totem becomes the timer button's totem and goes into the multicast slot, the wheel stays open)
-- and Circle/B to the navigation button ("wheelclose", snippet CloseWheel). These keys are only bound after the
-- release: bound while the key is held, they would take the release of a held face button. Pressing a wheel slot again closes a wheel left open first. The ticks
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

-- WheelAssign: the selected totem becomes the totem of the timer button of the open wheel, like a rightclick on the
-- menu button (the parent's wrap in TTActionBars.lua); returns the menu and the number of the menu button (frame ref
-- "m<m>b<j>"; RunAttribute scrubs frame handles from its returns), its own secure action (multicast slot, "*type2"
-- "multispell") is run by WHEEL_ASSIGN_WRAP
local WHEEL_ASSIGN = [[
    if not (wheelOpen and wheelSlot) then return end
    local m = wheelSlot:GetAttribute("ttHoldMenu")
    local i, n
    if m then i, n = self:RunAttribute("WheelSelection", m, wheelSlot:GetAttribute("ttTotemSlot") and 1 or 0) end
    local extra = wheelSlot:GetAttribute("ttTotemSlot") and 1 or 0
    -- the destroy segment (the first one) can't be assigned
    if not i or i <= extra then return end
    local b = self:GetFrameRef("m" .. m .. "b" .. (i - extra))
    local source = wheelSlot:GetFrameRef("ttGamePadSource")
    if not (b and source) then return end
    local spell = b:GetAttribute("*spell1")
    if source:GetAttribute("ttspellattr") == "spell1" then
        -- weapon tracker: the leftclick (main hand), like its menu without modifier
        if spell then
            source:SetAttribute("doublespell1", nil)
            source:SetAttribute("doublespell2", nil)
            source:SetAttribute("type1", "spell")
            source:SetAttribute("spell1", spell)
        elseif b:GetAttribute("doublespell1") then
            source:SetAttribute("doublespell1", b:GetAttribute("doublespell1"))
            source:SetAttribute("doublespell2", b:GetAttribute("doublespell2"))
            source:SetAttribute("type1", "macro")
            source:SetAttribute("ds", 1)
        else
            return
        end
    elseif spell then
        source:SetAttribute("*type1", "spell")
        source:SetAttribute("*spell1", spell)
    else
        return
    end
    self:CallMethod("WheelAssigned", i)
    return m, i - extra
]]

-- Square/X on a wheel left open: assigns the selection (WheelAssign) and runs the rightclick action of its menu button
-- (totem menus: puts the totem into the multicast slot of the active multicast spell unless that is disabled for the
-- timer), pre-click wrap of TotemTimers_GamePadWheelAssign
local WHEEL_ASSIGN_WRAP = [[
    if not down then return false end
    local m, j = control:RunAttribute("WheelAssign")
    local b = m and j and control:GetFrameRef("m" .. m .. "b" .. j)
    local spell = b and b:GetAttribute("*spell1")
    local action = b and b:GetAttribute("*action*")
    if spell and action and b:GetAttribute("*type2") == "multispell" then
        self:SetAttribute("type", "multispell")
        self:SetAttribute("action", action)
        self:SetAttribute("spell", spell)
    else
        return false
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
                ticker:SetBindingClick(true, "PAD3", control:GetFrameRef("wheelassignbutton"), "LeftButton")
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
    if not (GamePad.nav and SecureStateDriverManager) then return end
    SecureHandlerSetFrameRef(GamePad.nav, "statedriver", SecureStateDriverManager)
    GamePad.nav:SetAttribute("statedrivertime", time)
    SecureHandlerExecute(GamePad.nav, [[
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
        SecureHandlerWrapScript(holdTicker, "OnShow", GamePad.nav, HOLD_TICK_ONSHOW)
        SecureHandlerSetFrameRef(GamePad.nav, "holdticker", holdTicker)
        GamePad.nav:SetAttribute("holdticks", HOLD_TICKS)
        GamePad.nav.ShowWheel = ShowWheel
        GamePad.nav.ArmWheel = ArmWheel
        GamePad.nav.HideWheel = HideWheel
        GamePad.nav:SetAttribute("ReadWheelSticks", WHEEL_STICKS)
        GamePad.nav:SetAttribute("WheelSelection", WHEEL_SELECTION)
        GamePad.nav:SetAttribute("WheelAssign", WHEEL_ASSIGN)
        GamePad.nav:SetAttribute("CloseWheel", CLOSE_WHEEL)
        GamePad.nav.WheelAssigned = WheelAssigned
        GamePad.nav.SetWheelSticky = SetWheelSticky
        -- Cross/A of a wheel left open casts through this button (WHEEL_CAST_WRAP), on key down
        local cast = CreateFrame("Button", "TotemTimers_GamePadWheelCast", UIParent, "SecureActionButtonTemplate")
        cast:RegisterForClicks("AnyDown")
        cast:SetAttribute("useOnKeyDown", true)
        SecureHandlerWrapScript(cast, "OnClick", GamePad.nav, WHEEL_CAST_WRAP)
        SecureHandlerSetFrameRef(GamePad.nav, "wheelcast", cast)
        -- Square/X of a wheel left open assigns through this button (WHEEL_ASSIGN_WRAP), on key down
        local assign = CreateFrame("Button", "TotemTimers_GamePadWheelAssign", UIParent, "SecureActionButtonTemplate")
        assign:RegisterForClicks("AnyDown")
        assign:SetAttribute("useOnKeyDown", true)
        SecureHandlerWrapScript(assign, "OnClick", GamePad.nav, WHEEL_ASSIGN_WRAP)
        SecureHandlerSetFrameRef(GamePad.nav, "wheelassignbutton", assign)
    end
    GamePad.nav:SetAttribute("wheelstickindex1", GetStickIndex("Movement"))
    GamePad.nav:SetAttribute("wheelstickindex2", GetStickIndex("Camera"))
    return holdTicker
end


-- the slot of a source button (totem timer, multicast button) casts on the release, holding the key opens the
-- wheel of the source's menu
-- totemSlot: totem slot of the timer's element (totem wheels get a destroy segment)
function GamePad.SetupHoldWheel(bar, index, source, totemSlot)
    local slot = bar:GetActionButtonByIndex(index)
    if not (slot and GamePad.overriddenSlots[slot]) then return end
    slot:SetAttribute("useOnKeyDown", false)
    local menu = menuIndices[source]
    if not menu then return end
    GetHoldTicker()
    if not stateDriverTimeChanged then SetStateDriverUpdateTime(HOLD_UPDATE_TIME) end
    slot:SetAttribute("ttHoldMenu", menu)
    slot:SetAttribute("ttTotemSlot", totemSlot)
    if not holdWrapped[slot] then
        SecureHandlerWrapScript(slot, "OnClick", GamePad.nav, HOLD_WRAP)
        holdWrapped[slot] = true
    end
end


-- closes a wheel left open and sets the update interval of the state driver back (bar mode ends, RestoreSlots)
function GamePad.ReleaseHoldWheels()
    -- a wheel left open (bindings of the ticker, state of the secure environment)
    if holdTicker then
        SecureHandlerExecute(GamePad.nav, [[ self:RunAttribute("CloseWheel") ]])
        ClearOverrideBindings(holdTicker)
    end
    HideWheel()
    if stateDriverTimeChanged then SetStateDriverUpdateTime(DEFAULT_STATE_DRIVER_UPDATE_TIME) end
end
