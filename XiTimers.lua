if select(2,UnitClass("player")) ~= "SHAMAN" then return end

if not XiTimers then 
    XiTimers = {}
    XiTimers.version = 200
end

XiTimers.timers = {}
XiTimers.nrOfTimers = 0
XiTimers.__index = XiTimers
XiTimers.updateInterval = 0

local inActiveAlpha = 0.4


local XiTimers = XiTimers
local Timers = XiTimers.timers
local _G = getfenv()

-- shared font of the button time texts (also used by AuraDisplay), font and size settings change this font
local ButtonTimeFont = CreateFont("TotemTimersButtonTimeFont")
ButtonTimeFont:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")

local incombat = false


-- Timers are driven by DurationObjects: self.timers[i] holds the DurationObject of a running timer, nil otherwise.
-- Remaining times of DurationObjects may be secret, so they are never read in Lua.
-- Bars, swirls and text are driven natively, warning visuals through curves
-- and expiry through a cooldown frame acting as sensor (OnCooldownDone).

local CanBindDurationText = (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding
    and C_StringUtil and C_StringUtil.CreateSecondsFormatter) ~= nil

local secondsFormatter
local function GetSecondsFormatter()
    if not secondsFormatter then
        secondsFormatter = C_StringUtil.CreateSecondsFormatter()
        secondsFormatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
        secondsFormatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.Strip)
        secondsFormatter:SetDesiredUnitCount(1)
        secondsFormatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
        secondsFormatter:SetMaxInterval(Enum.SecondsFormatterInterval.Minutes)
        secondsFormatter:SetCanRoundUpLastUnit(true)
    end
    return secondsFormatter
end

-- also used for time texts outside of timers (e.g. GamePad.lua)
XiTimers.CanBindDurationText = CanBindDurationText
XiTimers.GetSecondsFormatter = GetSecondsFormatter

-- curves evaluated on remaining time: "below" up to point seconds, "above" after that
local thresholdCurves = {}
local function GetThresholdCurve(point, below, above)
    local key = below..":"..above
    thresholdCurves[key] = thresholdCurves[key] or {}
    local curve = thresholdCurves[key][point]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Linear)
        curve:AddPoint(0, below)
        if point > 0 then curve:AddPoint(point, below) end
        curve:AddPoint(point + 0.01, above)
        curve:AddPoint(point + 86400, above)
        thresholdCurves[key][point] = curve
    end
    return curve
end

-- warning flash alpha on remaining time: the current buff frame warning alpha up to point seconds, "above" (default 0) after that.
-- The warning alpha is quantized to limit the number of cached curves.
local function GetFlashAlpha(durObj, point, above)
    local alpha = BuffFrame.BuffAlphaValue or BuffFrame.AuraContainer:GetAuraWarningAlphaForDuration(0)
    alpha = floor(alpha * 50 + 0.5) / 50
    return durObj:EvaluateRemainingDuration(GetThresholdCurve(point, alpha, above or 0))
end

local emptyDuration
local function GetEmptyDuration()
    emptyDuration = emptyDuration or C_DurationUtil.CreateDuration()
    return emptyDuration
end

-- sensors are not parented to the timer buttons so they keep running while buttons are hidden
local sensorParent
local function CreateExpirySensor()
    if not sensorParent then
        sensorParent = CreateFrame("Frame", nil, WorldFrame)
        sensorParent:SetSize(1, 1)
        sensorParent:SetPoint("BOTTOMLEFT")
    end
    local sensor = CreateFrame("Cooldown", nil, sensorParent)
    sensor:SetAllPoints(sensorParent)
    sensor:SetDrawSwipe(false)
    sensor:SetDrawEdge(false)
    sensor:SetDrawBling(false)
    sensor:SetHideCountdownNumbers(true)
    sensor.noCooldownCount = true
    sensor.noOCC = true
    return sensor
end


local nextUpdate = 0

function XiTimers.UpdateTimers(self,elapsed) 
    if XiTimers.updateInterval > 0 then nextUpdate = nextUpdate + elapsed end
    if nextUpdate >= XiTimers.updateInterval then
        nextUpdate = nextUpdate - XiTimers.updateInterval
        for i=1,XiTimers.nrOfTimers do
            if Timers[i].active and Timers[i].running > 0 or Timers[i].barCurve then Timers[i]:Update(elapsed) end
        end        
    end
end

function XiTimers.AddSpecialActionBarDriver(button)
    RegisterStateDriver(button, "petbattle", "[petbattle][overridebar][possessbar][vehicleui] active; none")
    RegisterStateDriver(button, "combat", "[combat] active; none")
    button:WrapScript(button, "OnAttributeChanged", [[
			if not self:GetAttribute("active") then return end
			if name == "state-petbattle" then
				if value == "active" then
					self:Hide()
				elseif not self:GetAttribute("HideOOC") then
					self:Show()
				end
			elseif name == "state-combat" then
				if value == "active" then
					self:Show()
				elseif self:GetAttribute("HideOOC") then
					self:Hide()
				end
			end
		]])
end


