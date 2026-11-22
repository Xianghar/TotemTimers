if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...

-- Edit Mode integration with LibEditMode (libs/LibEditMode): the anchor frames of TotemTimers (totem timers,
-- trackers, combat cooldowns, always visible menus) are moved in the game's Edit Mode, the buttons of the loose
-- arrangement (Arrange/TrackerArrange "free") each on their own. Positions are kept per Edit Mode layout
-- (profile.LayoutPositions[layoutName], copied from profile.FramePositions/TimerPositions when something is first
-- moved in a layout). Snapping is our own (LibEditMode has none, Blizzard's EditModeMagnetismManager needs the
-- methods of its system frames): on the end of a drag, with "Snap" enabled in the Edit Mode, a selection snaps to the
-- screen edges and center, the grid lines (if shown), and the edges and centers of neighboring TotemTimers frames and
-- Blizzard Edit Mode systems.

local LEM = LibStub("LibEditMode", true)
local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers", true)

local Timers = XiTimers.timers

local activeLayout -- name of the active Edit Mode layout, nil until LibEditMode knows it
local entries = {} -- registered frames: { frame, selection, name, content = function() -> frames or nil }
local ticker
local applyAfterCombat

local SNAP_RANGE_DEFAULT = 8

-- positions

local function CopyPositions(t)
    return t and CopyTable(t) or {}
end

-- the position tables of the active layout: { FramePositions, TimerPositions }; without an entry of the layout the
-- profile's own tables (positions from before the Edit Mode, the start of every layout), with create the layout's
-- entry is created from them
function TotemTimers.GetLayoutPositions(create, layoutName)
    local profile = TotemTimers.ActiveProfile
    layoutName = layoutName or activeLayout
    if layoutName then
        profile.LayoutPositions = profile.LayoutPositions or {}
        local entry = profile.LayoutPositions[layoutName]
        if entry then
            return entry
        end
        if create then
            entry = {
                FramePositions = CopyPositions(profile.FramePositions),
                TimerPositions = CopyPositions(profile.TimerPositions),
            }
            profile.LayoutPositions[layoutName] = entry
            return entry
        end
    end
    return profile
end

-- after a position change: the menu directions ("auto" follows the position) and the timer bar sides
local function PositionsChanged()
    if InCombatLockdown() then
        return
    end
    TotemTimers.PositionCastButtons()
    TotemTimers.ProcessSetting("WeaponBarDirection")
    if TotemTimers.EarthShieldTracker and TotemTimers.EarthShieldTracker.actionBar then
        TotemTimers.ProcessSetting("ESMainTankMenuDirection")
    end
    for i = 1, 9 do
        local timer = Timers[i]
        if timer and timer.active then
            timer:SetTimerBarPos(timer.timerBarPos, true)
        end
    end
end

local function ApplyFramePositions()
    if InCombatLockdown() then
        applyAfterCombat = true
        return
    end
    TotemTimers.ProcessSetting("FramePositions")
    TotemTimers.OrderTimers()
    TotemTimers.OrderTrackers()
    PositionsChanged()
end

-- applies the positions of the active layout (layout change, profile reset)
function TotemTimers.ApplyFramePositions()
    if TotemTimers_IsSetUp then
        ApplyFramePositions()
    end
end

-- LibEditMode callback: a registered frame was moved (point relative to UIParent)
local function OnMoved(frame, layoutName, point, x, y)
    local entry = TotemTimers.GetLayoutPositions(true, layoutName)
    local pos = { point, "UIParent", point, x, y }
    if frame.ttTimerNr then
        entry.TimerPositions[frame.ttTimerNr] = pos
    else
        entry.FramePositions[frame:GetName()] = pos
    end
    PositionsChanged()
end

-- layouts

local function ForEachProfile(func)
    for _, profile in pairs(TotemTimers_Profiles) do
        if type(profile) == "table" and profile.LayoutPositions then
            func(profile.LayoutPositions)
        end
    end
end

if LEM then
    LEM:RegisterCallback("layout", function(layoutName)
        activeLayout = layoutName
        TotemTimers.ApplyFramePositions()
    end)
    -- a new layout copied from another one takes its positions
    LEM:RegisterCallback("create", function(layoutName, _, sourceName)
        if not sourceName then return end
        ForEachProfile(function(positions)
            if positions[sourceName] then
                positions[layoutName] = CopyTable(positions[sourceName])
            end
        end)
    end)
    LEM:RegisterCallback("rename", function(oldName, newName)
        ForEachProfile(function(positions)
            positions[newName] = positions[oldName]
            positions[oldName] = nil
        end)
        if activeLayout == oldName then
            activeLayout = newName
        end
    end)
    LEM:RegisterCallback("delete", function(layoutName)
        ForEachProfile(function(positions)
            positions[layoutName] = nil
        end)
    end)
