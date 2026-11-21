if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...

-- Displays possibly secret auras on a timer button with an aura container (Blizzard_AuraContainer) laid over it:
-- the game shows a slot button while one of the slot's auras is up and draws icon, swipe or timer bar, time
-- and charges on it. The addon never reads the aura, so the XiTimers timer of the button isn't started.
-- Each slot covers the whole button, slots with a higher level are drawn on top.
-- Like XiTimers buttons, the time is shown on a timer bar instead of the swipe if the timer doesn't show its
-- time on the button. The bar is laid over the (unused) first timer bar of the XiTimers timer, so it follows
-- its position and size, and takes over its texture, colors and font.
-- Without time (SetTimeShown(false), charges only), the charges are shown where the time would be: on a full
-- timer bar or in the button's time string.
--
-- Slot buttons can only be set up in initializeFrame of AddAuraSlot and can't be changed afterwards.
-- So the display keeps the slot definitions and builds the container from them and its configuration
-- (options and the look of the timer's bar). If the configuration changes (e.g. from the options GUI), a new
-- container is built and the old one is hidden and left behind, as frames can't be destroyed. Builds are deferred
-- to the next frame, so everything done at once (creating the slots at addon initialization, applying all
-- settings) results in a single build. In combat the build waits until combat ends.
--
-- usage:
--   local display = TotemTimers.AuraDisplay:new(timer.button)    -- nil if aura containers aren't available
--   (other buttons, e.g. of the Gamepad UI: AuraDisplay:new(button, unit, { textAnchor = button, noIcon = true }))
--   display:AddSlot("key", { [spellID] = true, ... }, level)
--   display:SetSlotEnabled("key", enabled)
--   display:SetTimeShown(shown)
--   TotemTimers.AuraDisplay.UpdateAll()                          -- after changing settings of the timers
--
-- dot mode (AuraDisplay:new(button, unit, { dot = texture })): the slot buttons show only a dot laid over the
-- given texture (which stays hidden and serves as anchor, size and image), no icon, time or charges.
-- With tint = true the "dot" is a colored additive layer over the given region (e.g. the icon) instead, optionally
-- cut out by a mask atlas (maskAtlas, inset maskInset from the region's edges).
--   display:SetDotColor(r, g, b)     -- rebuilds the container if the color changed
--
-- auras on other units than the player: AuraDisplay:new(timer.button, "target"), display:AddSlot(key, ids, level,
-- "HARMFUL|PLAYER"). The container doesn't follow changes of the unit token (e.g. a new target) by itself;
-- displays of "target" are refreshed on PLAYER_TARGET_CHANGED here, for other tokens call display:Refresh()
-- (works in combat).
-- display.iconAboveBar = true: for timer bars that start at the button (under the icon, like the Flame Shock timer),
-- the icon is drawn above the bar instead of below it.
-- display.maxApplications = n: the bar shows the stacks of the aura (full at n) instead of the duration (with
-- SetTimeShown(false) the bar's text shows the stacks, e.g. the Maelstrom tracker).

local AuraDisplay = {}
AuraDisplay.__index = AuraDisplay
TotemTimers.AuraDisplay = AuraDisplay

local displays = {}

-- formatter of the charges shown in place of the time: the game only shows counts above 1 without a formatter,
-- but here a single charge is shown, too (auras without stacks, 0, show nothing). false if not available.
local chargesFormatter
local function GetChargesFormatter()
    if chargesFormatter == nil then
        local ok, formatter = pcall(function()
            local f = C_StringUtil.CreateNumericRuleFormatter()
            f:AddBreakpoint({ threshold = 0, format = "" })
            f:AddBreakpoint({ threshold = 1, format = "%d" })
            if f:FormatNumber(1) == "1" and f:FormatNumber(3) == "3" then return f end
        end)
        chargesFormatter = ok and formatter or false
    end
    return chargesFormatter or nil
end

local function IsAuraContainerAvailable()
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
end

-- always shown frame outside the aura containers that runs the animations of the glow and image modes (see
-- InitGlowButton, InitImageButton): animations below a frame with secret visibility stop while it is hidden and
-- can't be restarted there
local animator = CreateFrame("Frame", nil, UIParent)
animator:SetSize(1, 1)
animator:SetPoint("TOPLEFT")
local animations = setmetatable({}, { __mode = "k" })
-- hiding the UI (UIParent) stops the animations
animator:SetScript("OnShow", function()
    for animation in pairs(animations) do
        animation:Play()
    end
end)

-- displays waiting for the end of combat to be built
local pendingBuilds = {}
local combatFrame = CreateFrame("Frame")
combatFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    for display in pairs(pendingBuilds) do
        pendingBuilds[display] = nil
        display:Build()
    end
end)

-- options, for parents that aren't XiTimers buttons (without time, icons, count):
--   textAnchor: region the time (or the charges) is centered on, instead of the parent's time string
--   noIcon: the slot buttons show no icon (the parent shows one itself)
--   swipeTexture, swipeInset: texture (e.g. round) and inset from the edges of the swipe
--   forGamePad: the time is formatted for Gamepad UI buttons (no "s" for seconds, see XiTimers.GetTimeFormatter)
--   dot: texture the slot buttons show a dot over (dot mode, see above)
--   tint, maskAtlas, maskInset: dot mode with a tint over the dot region (see above)
--   glow: { region = region, minApplications = n, round = bool }: glow mode, a glow around the region while the aura
--     has at least n stacks (see InitGlowButton), round: the round glow (round Gamepad UI buttons)
--   image: { region = region, texture = path, applications = n, exact = bool, pulse = bool }: image mode, the
--     texture over the region while the aura has n stacks (exact) or at least n stacks, optionally pulsing (see
--     InitImageButton)
function AuraDisplay:new(parent, unit, options)
    if not IsAuraContainerAvailable() then return end
    local display = setmetatable({}, AuraDisplay)
    display.parent = parent
    -- XiTimers timer of the button, if any
    display.timer = not options and parent.timer or nil
    display.textAnchor = options and options.textAnchor
    display.noIcon = options and options.noIcon or false
    display.dot = options and options.dot
    display.tint = options and options.tint or false
    display.maskAtlas = options and options.maskAtlas
    display.maskInset = options and options.maskInset or 0
    display.swipeTexture = options and options.swipeTexture
    display.swipeInset = options and options.swipeInset or 0
    display.forGamePad = options and options.forGamePad or false
    display.glow = options and options.glow
    display.image = options and options.image
    display.dotColor = { 1, 1, 1, 1 }
    display.unit = unit or "player"
    -- slot definitions in the order they were added
    display.slots = {}
    display.slotEnabled = {}
    -- widgets handed to the slot buttons of the current container, by slot key
    display.regions = {}
    display.timeShown = true
    table.insert(displays, display)
    return display
end

-- rechecks the configuration of all displays, rebuilds those that changed
function AuraDisplay.UpdateAll()
    for _, display in ipairs(displays) do
        display:ScheduleBuild()
    end
end

-- configuration the slot buttons are built with
function AuraDisplay:GetConfig()
    local timer = self.timer
    local config = { timeShown = self.timeShown, timeStyle = self.timeShown and XiTimers.TimeStyle or nil }
    if self.dot then
        config.dotColor = { unpack(self.dotColor) }
    end
    if self.glow then
        -- the glow's outset follows the height of the region, a new size rebuilds the container
        config.glowHeight = math.floor(self.glow.region:GetHeight() + 0.5)
    end
    if self.image then
        -- the mask's margin follows the width of the region
        config.imageWidth = math.floor(self.image.region:GetWidth() + 0.5)
    end
    if timer then
        config.showBar = not timer.timerOnButton or timer.forceBar or false
        config.showSwirl = not config.showBar or timer.showCooldown or false
    else
        config.showBar = false
        config.showSwirl = true
    end
    if config.showBar then
        local bar = timer.timerBars[1]
        config.texture = bar:GetStatusBarTexture():GetTexture()
        config.barColor = { bar:GetStatusBarColor() }
        config.backgroundColor = { bar.background:GetStatusBarColor() }
        config.font = { bar.time:GetFont() }
        config.textColor = { bar.time:GetTextColor() }
    end
    return config
end

local configKeys = { "timeShown", "timeStyle", "showBar", "showSwirl", "texture", "barColor", "backgroundColor", "font", "textColor",
    "dotColor", "glowHeight", "imageWidth" }

local function ConfigSignature(config)
    local parts = {}
    for _, key in ipairs(configKeys) do
        local values = config[key]
        if type(values) ~= "table" then values = { values } end
        for i = 1, #values do
            local value = values[i]
            parts[#parts + 1] = type(value) == "number" and string.format("%.3f", value) or tostring(value)
        end
        parts[#parts + 1] = "|"
    end
    return table.concat(parts, ":")
end

-- builds the container on the next frame if the configuration changed, so several calls in the same frame
-- result in one build
function AuraDisplay:ScheduleBuild()
    if self.buildScheduled then return end
    self.buildScheduled = true
    C_Timer.After(0, function()
        self.buildScheduled = false
        if InCombatLockdown() then
            pendingBuilds[self] = true
            combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            self:Build()
        end
    end)
end

function AuraDisplay:Build()
    if #self.slots == 0 then return end
    local config = self:GetConfig()
    local signature = ConfigSignature(config)
    if self.container and signature == self.signature then return end

    local old = self.container
    if old then
        old:Hide()
        for key, regions in pairs(self.regions) do
            pcall(old.SetAuraSlotEnabled, old, key, false)
            -- the glow animation runs on a frame outside the container (see InitGlowButton)
            if regions.animation then
                regions.animation:Stop()
                animations[regions.animation] = nil
            end
        end
        self.container = nil
    end
    self.regions = {}
    self.config = config
    self.signature = signature

    local parent = self.parent
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not container or type(container.AddAuraSlot) ~= "function" then
        print("TotemTimers: creating aura container failed: " .. tostring(container))
        return
    end
    -- the game sizes the container itself
    container:SetPoint("TOPLEFT", parent, "TOPLEFT")
    container:SetFrameLevel(parent:GetFrameLevel() + 2)
    container:SetUnit(self.unit)

    for _, slot in ipairs(self.slots) do
        local regions = {}
        local frameLevel = parent:GetFrameLevel() + slot.level
        local slotOk, err = pcall(container.AddAuraSlot, container, slot.key, slot.filter, {
            candidateFilters = { includeSpellIDs = slot.spellIDs },
            initializeFrame = function(button)
                self:InitSlotButton(button, frameLevel, regions)
            end,
        })
        if slotOk then
            self.regions[slot.key] = regions
            if self.slotEnabled[slot.key] ~= nil and container:IsAuraSlotEnabled(slot.key) ~= self.slotEnabled[slot.key] then
                container:SetAuraSlotEnabled(slot.key, self.slotEnabled[slot.key])
            end
        else
            print("TotemTimers: aura slot " .. tostring(slot.key) .. " failed: " .. tostring(err))
        end
    end
    self.container = container
end

-- timer bar laid over the first timer bar of the XiTimers timer, built like XiTimersTimerBarTemplate
-- showDuration: the bar shows the remaining duration, otherwise it is full
function AuraDisplay:CreateTimerBar(button, showDuration)
    local config = self.config
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(self.timer.timerBars[1])
    bar:SetStatusBarTexture(config.texture)
    bar:SetStatusBarColor(unpack(config.barColor))

    -- the background is the full bar of XiTimers' background status bar
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    background:SetTexture(config.texture)
    background:SetVertexColor(unpack(config.backgroundColor))

    local time = bar:CreateFontString(nil, "OVERLAY")
    time:SetFontObject("GameFontNormalSmall")
    if config.font[1] then
        time:SetFont(config.font[1], config.font[2], config.font[3])
    end
    time:SetTextColor(unpack(config.textColor))
    time:SetPoint("CENTER", bar, "CENTER")

    if self.maxApplications then
        button:SetApplicationBar(bar, {
            maxApplications = self.maxApplications,
            interpolation = Enum.StatusBarInterpolation.Immediate,
        })
    elseif showDuration then
        button:SetDurationBar(bar, {
            interpolation = Enum.StatusBarInterpolation.Immediate,
            direction = Enum.StatusBarTimerDirection.RemainingTime,
        })
    else
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
    end
    return bar, time
end

-- dot mode: the slot button covers the dot texture and shows only the dot
function AuraDisplay:InitDotButton(button, frameLevel, regions)
    local dot = self.dot
    button:ClearAllPoints()
    button:SetAllPoints(dot)
    button:SetFrameLevel(frameLevel)
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.EnableMouseMotion, button, false)

    local texture = button:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(button)
    if self.tint then
        texture:SetColorTexture(1, 1, 1)
        texture:SetBlendMode("ADD")
        if self.maskAtlas then
            local inset = self.maskInset
            local mask = button:CreateMaskTexture()
            mask:SetAtlas(self.maskAtlas, false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
            mask:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
            texture:AddMaskTexture(mask)
        end
    else
        texture:SetTexture(dot:GetTexture())
    end
    texture:SetVertexColor(unpack(self.config.dotColor))
    regions.dot = texture
end

-- glow mode: the slot button covers the glow region. The stack count can be secret, so the game decides when to
-- glow: an invisible application bar with minApplications = maxApplications = n is only shown by the container
-- from n stacks on (CustomAuraButton ApplyApplicationBar), the glow is its child.
-- The glow is the loop of the action bar's proc glow (atlas UI-HUD-ActionBar-Proc-Loop-Flipbook: 30 frames in 6 rows
-- of 5, one second per loop). Animations stop while their frame is hidden and can't be restarted below a frame with
-- secret visibility (no OnShow scripts there), and a stopped FlipBook animation shows the whole sheet. So each frame
-- of the sheet is made of textures of its own (fixed tex coords, cut into three parts for wide regions, see
-- CreateGlowFrame; only the first frame visible by default: without animation
-- the glow is a static frame), and the frames are stepped through by alpha animations of an always shown frame
-- outside the aura containers (animator), which keep running while the glow is hidden.
local GLOW_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local GLOW_ROWS, GLOW_COLUMNS, GLOW_FRAMES, GLOW_LOOP = 6, 5, 30, 1
-- round version for round Gamepad UI buttons (the game has none, it shows the square glow there too): own flipbook
-- generated by tools/proc_ring_texture.py (the square glow's 30 frames projected onto a circle), in 4 rows of 8 (the
-- last two cells empty), a frame covers 1.4 times the button
local ROUND_GLOW_FILE = "Interface/AddOns/TotemTimers/textures/proc_ring"
local ROUND_GLOW_ROWS, ROUND_GLOW_COLUMNS, ROUND_GLOW_FRAMES = 4, 8, 30

-- steps through the frames: frame i (all its textures) is shown from i/#frames of the loop for one frame's time
local function CreateGlowAnimation(frames)
    local animation = animator:CreateAnimationGroup()
    animation:SetLooping("REPEAT")
    animation:SetToFinalAlpha(true)
    local step = GLOW_LOOP / #frames
    for i, textures in ipairs(frames) do
        for _, texture in ipairs(textures) do
            local show = animation:CreateAnimation("Alpha")
            show:SetTarget(texture)
            show:SetFromAlpha(1)
            show:SetToAlpha(1)
            show:SetStartDelay((i - 1) * step)
            show:SetDuration(step)
            local hide = animation:CreateAnimation("Alpha")
            hide:SetTarget(texture)
            hide:SetFromAlpha(0)
            hide:SetToAlpha(0)
            hide:SetStartDelay(i * step)
            hide:SetDuration(0.001)
        end
    end
    return animation
end

-- one frame of the glow in three parts, so it fits a wide region: the left and right halves of the square frame
-- as ends (as wide as half the glow's height, so they keep their shape) and a thin strip from the frame's center
-- stretched in between (there the glow is only its straight top and bottom edge)
local GLOW_MIDDLE_STRIP = 0.02 -- width of the stretched center strip, share of the frame
local function CreateGlowFrame(glow, file, left, right, top, bottom, capWidth, alpha)
    local center = (left + right) / 2
    local strip = (right - left) * GLOW_MIDDLE_STRIP / 2
    local parts = {}
    local leftCap = glow:CreateTexture(nil, "OVERLAY")
    leftCap:SetPoint("TOPLEFT", glow, "TOPLEFT")
    leftCap:SetPoint("BOTTOMLEFT", glow, "BOTTOMLEFT")
    leftCap:SetWidth(capWidth)
    leftCap:SetTexCoord(left, center - strip, top, bottom)
    local rightCap = glow:CreateTexture(nil, "OVERLAY")
    rightCap:SetPoint("TOPRIGHT", glow, "TOPRIGHT")
    rightCap:SetPoint("BOTTOMRIGHT", glow, "BOTTOMRIGHT")
    rightCap:SetWidth(capWidth)
    rightCap:SetTexCoord(center + strip, right, top, bottom)
    local middle = glow:CreateTexture(nil, "OVERLAY")
    middle:SetPoint("TOPLEFT", leftCap, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", rightCap, "BOTTOMLEFT")
    middle:SetTexCoord(center - strip, center + strip, top, bottom)
    for _, texture in ipairs({ leftCap, middle, rightCap }) do
        texture:SetTexture(file)
        texture:SetAlpha(alpha)
        parts[#parts + 1] = texture
    end
    return parts
end

-- the frames of the round glow, one texture each over the whole glow frame
local function CreateRoundGlowFrames(glow)
    local frames = {}
    for i = 0, ROUND_GLOW_FRAMES - 1 do
        local column, row = i % ROUND_GLOW_COLUMNS, math.floor(i / ROUND_GLOW_COLUMNS)
        local texture = glow:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints(glow)
        texture:SetTexture(ROUND_GLOW_FILE)
        texture:SetTexCoord(column / ROUND_GLOW_COLUMNS, (column + 1) / ROUND_GLOW_COLUMNS,
                row / ROUND_GLOW_ROWS, (row + 1) / ROUND_GLOW_ROWS)
        texture:SetAlpha(i == 0 and 1 or 0)
        frames[#frames + 1] = { texture }
    end
    return frames
end

-- round glow around a frame (round Gamepad UI buttons), shown and hidden with the returned frame; 1.4 times the
-- frame's size like the action bar's glow, follows its size. Runs on the animator like the glow mode, so it keeps
-- running while hidden.
function AuraDisplay.CreateRoundGlow(parent)
    local glow = CreateFrame("Frame", nil, parent)
    glow:SetPoint("CENTER", parent, "CENTER")
    local function UpdateSize()
        local width, height = parent:GetSize()
        glow:SetSize(width * 1.4, height * 1.4)
    end
    UpdateSize()
    parent:HookScript("OnSizeChanged", UpdateSize)
    local ok, animation = pcall(CreateGlowAnimation, CreateRoundGlowFrames(glow))
    if ok then
        animation:Play()
        animations[animation] = true
    end
    glow:Hide()
    return glow
end

function AuraDisplay:InitGlowButton(button, frameLevel, regions)
    local count = self.glow.minApplications
    button:ClearAllPoints()
    button:SetAllPoints(self.glow.region)
    button:SetFrameLevel(frameLevel)
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.EnableMouseMotion, button, false)

    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    bar:SetStatusBarTexture("Interface/Buttons/WHITE8X8")
    bar:SetStatusBarColor(0, 0, 0, 0)
    button:SetApplicationBar(bar, { minApplications = count, maxApplications = count })

    local glow = CreateFrame("Frame", nil, bar)
    -- like the action bar's glow (1.4 times the button size): 20% of the height on each side
    local height = self.config.glowHeight or 20
    local outset = height * 0.2
    glow:SetPoint("TOPLEFT", bar, "TOPLEFT", -outset, outset)
    glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", outset, -outset)
    regions.bar = bar
    regions.glow = glow

    local frames
    if self.glow.round then
        -- round regions are square, no three parts needed
        frames = CreateRoundGlowFrames(glow)
    else
        local atlas = C_Texture.GetAtlasInfo(GLOW_ATLAS)
        local file = atlas and (atlas.file or atlas.filename)
        if not file then return end
        local capWidth = (height + 2 * outset) / 2
        frames = {}
        local cellWidth = (atlas.rightTexCoord - atlas.leftTexCoord) / GLOW_COLUMNS
        local cellHeight = (atlas.bottomTexCoord - atlas.topTexCoord) / GLOW_ROWS
        for i = 0, GLOW_FRAMES - 1 do
            local column, row = i % GLOW_COLUMNS, math.floor(i / GLOW_COLUMNS)
            local left = atlas.leftTexCoord + column * cellWidth
            local top = atlas.topTexCoord + row * cellHeight
            frames[#frames + 1] = CreateGlowFrame(glow, file, left, left + cellWidth, top, top + cellHeight, capWidth,
                    i == 0 and 1 or 0)
        end
    end

    -- targets below a frame with secret visibility might be refused, the glow then stays static
    local ok, animation = pcall(CreateGlowAnimation, frames)
    if ok then
        animation:Play()
        animations[animation] = true
        regions.animation = animation
    end
end

-- image mode: the slot button covers the region and shows the texture over it depending on the stacks, which can be
-- secret, so the game decides: an invisible application bar is shown from n stacks on (minApplications), the image
-- is its child. For exactly n stacks the bar runs from n (empty) to n + 1 (full) and the image is masked to the
-- empty part of the bar (mask from the right end of the bar's fill texture to the bar's right end): with n stacks
-- the image is shown in full, from n + 1 stacks the mask has no area left. Should the mask not be possible, the
-- image is shown from n stacks on (cumulative images, like the Maelstrom textures, still look right then).
-- pulse: a slight scaling pulse, run by the animator (keeps running while the image is hidden).
function AuraDisplay:InitImageButton(button, frameLevel, regions)
    local image = self.image
    local count = image.applications
    button:ClearAllPoints()
    button:SetAllPoints(image.region)
    button:SetFrameLevel(frameLevel)
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.EnableMouseMotion, button, false)

    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetStatusBarTexture("Interface/Buttons/WHITE8X8")
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetAllPoints(button)
    button:SetApplicationBar(bar, {
        minApplications = count,
        maxApplications = image.exact and count + 1 or count,
        interpolation = Enum.StatusBarInterpolation.Immediate,
    })

    local texture = bar:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(button)
    texture:SetTexture(image.texture)
    regions.bar = bar
    regions.image = texture

    if image.exact then
        pcall(function()
            local mask = bar:CreateMaskTexture()
            mask:SetTexture("Interface/Buttons/WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            -- the mask reaches a bar width beyond the bar, so it never has zero width (a zero width mask leaves the
            -- image faintly visible): with the bar full it lies completely right of the image
            mask:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT")
            mask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", (image.region:GetWidth() or 0) * 1.1, 0)
            texture:AddMaskTexture(mask)
            regions.mask = mask
        end)
    end

    if image.pulse then
        local ok, animation = pcall(function()
            local group = animator:CreateAnimationGroup()
            group:SetLooping("BOUNCE")
            local scale = group:CreateAnimation("Scale")
            scale:SetTarget(texture)
            scale:SetScaleFrom(1, 1)
            scale:SetScaleTo(1.06, 1.06)
            scale:SetOrigin("CENTER", 0, 0)
            scale:SetDuration(0.4)
            scale:SetSmoothing("IN_OUT")
            return group
        end)
        if ok then
            regions.animation = animation
            animation:Play()
            animations[animation] = true
        end
    end
end

-- runs inside AddAuraSlot, the only point where the slot button can be set up
function AuraDisplay:InitSlotButton(button, frameLevel, regions)
    if self.image then
        self:InitImageButton(button, frameLevel, regions)
        return
    end
    if self.glow then
        self:InitGlowButton(button, frameLevel, regions)
        return
    end
    if self.dot then
        self:InitDotButton(button, frameLevel, regions)
        return
    end
    local parent = self.parent
    local config = self.config
    button:ClearAllPoints()
    button:SetAllPoints(parent)
    button:SetFrameLevel(frameLevel)
    -- clicks and tooltips go through to the secure timer button
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.EnableMouseMotion, button, false)

    -- the bar (a child frame, level + 1) covers the button's textures, so with iconAboveBar the icon gets a
    -- frame above it, and swipe and texts go above that
    local iconAboveBar = self.iconAboveBar and config.showBar
    local level = button:GetFrameLevel()

    local icon
    if not self.noIcon then
        local iconParent = button
        if iconAboveBar then
            iconParent = CreateFrame("Frame", nil, button)
            iconParent:SetAllPoints(button)
            iconParent:SetFrameLevel(level + 2)
        end
        icon = iconParent:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(parent.icons[1])
        icon:SetTexCoord(parent.icons[1]:GetTexCoord())
        button:SetIcon(icon)
    end

    local texts = CreateFrame("Frame", nil, button)
    texts:SetAllPoints(button)
    texts:SetFrameLevel(level + (iconAboveBar and 3 or 1))

    if config.timeShown and config.showSwirl then
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        if iconAboveBar then cooldown:SetFrameLevel(level + 3) end
        local swipeRegion = icon or parent
        if self.swipeTexture then
            local inset = self.swipeInset
            cooldown:SetPoint("TOPLEFT", swipeRegion, "TOPLEFT", inset, -inset)
            cooldown:SetPoint("BOTTOMRIGHT", swipeRegion, "BOTTOMRIGHT", -inset, inset)
            cooldown:SetSwipeTexture(self.swipeTexture)
            cooldown:SetSwipeColor(0, 0, 0, 0.8)
            cooldown:SetDrawEdge(false)
        else
            cooldown:SetAllPoints(swipeRegion)
        end
        cooldown:SetDrawBling(false)
        cooldown:SetHideCountdownNumbers(true)
        cooldown.noCooldownCount = true
        button:SetDurationCooldown(cooldown)
        texts:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        regions.cooldown = cooldown
    end

    -- the time string shows the time, without time it shows the charges instead of the count string
    local time
    if config.showBar then
        regions.bar, time = self:CreateTimerBar(button, config.timeShown)
        if iconAboveBar then regions.bar:SetFrameLevel(level + 1) end
    else
        -- font strings size to their text, so only the anchor point of the button's own texts is taken
        time = texts:CreateFontString(nil, "OVERLAY")
        time:SetFontObject(TotemTimersButtonTimeFont)
        time:SetPoint("CENTER", self.textAnchor or parent.time, "CENTER")
    end

    local count
    if config.timeShown then
        local timeFormatter = XiTimers.GetTimeFormatter(true, self.forGamePad)
        button:SetDurationText(time, timeFormatter and { textFormatter = timeFormatter } or nil)
        regions.time = time
        count = texts:CreateFontString(nil, "OVERLAY")
        count:SetFontObject(parent.count and parent.count:GetFontObject() or "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
    else
        count = time
    end
    local formatter = not config.timeShown and GetChargesFormatter()
    button:SetApplicationCount(count, formatter and { formatter = formatter } or nil)
    regions.count = count
end

-- spellIDs: set of spell ids ({ [id] = true }) shown in this slot
-- level: frame level above the parent button, slots with a higher level are drawn on top
-- filter: aura filter, default "HELPFUL|PLAYER"
function AuraDisplay:AddSlot(key, spellIDs, level, filter)
    table.insert(self.slots, {
        key = key,
        spellIDs = spellIDs,
        level = level or 2,
        filter = filter or "HELPFUL|PLAYER",
    })
    self:ScheduleBuild()
end

-- enabling slots works on existing slot buttons, so no rebuild is needed
function AuraDisplay:SetSlotEnabled(key, enabled)
    enabled = enabled and true or false
    self.slotEnabled[key] = enabled
    local container = self.container
    if container and self.regions[key] and container:IsAuraSlotEnabled(key) ~= enabled then
        container:SetAuraSlotEnabled(key, enabled)
    end
end

-- rereads the auras of the unit, e.g. after the target changed (the container only marks itself dirty, so this
-- also works in combat)
function AuraDisplay:Refresh()
    local container = self.container
    if container then
        pcall(container.UpdateAllAuras, container)
    end
end

-- the containers don't follow target changes, all displays of "target" are refreshed
local targetFrame = CreateFrame("Frame")
targetFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetFrame:SetScript("OnEvent", function()
    for _, display in ipairs(displays) do
        if display.unit == "target" then
            display:Refresh()
        end
    end
end)

-- time and swipe of all slots, hidden e.g. to show only charges in place of the time
function AuraDisplay:SetTimeShown(shown)
    self.timeShown = shown and true or false
    self:ScheduleBuild()
end

-- color (and optional alpha) of the dot in dot mode. The slot buttons and their textures are forbidden after
-- initializeFrame, so a changed color rebuilds the container (deferred, after combat).
function AuraDisplay:SetDotColor(r, g, b, a)
    a = a or 1
    local c = self.dotColor
    if c[1] == r and c[2] == g and c[3] == b and c[4] == a then return end
    self.dotColor = { r, g, b, a }
    self:ScheduleBuild()
end