function XiTimers:new(nroftimers, unclickable)
	local self = {}
	setmetatable(self, XiTimers)
	XiTimers.nrOfTimers = XiTimers.nrOfTimers + 1
    self.nr = XiTimers.nrOfTimers
	self.active = false
	self.running = 0
    self.unclickable = unclickable
    self.numButtonTimers = 1
	
	if unclickable then
        self.button = CreateFrame("Button", "XiTimers_Timer"..XiTimers.nrOfTimers, UIParent, "XiTimersUnsecureTemplate")
    else
        self.button = CreateFrame("Button", "XiTimers_Timer"..XiTimers.nrOfTimers, UIParent, "XiTimersTemplate")
		XiTimers.AddSpecialActionBarDriver(self.button)
    end
    self.button:ClearAllPoints()
	self.button:SetPoint("CENTER", UIParent, "CENTER")
	self.button.timer = self
	
	self.button.action = 0
    if self.button.UpdateArrowShown then self.button:UpdateArrowShown() end
    --self.button:SetCheckedTexture(nil)
	--self.button.SetCheckedTexture = function() end
    --self.button.SetChecked = function() end
    --self.button.GetChecked = function() return false end
    --self.button.SetDisabledCheckedTexture = function() end

    --[[for _, texture in pairs({"SpellHighlightTexture", "PushedTexture", "NewActionTexture", "HighlightTexture"}) do
        if self.button[texture] then
            self.button[texture]:SetTexture(nil)
            self.button[texture]:Hide()
        end
    end
    if self.button.SpellHighlightAnim then
        self.button.SpellHighlightAnim:Stop()
    end]]

    local regions = {self.button:GetRegions()}
    for i, region in ipairs(regions) do
        if not region:GetName() then
           region:SetTexture(nil)
           region:Hide()
        end
    end

    
	self.button.unclickable = unclickable
	self.button.element = XiTimers.nrOfTimers
    
	
	self.nrOfTimers = nroftimers
	self.timers = {}
    self.expirySensors = {}
    self.sensorExpired = {}
    self.textBindings = {}
	self.timerBars = {}
	self.button.icons = {}

	for i=1,nroftimers do
		self.timerBars[i] = CreateFrame("StatusBar", "XiTimers_TimerBar"..XiTimers.nrOfTimers.."_"..i, self.button, "XiTimersTimerBarTemplate")
        self.timerBars[i].background = _G["XiTimers_TimerBar"..XiTimers.nrOfTimers.."_"..i.."Background"]
        self.timerBars[i].time = _G["XiTimers_TimerBar"..XiTimers.nrOfTimers.."_"..i.."Time"]
        self.timerBars[i].icon = _G["XiTimers_TimerBar"..XiTimers.nrOfTimers.."_"..i.."Icon"]
        self.timerBars[i]:SetPoint("TOP", self.button, "BOTTOM")
		self.button.icons[i] = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Icon"..((i>1) and i or "")]

        if self.button.icons[i] then
            local flash = self.button.icons[i]
            flash.animation = flash:CreateAnimationGroup()
            flash.animation:SetLooping("NONE")
            flash.flashAnim = flash.animation:CreateAnimation()
            flash.flashAnim:SetDuration(15)
            flash.flashAnim.flash = flash
            flash.flashAnim:SetScript("OnPlay", function(self) self.flash:Show() end)
            flash.flashAnim:SetScript("OnUpdate", function(self) self.flash:SetAlpha(BuffFrame.BuffAlphaValue or BuffFrame.AuraContainer:GetAuraWarningAlphaForDuration(0)) end)
			flash.flashAnim:SetScript("OnStop", function(self) self.flash:SetAlpha(inActiveAlpha) end)
			flash.flashAnim:SetScript("OnFinished", function(self) self.flash:SetAlpha(inActiveAlpha) end)
        end
		self:SetIconAlpha(self.button.icons[i], 0.4)
	end

    local flash = self.button.Flash
    flash:SetAllPoints(self.button)
    flash.animation = flash:CreateAnimationGroup()
    flash.animation:SetLooping("NONE")
    flash.flashAnim = flash.animation:CreateAnimation()
    flash.flashAnim:SetDuration(15)
    flash.flashAnim.flash = flash
    flash.flashAnim:SetScript("OnPlay", function(self) self.flash:Show() end)
    flash.flashAnim:SetScript("OnFinished", function(self) self.flash:Hide() end)
    flash.flashAnim:SetScript("OnStop", function(self) self.flash:Hide() end)
    flash.flashAnim:SetScript("OnUpdate", function(self) self.flash:SetAlpha(BuffFrame.BuffAlphaValue or BuffFrame.AuraContainer:GetAuraWarningAlphaForDuration(0)) end)
    
    
    self.timeColor = {r=1,g=1,b=1,a=1}
	self.button.icons[1]:Show()
	self.timerBarPos = "BOTTOM"
	self.timeSpacing = 0
	self.spacing = 5
	self.timeStyle = "mm:ss"
    self.OOCAlpha = 1
	self.maxAlpha = 1
	self.warningMsgs = {}
    self.warningSpells = {}
	self.expirationMsgs = {}
	self.earlyExpirationMsgs = {}
    self.warningIcons = {}
	self.events = {}
	self.playerEvents = {}
	self.button.count = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Count"]
	self.button.cooldown = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Cooldown"]
	self.button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
	self.button.cooldown:SetHideCountdownNumbers(true)
    self.button.cooldown:SetAllPoints(self.button)
	self.button.miniIcon = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."MiniIcon"]
    self.button.miniIconFrame = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Mini"]
    self.button.bar = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Bar"]
    self.button.bar:SetStatusBarColor(0.6, 0.6, 1, 0.7)
    self.button.hotkey = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."HotKey"]
    self.button.rangeCount = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."RangeCount"]
	self.button.normalTexture = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."NormalTexture"]
    local frame = CreateFrame("Frame", nil, self.button)
    frame:Show()
    frame:SetAllPoints(self.button)
    self.button.time = frame:CreateFontString(self.button:GetName().."Time", 'OVERLAY')
    self.button.time:SetPoint("CENTER",0,1)
    self.button.time:SetFontObject(ButtonTimeFont)
    frame:SetFrameLevel(frame:GetFrameLevel()+10)
    self.button.time:Hide()
    --self.button.cooldown:SetFrameLevel(self.button.cooldown:GetFrameLevel()-1)
    self.button.cooldown.noCooldownCount = true
    self.button.cooldown.noOCC = true
    self.button:SetAttribute("num", self.nr)
    self.rangeCheckCount = 0
    self.manaCheckCount = 0
	self.warningPoint = 10

    self:HideNormalTexture()

    self.animation = XiTimersAnimations:new(self.button)
    
	self.anchors = {}
	self.anchorchilds = {}
	
	--self.button:SetScript("OnDragStart", XiTimers.StartMoving)
	self.button:SetScript("OnDragStop", XiTimers.StopMoving)
    self.button:SetAttribute("_ondragstart", [[control:CallMethod("StartMove")]])
    --self.button:SetAttribute("_ondragstop", [[control:CallMethod("StopMoving")]])
    self.button.StartMove = XiTimers.StartMoving
    self.button.StopMove = XiTimers.StopMoving
	self.button:RegisterForDrag("LeftButton")

    self.button:SetAttribute("useOnKeyDown", 1)

	XiTimers.HookTooltips(self.button)
    
	table.insert(Timers, self)

    self.button:SetAttribute("_onattributechanged", [[ 
        if name=="state-invehicle" then
            if value == "show" and self:GetAttribute("active") then
                self:Show()
            else
                self:Hide()
            end
        end
        ]])

    self.button:Hide()
	
	return self
