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
--   display:AddSlot("key", { [spellID] = true, ... }, level)
--   display:SetSlotEnabled("key", enabled)
--   display:SetTimeShown(shown)
--   TotemTimers.AuraDisplay.UpdateAll()                          -- after changing settings of the timers

local AuraDisplay = {}
AuraDisplay.__index = AuraDisplay
TotemTimers.AuraDisplay = AuraDisplay

local displays = {}

local function IsAuraContainerAvailable()
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
end

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

function AuraDisplay:new(parent, unit)
    if not IsAuraContainerAvailable() then return end
    local display = setmetatable({}, AuraDisplay)
    display.parent = parent
    -- XiTimers timer of the button, if any
    display.timer = parent.timer
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
    local config = { timeShown = self.timeShown }
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

local configKeys = { "timeShown", "showBar", "showSwirl", "texture", "barColor", "backgroundColor", "font", "textColor" }

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
        for key in pairs(self.regions) do
            pcall(old.SetAuraSlotEnabled, old, key, false)
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

    if showDuration then
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

-- runs inside AddAuraSlot, the only point where the slot button can be set up
function AuraDisplay:InitSlotButton(button, frameLevel, regions)
    local parent = self.parent
    local config = self.config
    button:ClearAllPoints()
    button:SetAllPoints(parent)
    button:SetFrameLevel(frameLevel)
    -- clicks and tooltips go through to the secure timer button
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.EnableMouseMotion, button, false)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(parent.icons[1])
    icon:SetTexCoord(parent.icons[1]:GetTexCoord())
    button:SetIcon(icon)

    local texts = CreateFrame("Frame", nil, button)
    texts:SetAllPoints(button)
    texts:SetFrameLevel(button:GetFrameLevel() + 1)

    if config.timeShown and config.showSwirl then
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints(icon)
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
    else
        -- font strings size to their text, so only the anchor point of the button's own texts is taken
        time = texts:CreateFontString(nil, "OVERLAY")
        time:SetFontObject(TotemTimersButtonTimeFont)
        time:SetPoint("CENTER", parent.time, "CENTER")
    end

    local count
    if config.timeShown then
        button:SetDurationText(time, nil)
        regions.time = time
        count = texts:CreateFontString(nil, "OVERLAY")
        count:SetFontObject(parent.count:GetFontObject() or "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
    else
        count = time
    end
    button:SetApplicationCount(count, nil)
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

-- time and swipe of all slots, hidden e.g. to show only charges in place of the time
function AuraDisplay:SetTimeShown(shown)
    self.timeShown = shown and true or false
    self:ScheduleBuild()
end