end

-- selections

local function UIRect(frame)
    local left, bottom, width, height = frame:GetRect()
    if not left then
        return
    end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale
end

local function AddFrame(list, frame)
    if frame then
        list[#list + 1] = frame
    end
end

-- button and shown timer bars of an XiTimers timer
local function AddTimer(list, timer)
    if not timer then
        return
    end
    AddFrame(list, timer.button)
    for _, bar in ipairs(timer.timerBars or {}) do
        if bar:IsShown() then
            AddFrame(list, bar)
        end
    end
end

-- the selection of an anchor frame covers the frames it positions
local function UpdateAnchorSelection(entry)
    local frames = entry.content()
    local left, bottom, right, top
    if frames then
        for _, frame in ipairs(frames) do
            local l, b, r, t = UIRect(frame)
            if l and r > l and t > b then
                left = left and math.min(left, l) or l
                bottom = bottom and math.min(bottom, b) or b
                right = right and math.max(right, r) or r
                top = top and math.max(top, t) or t
            end
        end
    end
    local selection = entry.selection
    if frames and not left then
        -- frames in use but without a valid rect (hidden and never laid out): a button sized box at the anchor
        local l, b, r, t = UIRect(entry.frame)
        if l then
            local cx, cy = (l + r) / 2, (b + t) / 2
            left, bottom, right, top = cx - 18, cy - 18, cx + 18, cy + 18
        end
    end
    if not left then
        selection.ttDisabled = true
        selection:Hide()
        return
    end
    -- offsets from the anchor's center, in the anchor's scale
    local cx, cy = entry.frame:GetCenter()
    local anchorScale = entry.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    cx, cy = cx * anchorScale, cy * anchorScale
    selection:ClearAllPoints()
    selection:SetPoint("BOTTOMLEFT", entry.frame, "CENTER", (left - cx) / anchorScale, (bottom - cy) / anchorScale)
    selection:SetPoint("TOPRIGHT", entry.frame, "CENTER", (right - cx) / anchorScale, (top - cy) / anchorScale)
    return true
end

local function UpdateSelections()
    if not LEM or not LEM:IsInEditMode() or InCombatLockdown() then
        return
    end
    for _, entry in ipairs(entries) do
        local enabled
        if entry.isButton then
            enabled = entry.enabled()
        else
            enabled = UpdateAnchorSelection(entry)
        end
        local selection = entry.selection
        if enabled then
            if selection.ttDisabled then
                selection.ttDisabled = nil
                if selection.isSelected then
                    selection:ShowSelected(true)
                else
                    selection:ShowHighlighted()
                end
            end
        else
            selection.ttDisabled = true
            selection:Hide()
        end
    end
end

-- snapping

local function SnapRange()
    return EditModeMagnetismManager and EditModeMagnetismManager.magnetismRange or SNAP_RANGE_DEFAULT
end

-- the nearest of the candidates to one of the values within range: returns the difference
local function NearestOffset(values, candidates, range, best)
    for _, value in ipairs(values) do
        for _, candidate in ipairs(candidates) do
            local d = candidate - value
            if math.abs(d) <= range and (not best or math.abs(d) < math.abs(best)) then
                best = d
            end
        end
    end
    return best
end

-- rects (UIParent units) of the other frames to snap to: our shown selections and the Blizzard systems
local function OtherRects(own)
    local rects = {}
    for _, entry in ipairs(entries) do
        local selection = entry.selection
        if selection ~= own and selection:IsVisible() then
            local l, b, r, t = UIRect(selection)
            if l then rects[#rects + 1] = { l, b, r, t } end
        end
    end
    local systems = EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames
    if systems then
        for _, system in ipairs(systems) do
            local selection = system.Selection
            if selection and selection:IsVisible() then
                local l, b, r, t = UIRect(selection)
                if l then rects[#rects + 1] = { l, b, r, t } end
            end
        end
    end
    return rects
end

local function SnapOffsets(selection)
    local left, bottom, right, top = UIRect(selection)
    if not left then
        return
    end
    local range = SnapRange()
    local xs = { left, (left + right) / 2, right }
    local ys = { bottom, (bottom + top) / 2, top }

    -- screen edges and center
    local width, height = UIParent:GetSize()
    local dx = NearestOffset(xs, { 0, width / 2, width }, range)
    local dy = NearestOffset(ys, { 0, height / 2, height }, range)

    -- grid lines (registered by the Edit Mode grid while it is shown, in UIParent coordinates)
    local grid = EditModeMagnetismManager and EditModeMagnetismManager.magneticGridLines
    if grid and EditModeManagerFrame.Grid and EditModeManagerFrame.Grid:IsShown() then
        local vertical, horizontal = {}, {}
        for _, x in pairs(grid.vertical or {}) do vertical[#vertical + 1] = x end
        for _, y in pairs(grid.horizontal or {}) do horizontal[#horizontal + 1] = y end
        dx = NearestOffset(xs, vertical, range, dx)
        dy = NearestOffset(ys, horizontal, range, dy)
    end

    -- edges and centers of the frames next to it (overlapping or within range on the other axis)
    for _, rect in ipairs(OtherRects(selection)) do
        local l, b, r, t = rect[1], rect[2], rect[3], rect[4]
        if bottom <= t + range and top >= b - range then
            dx = NearestOffset(xs, { l, (l + r) / 2, r }, range, dx)
        end
        if left <= r + range and right >= l - range then
            dy = NearestOffset(ys, { b, (b + t) / 2, t }, range, dy)
        end
    end
    -- nil for an axis without a snap target in range
    return dx, dy
end

local function Snap(selection)
    if InCombatLockdown() or not EditModeManagerFrame:IsSnapEnabled() then
        return
    end
    local dx, dy = SnapOffsets(selection)
    if not dx and not dy then
        return
    end
    local frame = selection.parent
    local point, _, _, x, y = frame:GetPoint(1)
    if not point then
        return
    end
    -- the frame's offsets are in its own scale
    local scale = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    -- a snapped axis is rounded to whole units: the buttons are aligned to screen pixels, so a selection's center can
    -- be half a unit beside its anchor's (centered on the screen center the anchor's offset would be 0.5)
    if dx then x = math.floor(x + dx * scale + 0.5) end
    if dy then y = math.floor(y + dy * scale + 0.5) end
    -- set directly, not with LibEditMode's MoveParentToPoint: that reads the position back from the frame's (pixel
    -- aligned) rect and would bring the half unit back
    frame:ClearAllPoints()
    frame:SetPoint(point, x, y)
    OnMoved(frame, LEM:GetActiveLayoutName(), point, x, y)
    -- the coordinates in LibEditMode's dialog
    local dialog = LEM.internal and LEM.internal.dialog
    if selection.isSelected and dialog and dialog.Update then
        dialog:Update(selection, point, x, y)
    end
end

-- registration

local function DefaultPosition(pos)
    if pos and pos[1] then
        return { point = pos[1], x = pos[4] or 0, y = pos[5] or 0 }
    end
    return { point = "CENTER", x = 0, y = 0 }
end

local function Register(frame, name, default, content, enabled)
    LEM:AddFrame(frame, OnMoved, DefaultPosition(default), name)
    local selection = LEM.frameSelections[frame]
    local entry = { frame = frame, selection = selection, name = name, content = content, enabled = enabled,
                    isButton = enabled ~= nil }
    entries[#entries + 1] = entry
    if selection then
        -- LibEditMode shows all its selections in the Edit Mode: those of frames not in use stay hidden
        selection:HookScript("OnShow", function(self)
            if self.ttDisabled then self:Hide() end
        end)
        selection:HookScript("OnDragStop", Snap)
    end
end

local function TotemTimersContent()
    local Settings = TotemTimers.ActiveProfile
    local frames = {}
    if Settings.Arrange ~= "free" then
        for e = 1, 4 do
            if Timers[e].active then AddTimer(frames, Timers[e]) end
        end
    end
    local multiCast = TotemTimers_MultiSpell
    if multiCast and multiCast:IsShown() then
        AddFrame(frames, multiCast)
    end
    local call = TotemTimers.TotemicCallTimer
    if call and call.active then
        AddTimer(frames, call)
    end
    return #frames > 0 and frames
end

local function TrackerContent()
    if TotemTimers.ActiveProfile.TrackerArrange == "free" then
        return
    end
    local frames = {}
    for i = 5, 8 do
        if Timers[i].active and Timers[i].button:IsShown() then AddTimer(frames, Timers[i]) end
    end
    return #frames > 0 and frames
end

local function EnhanceCDsContent()
    if not TotemTimers.ActiveProfile.EnhanceCDs then
        return
    end
    local frames = {}
    -- active timers count even when hidden out of combat (HideEnhanceCDsOOC): their places are still the layout
    for _, timer in ipairs(TotemTimers.EnhanceCDs or {}) do
        if timer.active then AddFrame(frames, timer.button) end
    end
    local flameShock = TotemTimers.FlameShockDuration
    if flameShock and flameShock.active then
        AddFrame(frames, flameShock.button)
        AddFrame(frames, flameShock.timerBars[1])
    end
    local maelstrom = TotemTimers.Maelstrom
    if maelstrom and maelstrom.active then
        AddFrame(frames, maelstrom.button)
        AddFrame(frames, maelstrom.timerBars[1])
    end
    local icon = TotemTimers_MaelstromIcon
    if icon and icon:IsShown() and not TotemTimers.ActiveProfile.MaelstromIconAtCharacter then
        AddFrame(frames, icon)
    end
    return #frames > 0 and frames
end

-- an always visible menu (MenusAlwaysVisible) anchored to its own frame
local function MenuContent(anchor)
    return function()
        local bar
        for _, b in ipairs(TTActionBars.bars) do
            if b.secondanchor == anchor then bar = b break end
        end
        if not bar or not bar.alwaysvisible or bar.menuAnchor then
            return
        end
        local frames = {}
        for _, button in ipairs(bar.buttons) do
            if button:IsShown() then AddFrame(frames, button) end
        end
        return #frames > 0 and frames
    end
end

local TimerNames = {
    [EARTH_TOTEM_SLOT] = "Earth Totem Timer",
    [FIRE_TOTEM_SLOT] = "Fire Totem Timer",
    [WATER_TOTEM_SLOT] = "Water Totem Timer",
    [AIR_TOTEM_SLOT] = "Air Totem Timer",
    [5] = "Ankh Tracker",
    [6] = "Shield Tracker",
    [7] = "Earth Shield Tracker",
    [8] = "Weapon Tracker",
}

function TotemTimers.SetupEditMode()
    if not LEM or #entries > 0 then
        return
    end
    activeLayout = LEM:GetActiveLayoutName()
    local defaults = TotemTimers.DefaultProfile.FramePositions

    local anchors = {
        { TotemTimersFrame, L["Totem Timers"], TotemTimersContent },
        { TotemTimers_TrackerFrame, L["Trackers"], TrackerContent },
        { TotemTimers_EnhanceCDsFrame, L["Combat Cooldowns"], EnhanceCDsContent },
        { TotemTimers_MultiSpellFrame, L["Multicast Menu"], MenuContent(TotemTimers_MultiSpellFrame) },
    }
    for i = 1, 4 do
        local frame = _G["TotemTimers_CastBar" .. i]
        anchors[#anchors + 1] = { frame, L["Totem Menu %d"]:format(i), MenuContent(frame) }
    end
    for _, anchor in ipairs(anchors) do
        local frame = anchor[1]
        if frame then
            frame:EnableMouse(false)
            frame:Show()
            Register(frame, anchor[2], defaults[frame:GetName()], anchor[3])
        end
    end

    -- the buttons of the loose arrangement
    for nr = 1, 8 do
        local timer = Timers[nr]
        local button = timer and timer.button
        if button and TimerNames[nr] then
            button.ttTimerNr = nr
            -- moved by LibEditMode with StartMoving: not into the client's layout cache, the positions are ours
            button:SetDontSavePosition(true)
            local isTotem = nr <= 4
            Register(button, L[TimerNames[nr]], TotemTimers.DefaultProfile.TimerPositions[nr], nil, function()
                local arrange = isTotem and TotemTimers.ActiveProfile.Arrange or TotemTimers.ActiveProfile.TrackerArrange
                return arrange == "free" and timer.active and button:IsShown()
            end)
        end
    end

    LEM:RegisterCallback("enter", function()
        UpdateSelections()
        if not ticker then
            -- settings can change while the Edit Mode is open, and the selections follow their frames' sizes
            ticker = C_Timer.NewTicker(0.25, UpdateSelections)
        end
    end)
    LEM:RegisterCallback("exit", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function()
        if applyAfterCombat then
            applyAfterCombat = nil
            TotemTimers.ApplyFramePositions()
        end
    end)

    -- the settings were applied before the layout was known
    ApplyFramePositions()
end