end

-- timer functions
local IsSpellInRange = IsSpellInRange
local IsUsableSpell = IsUsableSpell

function XiTimers:Update(elapsed)
	local timers = self.timers
	for i=1,self.nrOfTimers do
        if timers[i] then
            self:UpdateDurationVisuals(i, timers[i])
		end
	end
    if self.barCurve then
        self.button.bar:SetValue(self.barTimer:EvaluateElapsedDuration(self.barCurve))
    end
end


function XiTimers:Activate()
	self.active = true
	for _,event in pairs(self.events) do
		self.button:RegisterEvent(event)
	end
	for _, event in pairs(self.playerEvents) do
		self.button:RegisterUnitEvent(event, "player")
	end
	if not self.hideInactive and (not self.HideOOC or InCombatLockdown()) and not self.ActiveWhileHidden then
        self.button:Show()
    end	
	self.button:SetAttribute("active", true)
	if self.ActiveWhileHidden then self.button:Hide() self.button:SetAttribute("active", false) end
	 if self.rangeCheck or self.manaCheck then
		self:AddRangeCheck()
	end
end

function XiTimers:Deactivate()
	self.active = false
	self.button:UnregisterAllEvents()
	self.button:Hide()
    self.button:SetAttribute("active", false)
	self:RemoveRangeCheck()
end

function XiTimers:Start(timer, durObj)
	if self.timers[timer] then
        -- cleared before the sensor so a done event of the old duration doesn't stop the timer
        self.timers[timer] = nil
        self:ClearDurationObject(timer)
    else
		self.running = self.running + 1
	end
    self.timers[timer] = durObj
	self.button.Flash.animation:Stop()
	if self.button.icons[timer] then self.button.icons[timer].animation:Stop() end
	local timerbar = self.timerBars[timer]

    timerbar.time:SetText("")
    self.button.time:SetText("")
    timerbar:SetTimerDuration(durObj, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
    if not self.expirySensors[timer] then
        self.expirySensors[timer] = CreateExpirySensor()
        self.expirySensors[timer]:SetScript("OnCooldownDone", function() self:DurationExpired(timer) end)
    end
    self.expirySensors[timer]:SetCooldownFromDurationObject(durObj)

    if timer > 1 then
        if (timer > 1 and (not self.nobars or (self.nobars and not self.timerOnButton))) then
            self:ShowTimerBar(timer)
        else
            self:HideTimerBar(timer)
        end
        self:BindDurationText(timer)
    else
        self:ShowTimer()
        if (self.showCooldown or self.timerOnButton) and not self.prohibitCooldown then
            self.button.cooldown:SetCooldownFromDurationObject(durObj)
        else
            self.button.cooldown:Hide()
        end
        if self.procFlash then
            self.button.bar:Show()
            self.button.bar:SetValue(0)
        elseif not self.barTimer then
            self.button.bar:Hide()
        end
        self.playedWarningStopPulse = false
    end

    if not self.dontAlpha then self:SetIconAlpha(self.button.icons[timer], self.maxAlpha) end
    if self.reverseAlpha then self:SetIconAlpha(self.button.icons[timer],  self.alpha or 0.4) end

    self.flashIsAnimating = false
    self:StartDurationFlash(timer)
    --self.button.bar:SetValue(0)
    self:SetTimerBarPos(self.timerBarPos, true)
    if timer == 1 and self.hideInactive then
        self.button:Show()
    end
end

function XiTimers:Stop(timer)
	if not self.timers[timer] then return end
	self.running = self.running - 1
	if self.running < 0 then self.running = 0 end
	self.timers[timer] = nil
	local timerbar = self.timerBars[timer]
    if not self.stopQuiet then
        if not self.sensorExpired[timer] then
            if self.earlyExpirationMsgs[timer] then
                self:PlayWarning(self.earlyExpirationMsgs[timer], self.warningSpells[timer], self.warningIcons[timer])
                self.earlyExpirationMsgs[timer] = nil
            end
        elseif self.expirationMsgs[timer] then
            self:PlayWarning(self.expirationMsgs[timer], self.warningSpells[timer], self.warningIcons[timer])
            self.expirationMsgs[timer] = nil
        end
        -- the warning point can't be detected for DurationObjects, so StopPulseAtWarning timers pulse on stop, too
        if self.StopPulse and timer == 1 then
            self.animation:SetTexture(self.button.icons[1]:GetTexture())
            self.animation:Play()
        end
    end
    self.stopQuiet = false
    self:ClearDurationObject(timer)
	timerbar.time:SetText("")
    timerbar:SetValue(0)
    self:HideTimerBar(timer)
    if timer == 1 then
        self.button.time:Hide()
        self.button.cooldown:Hide()
    end 
    if not self.dontAlpha then self:SetIconAlpha(self.button.icons[timer], self.alpha or 0.4) end
    if self.reverseAlpha then self:SetIconAlpha(self.button.icons[timer],self.maxAlpha) end
    if self.procFlash and timer == 1 then self:StopBarTimer() end
    self:SetTimerBarPos(self.timerBarPos, true)
    if timer == 1 and self.hideInactive then
        self.button:Hide()
    end
    -- self:SetOutOfRange(false)
end

function XiTimers:ShowTimer()
    self.button.time:Hide()
    if not self.hideTime then
        if not self.timerOnButton or self.forceBar then
            self.button.time:Hide()
            self:ShowTimerBar(1)
        else
            self.button.time:SetTextColor(self.timeColor.r, self.timeColor.g, self.timeColor.b, self.timeColor.a)
            self:HideTimerBar(1)
            self.button.time:Show()
        end
    else
        self.button.time:Hide()
        self:HideTimerBar(1)
    end
    self:BindDurationText(1)
end


-- DurationObject timers

function XiTimers:DurationExpired(timer)
    if not self.timers[timer] then return end
    self.sensorExpired[timer] = true
    self:Stop(timer)
end

function XiTimers:ClearDurationObject(timer)
    self.sensorExpired[timer] = nil
    if self.expirySensors[timer] then self.expirySensors[timer]:Clear() end
    if self.textBindings[timer] then self.textBindings[timer]:SetEnabled(false) end
    self.timerBars[timer]:SetTimerDuration(GetEmptyDuration())
    if timer == 1 then self.button.cooldown:SetHideCountdownNumbers(true) end
    if self.flashingDuration == timer then
        self.flashingDuration = nil
        if self.flashIconAlpha then
            self.button.icons[timer]:SetAlpha(self.flashIconAlpha)
            self.flashIconAlpha = nil
        else
            self.button.Flash:Hide()
            self.button.Flash:SetAlpha(1)
        end
    end
end

-- binds the time text of a DurationObject timer to its font string
function XiTimers:BindDurationText(timer)
    local durObj = self.timers[timer]
    local binding = self.textBindings[timer]
    local fontString
    if durObj and not self.hideTime then
        if timer > 1 or not self.timerOnButton or self.forceBar then
            fontString = self.timerBars[timer].time
        else
            fontString = self.button.time
        end
    end
    if timer == 1 then
        -- without text bindings, the swirl's countdown numbers replace the button time
        self.button.cooldown:SetHideCountdownNumbers(CanBindDurationText or fontString ~= self.button.time)
    end
    if not fontString or not CanBindDurationText then
        if binding then binding:SetEnabled(false) end
        return
    end
    if not binding then
        binding = C_DurationUtil.CreateDurationTextBinding()
        binding:SetFormatter(GetSecondsFormatter())
        binding:SetExpiredText("")
        binding:SetZeroDurationText("")
        self.textBindings[timer] = binding
    end
    binding:SetFontString(fontString)
    binding:SetDuration(durObj)
    binding:SetEnabled(true)
end

-- the warning flash runs for the whole duration, its alpha is the buff frame warning alpha gated by a curve on the remaining time.
-- With flashRed the red Flash texture is shown, otherwise the icon fades and keeps its normal alpha (self.flashIconAlpha)
-- above the warning point. The flashAnim animations aren't used here, their OnUpdate would overwrite the alpha.
function XiTimers:StartDurationFlash(timer)
    if timer > self.numButtonTimers or self.dontFlash then return end
    self.flashingDuration = timer
    if self.flashRed then
        local flash = self.button.Flash
        flash.animation:Stop()
        flash:SetAlpha(GetFlashAlpha(self.timers[timer], self.warningPoint))
        flash:Show()
    else
        local icon = self.button.icons[timer]
        self.flashIconAlpha = icon:GetAlpha()
        icon:SetAlpha(GetFlashAlpha(self.timers[timer], self.warningPoint, self.flashIconAlpha))
    end
end

function XiTimers:UpdateDurationVisuals(timer, durObj)
    if self.flashingDuration == timer then
        if self.flashIconAlpha then
            self.button.icons[timer]:SetAlpha(GetFlashAlpha(durObj, self.warningPoint, self.flashIconAlpha))
        else
            self.button.Flash:SetAlpha(GetFlashAlpha(durObj, self.warningPoint))
        end
    end
    if timer == 1 and self.nr < 8 and not self.hideTime and self.timerOnButton and not self.forceBar then
        -- red button time for the last 10 seconds
        local color = self.timeColor
        self.button.time:SetTextColor(
            durObj:EvaluateRemainingDuration(GetThresholdCurve(10, 1, color.r)),
            durObj:EvaluateRemainingDuration(GetThresholdCurve(10, 0, color.g)),
            durObj:EvaluateRemainingDuration(GetThresholdCurve(10, 0, color.b)),
            color.a)
    end
end


-- self.barTimer holds the DurationObject of a running bar timer (nil otherwise).
-- Without curve the bar is driven natively like the timers. With curve the bar value is set each update
-- to the curve evaluated on the elapsed duration in seconds, the curve has to return values from 0 to 1.
function XiTimers:StartBarTimer(durObj, curve)
    local bar = self.button.bar
    self.barTimer = durObj
    self.barCurve = curve
    if curve then
        bar:SetTimerDuration(GetEmptyDuration())
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(durObj:EvaluateElapsedDuration(curve))
    else
        bar:SetTimerDuration(durObj, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
    end
    bar:Show()
    if not self.barSensor then
        self.barSensor = CreateExpirySensor()
        self.barSensor:SetScript("OnCooldownDone", function()
            if self.barTimer then self:StopBarTimer() end
        end)
    end
    self.barSensor:SetCooldownFromDurationObject(durObj)
end

function XiTimers:StopBarTimer()
    -- cleared before the sensor so its done event is ignored
    self.barTimer = nil
    self.barCurve = nil
    if self.barSensor then self.barSensor:Clear() end
    self.button.bar:SetTimerDuration(GetEmptyDuration())
    self.button.bar:SetValue(0)
    self.button.bar:Hide()
end


function XiTimers:SetOutOfRange(outOfRange)
    self.outOfRange = outOfRange
    self:UpdateButtonColor()
end

function XiTimers:SetOutOfMane(outOfMana)
    self.outOfMana = outOfMana
    self:UpdateButtonColor()
end

function XiTimers:UpdateButtonColor()
    if self.outOfRange then
        self.button.icons[1]:SetVertexColor(1,0,0)
    elseif self.outOfMana then
        self.button.icons[1]:SetVertexColor(0.5,0.5,2)
    else
        self.button.icons[1]:SetVertexColor(1,1,1)
    end
end

if ActionButton_ShowOverlayGlow then
    function XiTimers:ShowOverlayGlow()
        ActionButton_ShowOverlayGlow(self.button)
    end

    function XiTimers:HideOverlayGlow()
        ActionButton_HideOverlayGlow(self.button)
    end
elseif ActionButtonSpellAlertManager then
    function XiTimers:ShowOverlayGlow()
        ActionButtonSpellAlertManager:ShowAlert(self.button)
    end

    function XiTimers:HideOverlayGlow()
        ActionButtonSpellAlertManager:HideAlert(self.button)
    end
end

    function XiTimers:StartMoving()
        if self.timer.locked then return end
        if self.anchorframe and not self.timer.savePos then
            self.anchorframe:StartMoving()
        else
            self:StartMoving()
        end
    end

    function XiTimers:StopMoving()
        if self.anchorframe and not self.timer.savePos then
            self.anchorframe:StopMovingOrSizing()
        else
            self:StopMovingOrSizing()
        end
        if XiTimers.SaveFramePositions then XiTimers.SaveFramePositions() end
        self.timer:SetTimerBarPos(self.timer.timerBarPos, true)
    end

    function XiTimers:SetIconAlpha(icon, alpha)
        if icon then
            icon:SetAlpha(alpha)
        end
    end

    function XiTimers:SetAlpha(alpha)
        self.button:SetAlpha(alpha)
    end

    function XiTimers:SetReverseAlpha(alpha)
        self.reverseAlpha = alpha
        if alpha then
            for i=1, self.nrOfTimers do
                self.button.icons[i]:SetAlpha(self.maxAlpha)
            end
        end
    end


    function XiTimers:HideTimerBar(nr)
        self.timerBars[nr].background:Hide()
        self.timerBars[nr].background:SetValue(0)
        ---self.timerBars[nr].icon:Hide()
        self.timerBars[nr]:Hide()
    end

    function XiTimers:ShowTimerBar(nr)
        self.timerBars[nr]:Show()
        self.timerBars[nr].background:Show()
        self.timerBars[nr].background:SetValue(1)
    end

    -- display functions

    function XiTimers:SetTimerBarPos(side, notReanchor)
        if not side then return end
        self.timerBarPos = side

        local TimerBars = self.timerBars
        local nrOfTimers = self.nrOfTimers

        for i=1, nrOfTimers do
            TimerBars[i]:ClearAllPoints()
            TimerBars[i].icon:ClearAllPoints()
        end
        if side == "RIGHT" then
            for i=2,nrOfTimers do
                TimerBars[i].icon:SetPoint("LEFT", TimerBars[i], "RIGHT", -4, 0)
            end
        else
            for i=2,nrOfTimers do
                TimerBars[i].icon:SetPoint("RIGHT", TimerBars[i], "LEFT", 4, 0)
            end
        end
        local activetimers = 1
        if side == "LEFT" then
            local lastactive = 1
            for i=2,nrOfTimers do
                TimerBars[i]:SetPoint("TOP", TimerBars[lastactive], "BOTTOM") -- set all, but only active ones will be seen so they can lay atop one another
                if self.timers[i] then
                    lastactive = i
                    activetimers = activetimers + 1
                end
            end
            TimerBars[1]:SetPoint("RIGHT", self.button, "LEFT", -self.timeSpacing, TimerBars[1]:GetHeight()*TimerBars[1]:GetEffectiveScale()/2*(activetimers-1))
        elseif side == "RIGHT" then
            local lastactive = 1
            for i=2,nrOfTimers do
                TimerBars[i]:SetPoint("TOP", TimerBars[lastactive], "BOTTOM")
                if self.timers[i] then
                    lastactive = i
                    activetimers = activetimers + 1
                end
            end
            TimerBars[1]:SetPoint("LEFT", self.button, "RIGHT", self.timeSpacing, TimerBars[1]:GetHeight()*TimerBars[1]:GetEffectiveScale()/2*(activetimers-1))
        elseif side == "TOP" then
            if TotemTimers.ActiveProfile.ShowCooldowns and self.nr < 5 and (TotemTimers.ActiveProfile.Arrange == "vertical" or TotemTimers.ActiveProfile.Arrange == "box") then
                TimerBars[1]:SetPoint("BOTTOM", self.button, "TOP", 0, self.timeSpacing)
                local active = 0
                local firstactive = 0
                for i = 2, nrOfTimers do
                    if self.timers[i] then
                        active = active + 1
                        if firstactive == 0 then firstactive = i end
                    end
                end
                if active > 0 then
                    local left = self.button:GetLeft() < WorldFrame:GetWidth()/2
                    if TotemTimers.ActiveProfile.Arrange == "box" and self.actnr then
                        left = self.actnr == 2 or self.actnr == 4
                    end
                    for i=2, nrOfTimers do
                        TimerBars[i].icon:ClearAllPoints()
                        if left then
                            TimerBars[i].icon:SetPoint("LEFT", TimerBars[i], "RIGHT", -4, 0)
                        else
                            TimerBars[i].icon:SetPoint("RIGHT", TimerBars[i], "LEFT", 4, 0)
                        end
                    end
                    if left then
                        TimerBars[firstactive]:SetPoint("LEFT", self.button, "RIGHT",
                                self.timeSpacing, TimerBars[firstactive]:GetHeight()*TimerBars[firstactive]:GetEffectiveScale()/2*(active-1))
                    else
                        TimerBars[firstactive]:SetPoint("RIGHT", self.button, "LEFT",
                                -self.timeSpacing, TimerBars[firstactive]:GetHeight()*TimerBars[firstactive]:GetEffectiveScale()/2*(active-1))
                    end
                    local last = firstactive
                    for i = firstactive+1, nrOfTimers do
                        TimerBars[i]:SetPoint("TOP", TimerBars[last], "BOTTOM")
                        if self.timers[i] then
                            last = i
                        end
                    end
                    for i = 2, firstactive-1 do
                        TimerBars[i]:SetPoint("TOP", self.button, "BOTTOM")
                    end
                end
            else
                local lastactive = 1
                TimerBars[1]:SetPoint("BOTTOM", self.button, "TOP", 0, self.timeSpacing)
                for i=2, nrOfTimers do
                    TimerBars[i]:SetPoint("BOTTOM", TimerBars[lastactive], "TOP")
                    if self.timers[i] then
                        lastactive = i
                    end
                end
            end
        elseif side == "BOTTOM" then
            if TotemTimers.ActiveProfile.ShowCooldowns and self.nr < 5 and (TotemTimers.ActiveProfile.Arrange == "vertical" or TotemTimers.ActiveProfile.Arrange == "box") then
                TimerBars[1]:SetPoint("TOP", self.button, "BOTTOM", 0, -self.timeSpacing)
                local active = 0
                local firstactive = 0
                for i = 2, nrOfTimers do
                    if self.timers[i] then
                        active = active + 1
                        if firstactive == 0 then firstactive = i end
                    end
                end
                if active > 0 then
                    local left = self.button:GetLeft() < WorldFrame:GetWidth()/2
                    if TotemTimers.ActiveProfile.Arrange == "box" and self.actnr then
                        left = self.actnr == 2 or self.actnr == 4
                    end
                    for i=2, nrOfTimers do
                        TimerBars[i].icon:ClearAllPoints()
                        if left then
                            TimerBars[i].icon:SetPoint("LEFT", TimerBars[i], "RIGHT", -4, 0)
                        else
                            TimerBars[i].icon:SetPoint("RIGHT", TimerBars[i], "LEFT", 4, 0)
                        end
                    end
                    if left then
                        TimerBars[firstactive]:SetPoint("LEFT", self.button, "RIGHT",
                                self.timeSpacing, TimerBars[firstactive]:GetHeight()*TimerBars[firstactive]:GetEffectiveScale()/2*(active-1))
                    else
                        TimerBars[firstactive]:SetPoint("RIGHT", self.button, "LEFT",
                                -self.timeSpacing, TimerBars[firstactive]:GetHeight()*TimerBars[firstactive]:GetEffectiveScale()/2*(active-1))
                    end
                    local last = firstactive
                    for i = firstactive+1, nrOfTimers do
                        TimerBars[i]:SetPoint("TOP", TimerBars[last], "BOTTOM")
                        if self.timers[i] then
                            last = i
                        end
                    end
                    for i = 2, firstactive-1 do
                        TimerBars[i]:SetPoint("TOP", self.button, "BOTTOM")
                    end
                end
            else
                local lastactive = 1
                TimerBars[1]:SetPoint("TOP", self.button, "BOTTOM", 0, -self.timeSpacing)
                for i=2, nrOfTimers do
                    TimerBars[i]:SetPoint("TOP", TimerBars[lastactive], "BOTTOM")
                    if self.timers[i] then
                        lastactive = i
                    end
                end
            end
        end
        if not InCombatLockdown() and not notReanchor then self:Reanchor() end
    end

    function XiTimers:GetBorder(side)
        local timerBarPos = self.timerBarPos
        if side == "TOP" and timerBarPos == "TOP" or side == "BOTTOM" and timerBarPos == "BOTTOM" then
            local height = self.timerBars[1]:GetHeight()*self.timerBars[1]:GetEffectiveScale()
            if self.nr > 5 or TotemTimers.ActiveProfile.Arrange == "horizontal" then
                height = height * self.nrOfTimers
            end
            return (self.timerOnButton and not self.forceBar) and 0 or self.timeSpacing + height
        elseif ((side == "LEFT" and timerBarPos == "LEFT" or side == "RIGHT" and timerBarPos == "RIGHT") and ((self.nrOfTimers>1 and TotemTimers.ActiveProfile.ShowCooldowns) or not self.timerOnButton or self.forceBar))
                or (self.nr < 5 and TotemTimers.ActiveProfile.ShowCooldowns and TotemTimers.ActiveProfile.Arrange == "vertical" and self.nrOfTimers > 1 and
                ((side == "LEFT" and self.nrOfTimers > 1 and TotemTimersFrame:GetLeft() > WorldFrame:GetWidth()/2)
                        or (side == "RIGHT" and self.nrOfTimers > 1 and TotemTimersFrame:GetLeft() < WorldFrame:GetWidth()/2)))
        then
            return (self.timeSpacing + self.timerBars[1]:GetWidth()*self.timerBars[1]:GetEffectiveScale())
        end
        return 0
    end


    function XiTimers:SetWidth(width)
        self.button:SetWidth(width)
    end

    function XiTimers:SetHeight(height)
        self.button:SetHeight(height)
    end

    function XiTimers:SetFont(font)
        for _,timerbar in pairs(self.timerBars) do
            local _,height = timerbar.time:GetFont()
            timerbar.time:SetFont(font, height)
        end
    end

    function XiTimers:SetTimeHeight(height)
        for _,timerbar in pairs(self.timerBars) do
            timerbar:SetHeight(height)
            timerbar.background:SetHeight(height)
            local font = timerbar.time:GetFont()
            timerbar.time:SetFont(font, height)
        end
        self:Reanchor()
    end

    function XiTimers:SetTimeWidth(width)
        for _,timerbar in pairs(self.timerBars) do
            timerbar:SetWidth(width)
            timerbar.background:SetWidth(width)
            timerbar.time:SetWidth(width)
        end
        self:Reanchor()
    end

    function XiTimers:SetScale(scale)
        self.button:SetScale(scale)
        self:SetTimerBarPos(self.timerBarPos)
        --self:Reanchor()
    end

    function XiTimers:SetBarTexture(texture)
        for _,bar in pairs(self.timerBars) do
            bar:SetStatusBarTexture(texture)
            bar.background:SetStatusBarTexture(texture)
        end
    end

    function XiTimers:SetBarColor(r,g,b,a)
        if not a then a = 1 end
        local backgroundAlpha = math.max(0, a - 0.6)
        for _,bar in pairs(self.timerBars) do
            bar:SetStatusBarColor(r,g,b,a)
            bar.background:SetStatusBarColor(r,g,b,backgroundAlpha)
        end
    end


    --allowed position combinations are: CENTER/CENTER, LEFT/RIGHT, RIGHT/LEFT, TOP/BOTTOM, BOTTOM/TOP

    local CounterPositions = {
        CENTER = "CENTER",
        LEFT = "RIGHT",
        RIGHT = "LEFT",
        TOP = "BOTTOM",
        BOTTOM = "TOP",
        TOPLEFT = "BOTTOM",
        TOPRIGHT = "BOTTOM",
    }

    local DirectionXMult = {
        CENTER = 0,
        LEFT = 1,
        RIGHT = -1,
        TOP = 0,
        BOTTOM = 0,
        TOPRIGHT = -1,
        TOPLEFT = 1,
        BOTTOMLEFT = 1,
        BOTTOMRIGHT = -1,
    }

    local DirectionYMult = {
        CENTER = 0,
        LEFT = 0,
        RIGHT = 0,
        TOP = -1,
        BOTTOM = -1,
        TOPRIGHT = -1,
        TOPLEFT = -1,
        BOTTOMRIGHT = -1,
        BOTTOMLEFT = 0.5,
    }


    function XiTimers:SetPoint(pos, relframe, relpos, halfspace)
        local relborder = 0
        if relframe.button then
            if not relpos then relborder = relframe:GetBorder(CounterPositions[pos])
            else relborder = relframe:GetBorder(relpos) end
            relframe = relframe.button
        end
        local borderx = self:GetBorder(pos)+relborder
        local bordery = borderx
        --hack for anchoring TOPRIGHT or TOPLEFT to BOTTOM, maybe change it account for all anchors someday if needed
        if relpos == "BOTTOM" then borderx = 0 end
        self.button:ClearAllPoints()
        if not relpos then relpos = CounterPositions[pos] end
        local spacingx = self.spacing
        if halfspace then spacingx = spacingx / 2 end
        local spacingy = self.spacing
        self.button:SetPoint(pos, relframe, relpos, (spacingx+borderx)*DirectionXMult[pos], (spacingy+bordery)*DirectionYMult[pos])
    end

    -- anchors this timer to another
    function XiTimers:Anchor(timer, point, relpoint, halfspace)
        table.insert(self.anchors, {timer = timer, point = point, relpoint = relpoint, halfspace = halfspace})
        table.insert(timer.anchorchilds, self)
        self:SetPoint(point, timer, relpoint, halfspace)
    end

    -- updates the positions of all frames anchored to this timer
    function XiTimers:Reanchor()
        for _, anchor in pairs(self.anchors) do
            self:SetPoint(anchor.point, anchor.timer, anchor.relpoint, anchor.halfspace)
        end
        for _, anchorchild in pairs(self.anchorchilds) do
            anchorchild:Reanchor()
        end
    end

    function XiTimers:ClearAnchors()
        self.anchors = {}
        self.anchorchilds = {}
    end

    function XiTimers:SetSpacing(spacing)
        self.spacing = spacing
        self:Reanchor()
    end

    function XiTimers:SetTimeSpacing(spacing)
        self.timeSpacing = spacing
        self:SetTimerBarPos(self.timerBarPos)
        --self:Reanchor()
    end


    function XiTimers:Show()
        self.button:Show()
        for i=1,self.nrOfTimers do
            if self.timers[i] then
                self:ShowTimerBar(i)
            end
        end
    end

    function XiTimers:Hide()
        self.button:Hide()
        for i=1,self.nrOfTimers do
            if self.timers[i] then
                self:HideTimerBar(i)
            end
        end
    end

    function XiTimers:HideNormalTexture()
        --self.button.normalTexture:SetTexture(1,1,1,0)
        self.button.normalTexture:SetTexture(nil)
    end


    --Out-of-combat-Fader

    local oocframe = CreateFrame("Frame", "XiTimersOOCFaderFrame")
    oocframe:RegisterEvent("PLAYER_REGEN_ENABLED")
    oocframe:RegisterEvent("PLAYER_REGEN_DISABLED")

    function XiTimers.invokeOOCFader()
        XiTimers.OOCFaderEvent(nil, (InCombatLockdown() and "PLAYER_REGEN_DISABLED") or "PLAYER_REGEN_ENABLED")
    end

    XiTimers.OOCFaderEvent = function(self, event, arg1, arg2)
        if event == "PLAYER_REGEN_ENABLED" then
            incombat = false
            for _,timer in pairs(XiTimers.timers) do
                if timer.active and timer.unclickable and timer.HideOOC then
                    timer:Hide()
                end
                timer.button:SetAlpha(timer.OOCAlpha)
                if timer.ChainOOCAlpha then timer.ChainOOCAlpha:SetAlpha(timer.OOCAlpha) end
            end
            if TotemTimers_MultiSpell then
                TotemTimers_MultiSpell:SetAlpha(TotemTimers_MultiSpell.OOCAlpha or 1)
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            incombat = true
            for _,timer in pairs(XiTimers.timers) do
                if timer.active and timer.unclickable and timer.HideOOC and not timer.ActiveWhileHidden and not timer.hideInactive then
                    timer:Show()
                end
                timer.button:SetAlpha(1)
                if timer.ChainOOCAlpha then timer.ChainOOCAlpha:SetAlpha(1) end
            end
            if TotemTimers_MultiSpell then
                TotemTimers_MultiSpell:SetAlpha(1)
            end
        end
    end
    oocframe:SetScript("OnEvent", XiTimers.OOCFaderEvent)

    local rangeManaFrame = CreateFrame("Frame")
    local lastRangeUpdate = 0
    local rangeManaCheckFrames = {}


    local function rangeManaUpdate(self, elapsed)
      --lastRangeUpdate = lastRangeUpdate + 1
      --  if lastRangeUpdate > #rangeManaCheckFrames then lastRangeUpdate = 1 end
      --  local timer = rangeManaCheckFrames[lastRangeUpdate]
      --  if not timer then return end
      --  --[[  if timer.rangeCheck then
      --       --self.rangeCheckCount = self.rangeCheckCount + 1
      --       --if self.rangeCheckCount > 8 then
      --          -- self.rangeCheckCount = 0
      --           timer.outofrange = IsSpellInRange(timer.rangeCheck, "target") == 0
      --           if timer.outofrange then
      --               timer.button.icons[1]:SetVertexColor(1,0,0)
      --           else
      --               timer.button.icons[1]:SetVertexColor(1,1,1)
      --           end
      --      -- end
      --   end ]]
      --
      --  if timer.manaCheck then
      --      --self.manaCheckCount = self.manaCheckCount + 1
      --      --if self.manaCheckCount > 8 then
      --      --self.manaCheckCount = 0
      --      local _,nomana = IsUsableSpell(timer.manaCheck)
      --      if nomana then
      --          if timer.manaCheckMini then
      --              timer.button.miniIcon:SetVertexColor(0.5,0.5,1)
      --          else
      --              timer.button.icons[1]:SetVertexColor(0.5,0.5,1)
      --          end
      --      else
      --          if timer.manaCheckMini then
      --              timer.button.miniIcon:SetVertexColor(1,1,1)
      --          else
      --              --[[ if timer.outofrange then
      --                    timer.button.icons[1]:SetVertexColor(1,0,0)
      --                else ]]
      --              timer.button.icons[1]:SetVertexColor(1,1,1)
      --              -- end
      --          end
      --      end
      --      --end
      --  end
    end

    rangeManaFrame:SetScript("OnUpdate", rangeManaUpdate)
    rangeManaFrame:Show()

    function XiTimers.AddRangeCheck(self)
        local isIn = false
        for i=1,#rangeManaCheckFrames do
            if rangeManaCheckFrames[i] == self then isIn = true end
        end
        if not isIn then table.insert(rangeManaCheckFrames, self) end
    end

    function XiTimers.RemoveRangeCheck(self)
        for i=1,#rangeManaCheckFrames do
            if rangeManaCheckFrames[i] and rangeManaCheckFrames[i] == self then
                table.remove(rangeManaCheckFrames,i)
                i = i - 1
            end
        end
    end

    function XiTimers.HookTooltips(button)
        button:HookScript("OnEnter", function(self)
            if not self:GetAttribute("tooltip") then return end
            if self.tooltip then self.tooltip:Show() end
        end)
        button:HookScript("OnLeave", function(self)
            if self.tooltip then self.tooltip:Hide() end
        end)
    end


    XiTimers.TimerEvent = function(self, event, ...)

        local timer = self.timer
        if timer.customOnEvent then
            local abort = timer.customOnEvent(self, event, ...)
            if abort then return end
        end

        local checkCooldown = false

        if timer.buff and event == "UNIT_AURA" and ... == "player" then
            local name, _, _, count, duration, expires
            local buff = self.timer.buff

            if type(buff) == "number" then
                name, _, _, count, duration, expires = AuraUtil.FindAura(
                        function(...) return select(13, ...) == buff end, "player", "HELPFUL")
            else
                name, _, _, count, duration, expires = AuraUtil.FindAuraByName(buff, "player", "HELPFUL")
            end
            if name and duration and expires then
                timer.buffIsActive = true
                timer.prohibitCooldown = true
                timer.StopPulse = false
                local durObj = C_DurationUtil.CreateDuration()
                durObj:SetTimeFromEnd(expires, duration)
                timer:StartBarTimer(durObj)
                timer:Start(1, durObj)
            elseif timer.buffIsActive then
                timer.buffIsActive = false
                timer.prohibitCooldown = false
                timer:StopBarTimer()
                timer:Stop(1)
                checkCooldown = true
                timer.StopPulse = timer.NoBuffStopPulse
            end
        end

        if timer.buffIsActive then return end

        if checkCooldown or  event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
            local start, duration, enable = GetSpellCooldown(timer.spell)
            if (not start and not duration) then --or (duration <= 1.5 and not InCombatLockdown()) then
                self.timer:Stop(1)
            else
                if duration <= 1.5 then
                    self.timer:Stop(1)
                elseif duration > 1.5 then
                    local durObj = C_DurationUtil.CreateDuration()
                    durObj:SetTimeFromStart(start, duration)
                    self.timer:Start(1, durObj)
                end
                CooldownFrame_Set(self.cooldown, start, duration, enable)
            end
            --[[local start, duration, enable, charges, maxcharges

            local gcdstart, gcdduration = GetSpellCooldown(61304)
            start, duration, enable = GetSpellCooldown(timer.spell)

            if (timer.running and timer.endTime and timer.endTime <= gcdstart + gcdduration) or
                    (gcdstart == start and gcdduration == duration) then
                if timer.timers[1] > 0 then
                    timer:Stop(1)
                end
                self.cooldown:SetDrawSwipe(true)
                self.cooldown:SetCooldown(gcdstart, gcdduration)
            else
                if duration == 0 and timer.timers[1] > 0 then
                    self.timer:Stop(1)
                elseif duration > 0 then
                    self.timer:Start(1, start+duration-GetTime(), duration)
                end
            end]]
        end
    end


--[[local flashCurve = C_CurveUtil.CreateCurve()
--flashCurve:SetType(Enum.LuaCurveType.Linear) -- Standardmäßig linear
--
---- 1. Flache Null-Linie von 0 bis 90
--flashCurve:AddPoint(0, 0)
--flashCurve:AddPoint(90, 0)
--
---- 2. Sinus-Approximation zwischen 90 und 100
---- Wir teilen den Bereich in dichte Schritte auf, um die Kurve zu glätten
--local stepsPerUnit = 4 -- Erzeugt 40 Punkte zwischen 90 und 100 für maximale visuelle Weichheit
--
--for x = 90, 100, (1 / stepsPerUnit) do
--    if x > 90 then
--        -- Wir berechnen den Fortschritt innerhalb des Bereichs 90-100 (Ergebnis 0.0 bis 1.0)
--        local progress = x - 90
--
--        -- Mathematische Sinuswelle:
--        -- Da math.sin im Bogenmaß (Radians) rechnet, multiplizieren wir mit Pi,
--        -- damit der Wert bei jedem Ganzzahlschritt (91, 92, 93...) sauber周期 (cycle) durchläuft.
--        local y = math.abs(math.sin(progress * math.pi))
--
--        -- Punkt der Kurve hinzufügen
--        flashCurve:AddPoint(x, y)
--    end
--end]]