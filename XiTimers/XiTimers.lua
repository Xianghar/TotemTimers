-- Copyright © 2008-2016 Xianghar
-- All Rights Reserved.

local addonName, Addon = ...
local class = select(2,UnitClass("player"))
if class ~= Addon.Class then return end

XiTimers = {}
XiTimers.version = 401

XiTimers.timers = {}
XiTimers.nrOfTimers = 0
XiTimers.__index = XiTimers
XiTimers.updateInterval = 0.06

local libmov = LibStub:GetLibrary("LibMovable-1.0")
local SpellRange = LibStub("SpellRange-1.0")

local XiTimers = XiTimers
local Timers = XiTimers.timers
local _G = getfenv()

local incombat = false

local profile = {}
profile.Anchors = {}
local bars = {}
local baranchors = {}
XiTimers.actionBars = bars
XiTimers.barAnchors = baranchors

local function FormatTime(frame, sec, format)
	local seconds = ceil(sec)

 	if format == "blizz" then
		frame:SetFormattedText(SecondsToTimeAbbrev(sec))
    elseif format == "sec" then
        --seconds = ceil(sec-0.5)
        if seconds == 0 then seconds = "" end
        frame:SetFormattedText(tostring(seconds))
	else
		if(seconds <= 0) then
			frame:SetText("")
		elseif seconds < 600 then
			local d, h, m, s = ChatFrame_TimeBreakDown(seconds)
			frame:SetFormattedText("%01d:%02d", m, s)
		elseif(seconds < 3600) then
			local d, h, m, s = ChatFrame_TimeBreakDown(seconds);
			frame:SetFormattedText("%02d:%02d", m, s)
		else
			frame:SetText("1 hr+")
		end
	end
end


local function SetButtonTime(fontstring, sec)
    if sec > 600 then
        FormatTime(fontstring, sec, "blizz")
    elseif sec > 60 then
        FormatTime(fontstring, sec)
    else
        FormatTime(fontstring, sec, "sec")
    end
end


local nextUpdate = 0

local buffTimers = {}
XiTimers.buffTimers = buffTimers
local continuousTimers = {}

local continuousUpdateDone = false

function XiTimers.UpdateTimers(self,elapsed)
    if XiTimers.updateInterval > 0 then nextUpdate = nextUpdate + elapsed end	
	if not continuousUpdateDone and nextUpdate >= XiTimers.updateInterval / 2 then
		continuousUpdateDone = true
		for i=1,#continuousTimers do
			continuousTimers[i]:continuousUpdate()
		end
	end
    if nextUpdate >= XiTimers.updateInterval then
        nextUpdate = 0
		continuousUpdateDone = false
		local now = GetTime()
		local timers = XiTimers.timers
        for i=1,XiTimers.nrOfTimers do			
			local timer = timers[i]
            if timer.active then
				timer.buffSeen = false
				if timer.timer > 0 then	
					timer:Update(now)
				elseif timer.smallTimer > 0 then
					timer:UpdateSmall(now)
				end
			end
        end     
		if XiTimers.updateAuras then
			XiTimers.updateAuras = false
			local counter = 0
			while true do
				counter = counter + 1
				local name,_,count,_,duration, expiration,_,_,_,spellID = UnitAura("player", counter)
				if not name then break end
				if buffTimers[spellID] then
					local timer = XiTimers.timers[buffTimers[spellID]]
					timer.buffSeen = true
					if timer.timer > 0 and timer.buffIsActive then
						if timer.buffCount and count and duration == 0 and expiration == 0 then
							timer.barTimer = count
							timer.timer = count
							timer:Start(count, count, true, count)
						else
							timer.endTime = expiration
							timer.startTime = expiration - duration
							timer.timer = expiration - now
							timer.buffSeen = true
						end
					else
						timer.reverseAlpha = false	
						if count and duration == 0 and expiration == 0 then
							timer:Start(count, count, true, count)
						else
							timer:Start(expiration-duration, expiration, true)
						end
					end
				end
			end
			for _,timerID in pairs(buffTimers) do
				local timer = timers[timerID]
				if not timer.buffSeen and timer.buffIsActive then
					timer:Stop()
				end
			end
		end
    end
end

function XiTimers.SetProfile(newprofile)
	profile = newprofile
end



local function DropSpell(self, kind, nr, item, id, ...)
	local role = GetSpecialization()
	if InCombatLockdown() or (kind ~= "spell" and kind ~= "item") then return end
	if not profile.buttons then profile.buttons = {} end
	if not profile.buttons[class] then profile.buttons[class] = {} end
	if not profile.buttons[class][role] then profile.buttons[class][role] = {} end
	
	local oldspell = {}
	if profile.buttons[class][role][self.timer.nr] then
		oldspell.type = profile.buttons[class][role][self.timer.nr].type
		oldspell.id = profile.buttons[class][role][self.timer.nr].id
	end
	if kind == "spell" then
		profile.buttons[class][role][self.timer.nr] = {}
		profile.buttons[class][role][self.timer.nr].type = "spell"
		profile.buttons[class][role][self.timer.nr].id = id		
	elseif kind == "item" then 
		profile.buttons[class][role][self.timer.nr] = {}
		profile.buttons[class][role][self.timer.nr].type = "item"
		profile.buttons[class][role][self.timer.nr].id = nr
		profile.buttons[class][role][self.timer.nr].item = item
	end
	ClearCursor()
	if oldspell.type == "spell" and oldspell.id then
		PickupSpell(oldspell.id)
	elseif oldspell.type == "item" and oldspell.id then
		PickupItem(oldspell.id)
	end
	self.timer:LoadConfig()
	self.timer:Activate()
	self.timer.button:SetNormalTexture(nil)
	--self.timer.button.NormalTexture:Hide()
end

local function DropSpellClick(self)
	if InCombatLockdown() then return end
	local itemtype, arg1, arg2, arg3 = GetCursorInfo()
	if itemtype == "item" or itemtype == "spell" then
		DropSpell(self, itemtype, arg1, arg2, arg3)		
	end
end

local function PickupSpellFromTimer(self)
	if InCombatLockdown() then return end
	local role = GetSpecialization()
	if not self.timer.active then return end
	if self.timer.type == "spell" then		
		PickupSpell(self.timer.spellID)
	elseif self.timer.type == "item" then
		PickupItem(self.timer.item)
	end
	profile.buttons[class][role][self.timer.nr] = nil
	self:SetNormalTexture("Interface\\Buttons\\UI-Quickslot")
	--self.NormalTexture:Show()
	self.icon:SetTexture(nil)
	self.timer:Deactivate()
	self:Show()	
end




function XiTimers:new(unclickable, unconfigurable)
	local self = {}
	setmetatable(self, XiTimers)
	XiTimers.nrOfTimers = XiTimers.nrOfTimers + 1
    self.nr = XiTimers.nrOfTimers
	self.active = false
    self.unclickable = unclickable
	if unclickable then
        self.button = CreateFrame("CheckButton", "XiTimers_Timer"..XiTimers.nrOfTimers, UIParent, "XiTimersLiteUnsecureTemplate")
    else
        self.button = CreateFrame("CheckButton", "XiTimers_Timer"..XiTimers.nrOfTimers, UIParent, "XiTimersLiteTemplate")
		RegisterStateDriver(self.button, "petbattle", "[petbattle][overridebar][possessbar] active; none")
		RegisterStateDriver(self.button, "combat", "[combat] active; none")
		self.button:WrapScript(self.button, "OnAttributeChanged", [[
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
	--self.button:SetPoint("CENTER", UIParent, "CENTER")
	self.button.timer = self
	
	--for rActionButtonStyler
	self.button.action = 0 
    self.button:SetCheckedTexture(nil)
	self.button.SetCheckedTexture = function() end
    self.button.SetChecked = function() end
    self.button.GetChecked = function() return false end
    self.button.SetDisabledCheckedTexture = function() end
    
	self.button.unclickable = unclickable
	self.button.element = XiTimers.nrOfTimers
	
	self.button:RegisterForClicks("AnyDown")
    
	
	self.timer = 0
    self.duration = 0
    self.barTimer = 0
    self.barDuration = 0
	self.smallTimer = 0
	self.smallTimerDuration = 0
	self.button.icons = {}
	self.button.flash = {}

	self.timerBar = CreateFrame("StatusBar", "XiTimers_TimerBar"..XiTimers.nrOfTimers, self.button, "XiTimersTimerBarTemplate")
    self.timerBar.background = _G["XiTimers_TimerBar"..XiTimers.nrOfTimers.."Background"]
    self.timerBar.time = _G["XiTimers_TimerBar"..XiTimers.nrOfTimers.."Time"]
    self.timerBar.icon = _G["XiTimers_TimerBar"..XiTimers.nrOfTimers.."Icon"]
    self.timerBar:SetPoint("TOP", self.button, "BOTTOM")
	self.button.icon = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Icon"]
	self.button.flash = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Flash"]
    if self.button.flash then
        local flash = self.button.flash
        flash.animation = self.button.flash:CreateAnimationGroup()
        flash.animation:SetLooping("NONE")
        flash.flashAnim = flash.animation:CreateAnimation()
        flash.flashAnim:SetDuration(15)
        flash.flashAnim.flash = flash
        flash.flashAnim:SetScript("OnPlay", function(self) self.flash:Show() end)
        flash.flashAnim:SetScript("OnFinished", function(self) self.flash:Hide() end)
        flash.flashAnim:SetScript("OnStop", function(self) self.flash:Hide() end)
        flash.flashAnim:SetScript("OnUpdate", function(self) self.flash:SetAlpha(BuffFrame.BuffAlphaValue) end)
	end
    if self.button.icon then
        local flash = self.button.icon
		flash.animation = self.button.flash:CreateAnimationGroup()
		flash.animation:SetLooping("NONE")
		flash.flashAnim = flash.animation:CreateAnimation()
		flash.flashAnim:SetDuration(15)
		flash.flashAnim.flash = flash
		flash.flashAnim:SetScript("OnPlay", function(self) self.flash:Show() end)
		flash.flashAnim:SetScript("OnUpdate", function(self) self.flash:SetAlpha(BuffFrame.BuffAlphaValue) end)
    end
	self:SetIconAlpha(self.button.icon, 1)
	
    self.timeColor = {r=1,g=1,b=1}
	self.button.icon:Show()
	self.timerBarPos = "BOTTOM"
	self.timeSpacing = 0
	self.spacing = 5
	self.timeStyle = "mm:ss"
    self.OOCAlpha = 0.4
	self.maxAlpha = 1
	self.warningMsg = nil
    self.warningSpell = nil
	self.expirationMsg = nil
	self.earlyExpirationMsg = nil
    self.warningIcon = nil
	self.activeCooldownAlpha = 0.4
	self.events = {}
	self.button.count = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Count"]
	self.button.cooldown = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Cooldown"]
	self.button.cooldown:SetSwipeColor(0, 0, 0)
	self.button.cooldown:SetHideCountdownNumbers(true)
	self.button.miniIcon = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."MiniIcon"]
    self.button.miniIconFrame = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Mini"]
    self.button.bar = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."Bar"]
	self.button.bar:SetStatusBarColor(0.6,0.6,1.0,0.7)
    self.button.hotkey = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."HotKey"]
    self.button.rangeCount = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."RangeCount"]
	--self.button.normalTexture = _G["XiTimers_Timer"..XiTimers.nrOfTimers.."NormalTexture"]
	self.button:SetNormalTexture(nil)
	local frame = CreateFrame("Frame", nil, self.button)
    frame:Show()
    frame:SetAllPoints(self.button)
    self.button.time = frame:CreateFontString(self.button:GetName().."Time", 'OVERLAY')
    self.button.time:SetPoint("CENTER",0,1)
    self.button.time:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
    frame:SetFrameLevel(frame:GetFrameLevel()+10)
    self.button.time:Hide()
    --self.button.cooldown:SetFrameLevel(self.button.cooldown:GetFrameLevel()-1)
    self.button.cooldown.noCooldownCount = true
    self.button.cooldown.noOCC = true
    self.rangeCheckCount = 0
    self.manaCheckCount = 0
	self.running = false
	    
    self.animation = XiTimersAnimations:new(self.button)
	
	if not IsAddOnLoaded("rActionButtonStyler") then
		self:HideNormalTexture()
	else
		ActionButton_Update(self.button)
	end
    
	self.anchors = {}
	self.anchorchilds = {}
	
	--self.button:SetScript("OnDragStart", XiTimers.StartMoving)
	--self.button:SetScript("OnDragStop", XiTimers.StopMoving)
    --self.button:SetAttribute("_ondragstart", [[control:CallMethod("StartMove")]])
    --self.button:SetAttribute("_ondragstop", [[control:CallMethod("StopMoving")]])
    self.button.StartMove = XiTimers.StartMoving
    self.button.StopMove = XiTimers.StopMoving
	self.button:RegisterForDrag("LeftButton")
    
	table.insert(Timers, self)
	
	if not unconfigurable then
		self.button:SetAttribute("_onreceivedrag",
			[[ 
				control:CallMethod("DropSpell", kind, value, ...)
				return "clear"
			]])
		self.button:WrapScript(self.button, "OnClick", [[
			if self:GetAttribute("unlocked") then
				control:CallMethod("DropSpellClick")
				return false
			end
		]])
		self.button:SetAttribute("_ondragstart", [[ if self:GetAttribute("unlocked") then control:CallMethod("PickupSpell") end]])
		self.button.DropSpell = DropSpell
		self.button.DropSpellClick = DropSpellClick
		self.button.PickupSpell = PickupSpellFromTimer
		
	end
	self.button.ShowTooltip = XiTimers.Tooltip
    self.button.HideTooltip = function(self) GameTooltip:Hide() end
	--self.button:SetAttribute("_onenter", [[ control:CallMethod("ShowTooltip")]])
	--self.button:SetAttribute("_onleave", [[ control:CallMethod("HideTooltip")]])
	
	

    -- self.button:SetAttribute("_onattributechanged", [[ 
        -- if name=="state-invehicle" then
            -- if value == "show" and self:GetAttribute("active") then
                -- self:Show()
            -- else
                -- self:Hide()
            -- end
        -- end
        -- ]])

    self.button:Hide()
	self.configurable = not unconfigurable
	return self
end

function XiTimers.Tooltip(self)
	local spell = self.timer.spellID
	if not spell then spell = self:GetAttribute("spell1") end
	if spell and spell > 0 then
	    if not XiTimers.TooltipsAtButtons then 
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
		else
			local left = self:GetLeft()
			if left<UIParent:GetWidth()/2 then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			else			
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			end
		end
		GameTooltip:SetSpellByID(spell)
	end
end

-- timer functions
local IsUsableSpell = IsUsableSpell

function XiTimers:Update(now)
	if not self.running or self.buffCount then return end	
    local button = self.button
	
	if self.timer > 0 then			
		self.timer = self.endTime - now
		if self.timer <= 0 then
			self:Stop()
			return
		else
			local timer = self.timer
			--[[if timer<10 and self.warningMsg then print(self.warningMsg)
				--self:PlayWarning(self.warningMsg, self.warningSpell, self.warningIcon)
				self.warningMsg = nil
			end]]
			if not self.hideTime then
				if not self.timerOnButton then
					if timer >= 600 then
						FormatTime(self.timerBar.time, timer, "blizz")
					else
						FormatTime(self.timerBar.time, timer, self.timeStyle)
					end
				else
					SetButtonTime(button.time, timer)
				end
				if self.visibleTimerBars and not self.timerOnButton then
					self.timerBar:SetValue(timer)
				end
			end
			
			if self.buffIsActive then 
				button.bar:SetValue(self.timer)
			end
			
			if not self.isAnimating and timer <= 5 and timer > 0 then
				self.isAnimating = true
				if not self.dontFlash then
					if self.flashRed and self.button.flash then
						self.button.flash.animation:Play()
					end
					--[[elseif self.button.icon then
						self.button.icon.animation:Play()
					end]]
				end
			end 
		end
	end
end


function XiTimers:Activate()
	self.active = true
	for _,event in pairs(self.events) do
		self.button:RegisterEvent(event)
	end
	if not self.hideInactive and (not self.HideOOC or InCombatLockdown()) then
        self.button:Show()        
    end
	self.button:SetAttribute("active", true)
    if self.rangeCheck or self.manaCheck then
		self:AddRangeCheck()
	end
	if self.continuousUpdate then
		table.insert(continuousTimers, self)
	end
end

function XiTimers:Deactivate()
	self.active = false
	for _,event in pairs(self.events) do
		self.button:UnregisterEvent(event)
	end
	self.button:Hide()
    self.button:SetAttribute("active", false)
	self:RemoveRangeCheck()
	if self.buff and buffTimers[buff] then
		for i=1,#buffTimers[buff] do
			if buffTimers[buff][i] == self.nr then table.remove(buffTimers[buff], i) end
		end
	end
	if self.continuousUpdate then
		for i=1,#continuousTimers do
			if continuousTimers[i] == self then
				table.remove(continuousTimers, i)
			end
		end
	end
end


function XiTimers:Start(startTime, endTime, buff, buffCount, charges, maxcharges)
	self.startTime = startTime
	self.endTime = endTime
	duration = endTime - startTime
    self.duration = duration
	local timerbar = self.timerBar
	local time = endTime - GetTime()
	if buff and buffCount then
		self.timer = buffCount
	else
		self.timer = time
	end
	if self.timer < 0 then return end
	
	if not self.timerOnButton then
		if time >= 600 then
			FormatTime(timerbar.time, self.timer, "blizz")
		else
			FormatTime(timerbar.time, self.timer, self.timeStyle)
		end
	else
		SetButtonTime(self.button.time, self.timer)
	end
	
	timerbar:SetMinMaxValues(0, duration)
	self.running = true

	if self.visibleTimerBars and not self.timerOnButton then
		timerbar:SetValue(self.timer)
	end
	if buff or self.dontAlpha or (charges and charges > 0) then
		self:SetIconAlpha(self.button.icon, self.maxAlpha)
	else
		self:SetIconAlpha(self.button.icon, self.activeCooldownAlpha)
	end
    --if self.reverseAlpha and not (charges and charges > 0) then self:SetIconAlpha(self.button.icon, self.activeCooldownAlpha) end

	if not self.hideTime then
		if not self.timerOnButton then
			self.button.time:Hide()
			self:ShowTimerBar() 
		else
			self:HideTimerBar() 
			self.button.time:Show()
			--self.button.time:SetTextColor(self.timeColor.r,self.timeColor.g,self.timeColor.b)
		end
	else
		self.button.time:Hide()
		self:HideTimerBar()
	end
	
	self.buffIsActive = buff
	self.buffCount = buffCount
	if buff then
		if buffCount then
			self.button.bar:SetMinMaxValues(0, buffCount)
			self.button.bar:SetValue(buffCount)
		else
			self.button.bar:SetMinMaxValues(0, duration)
			self.button.bar:SetValue(self.timer)
		end
		self.button.bar:Show()
	else
		self.button.bar:Hide()
	end
	if (self.showCooldown or self.timerOnButton) and not self.prohibitCooldown and not self.buffIsActive then
		self.button.cooldown:SetDrawSwipe(not maxcharges or (charges and charges == 0))
		self.button.cooldown:SetCooldown(startTime, duration, charges, maxcharges)
	else
		self.button.cooldown:Hide()
	end

    self.button.flash.animation:Stop()
    self.isAnimating = false
    --self.flashRed = XiTimers.flashRed
    --self.button.bar:SetValue(0)
    self:SetTimerBarPos(self.timerBarPos, true)
    if self.hideInactive then
        self.button:Show()
    end
	if not buff and duration >= 45 then
		self.dontFlash = false
	else
		self.dontFlash = true
	end
end

function XiTimers:Stop()	
	if not self.running then return end
	self.running = false
	local timerbar = self.timerBar
    --[[if not self.stopQuiet then
        if self.StopPulse then
            self.animation:SetTexture(self.button.icon:GetTexture())
            self.animation:Play()
        end
    end]]
    self.stopQuiet = false
	timerbar.time:SetText("")
	if self.visibleTimerBars then		
		timerbar:SetValue(0)
	end
    self:HideTimerBar(timer)
    self.button.time:Hide()
    self.button.cooldown:Hide()
    if not self.dontAlpha then self:SetIconAlpha(self.button.icon, self.activeCooldownAlpha) end
    if self.reverseAlpha then self:SetIconAlpha(self.button.icon,self.maxAlpha) end    
    self:SetTimerBarPos(self.timerBarPos, true)
    if self.hideInactive then
        self.button:Hide()
    end
    self:SetOutOfRange(false)
	self.timer = 0
	
	if self.buffIsActive then
		self.button.bar:Hide()
		self.button.bar:SetValue(0)
		self.buffIsActive = nil
		self.buffCount = nil
		if not self.noCooldownAfterBuff then
			XiTimers.TimerEvent(self.button, "SPELL_UPDATE_COOLDOWN")
		end
	end
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
        self.button.icon:SetVertexColor(1,0,0)
    elseif self.outOfMana then
        self.button.icon:SetVertexColor(0.5,0.5,2)
    else
        self.button.icon:SetVertexColor(1,1,1)
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

function XiTimers:SetReverseAlpha(ralpha)
	self.reverseAlpha = ralpha
	if (self.timer > 0) and not self.dontAlpha then
		if not self.reverseAlpha then
			self:SetIconAlpha(self.button.icon, self.maxAlpha)
		else
			self:SetIconAlpha(self.button.icon, self.activeCooldownAlpha)
		end		
	elseif not self.dontAlpha then
		if not self.reverseAlpha then
			self:SetIconAlpha(self.button.icon, self.activeCooldownAlpha)
		else
			self:SetIconAlpha(self.button.icon, self.maxAlpha)
		end	
	end
end

function XiTimers:SetAlpha(alpha)
    self.button:SetAlpha(alpha)
end

function XiTimers:HideTimerBar()
	self.timerBar.background:Hide()
    self.timerBar.background:SetValue(0)
    ---self.timerBars[nr].icon:Hide()
    self.timerBar:Hide()
end

function XiTimers:ShowTimerBar()
    self.timerBar:Show()
	if self.visibleTimerBars then
        self.timerBar.background:Show()
        self.timerBar.background:SetValue(1)
    end
end

-- display functions

function XiTimers:SetTimerBarPos(side, notReanchor)
	self.timerBarPos = side
	
	local TimerBar = self.timerBar
		
	TimerBar:ClearAllPoints()
    TimerBar.icon:ClearAllPoints()
	
    if side == "RIGHT" then
        TimerBar.icon:SetPoint("LEFT", TimerBar, "RIGHT", -4, 0)
    else
        TimerBar.icon:SetPoint("RIGHT", TimerBar, "LEFT", 4, 0)
    end
    local activetimers = 1
	if side == "LEFT" then
		TimerBar:SetPoint("RIGHT", self.button, "LEFT", -self.timeSpacing, TimerBar:GetHeight()*TimerBar:GetEffectiveScale()/2)
	elseif side == "RIGHT" then
		TimerBar:SetPoint("LEFT", self.button, "RIGHT", self.timeSpacing, TimerBar:GetHeight()*TimerBar:GetEffectiveScale()/2)
	elseif side == "TOP" then
		TimerBar:SetPoint("BOTTOM", self.button, "TOP", 0, self.timeSpacing)
	elseif side == "BOTTOM" then
   		TimerBar:SetPoint("TOP", self.button, "BOTTOM", 0, -self.timeSpacing)
	end
	if not InCombatLockdown() and not notReanchor then self:Reanchor() end
end

function XiTimers:GetBorder(side)
	local timerBarPos = self.timerBarPos
	if side == "TOP" and timerBarPos == "TOP" or side == "BOTTOM" and timerBarPos == "BOTTOM" then
        local height = self.timerBar:GetHeight()*self.timerBar:GetEffectiveScale()
		return self.timerOnButton and 0 or self.timeSpacing + height
	elseif ((side == "LEFT" and timerBarPos == "LEFT" or side == "RIGHT" and timerBarPos == "RIGHT") and not self.timerOnButton)
    then
		return (self.timeSpacing + self.timerBar:GetWidth()*self.timerBar:GetEffectiveScale())
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
    local _,height = self.timerBar.time:GetFont()
    self.timerBar.time:SetFont(font, height)
    local _,height = self.button.time:GetFont()
    self.button.time:SetFont(font, height, "OUTLINE")
end

function XiTimers:SetTimeHeight(height)
	self.timerBar:SetHeight(height)
	local font = self.timerBar.time:GetFont()
	self.timerBar.time:SetFont(font, height)
	self:Reanchor()
end

function XiTimers:SetTimeWidth(width)
	self.timerBar:SetWidth(width)
	self.timerBar.time:SetWidth(width)
	self:Reanchor()
end

function XiTimers:SetScale(scale)
	self.button:SetScale(scale)
	self:SetTimerBarPos(self.timerBarPos)
	--self:Reanchor()
end

function XiTimers:SetBarTexture(texture)
    self.timerBar:SetStatusBarTexture(texture)
    self.timerBar.background:SetStatusBarTexture(texture)
end

function XiTimers:SetBarColor(r,g,b)
    self.timerBar:SetStatusBarColor(r,g,b, 1.0)
    self.timerBar.background:SetStatusBarColor(r,g,b,0.4)
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
}

local DirectionYMult = {
	CENTER = 0,
	LEFT = 0,
	RIGHT = 0,
	TOP = -1,
	BOTTOM = -1,
    TOPRIGHT = -1,
    TOPLEFT = -1,
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
		self:SetPoint(anchor.point, anchor.timer, anchor.relpoint)
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
	self:ShowTimerBar()
    --[[for i=1,self.nrOfTimers do
        if self.timers[i] > 0 then
            self:ShowTimerBar(i)
        end
    end]]
end

function XiTimers:Hide()
    self.button:Hide()
	self:HideTimerBar()
   --[[ for i=1,self.nrOfTimers do
        if self.timers[i] > 0 then
            self:HideTimerBar(i)
        end
    end]]
end

function XiTimers:HideNormalTexture()
	--self.button.normalTexture:SetTexture(1,1,1,0)		
end

function XiTimers:Clickthrough(value)
	self.clickthrough = value
	if not XiTimers.grid then
		self.button:EnableMouse(not value)
	end
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
        end
		if XiTimers.PowerBar and XiTimers.PowerBar.active then
			if XiTimers.ActiveProfile.PowerBarHideOOC then
				XiTimers.PowerBar:Hide()
			else
				XiTimers.PowerBar:Show()
			end
			XiTimers.PowerBar:SetAlpha(XiTimers.PowerBar.OOCAlpha)
		end
    elseif event == "PLAYER_REGEN_DISABLED" then
        incombat = true
        for _,timer in pairs(XiTimers.timers, true) do
            if timer.active and timer.unclickable and timer.HideOOC and not timer.hideInactive then
                timer:Show()
            end			
            timer.button:SetAlpha(1)
        end  
		if XiTimers.PowerBar and XiTimers.PowerBar.active then
			XiTimers.PowerBar:Show()
			XiTimers.PowerBar:SetAlpha(1)
		end
	end
end

oocframe:SetScript("OnEvent", XiTimers.OOCFaderEvent)

local rangeManaFrame = CreateFrame("Frame")
local lastRangeUpdate = 0
local rangeManaCheckFrames = {}

local function rangeManaUpdate(self, elapsed)
	lastRangeUpdate = lastRangeUpdate + 1
	if lastRangeUpdate > #rangeManaCheckFrames then lastRangeUpdate = 1 end
	local timer = rangeManaCheckFrames[lastRangeUpdate]
	if not timer then return end
    if timer.rangeCheck then
        --self.rangeCheckCount = self.rangeCheckCount + 1
        --if self.rangeCheckCount > 8 then
           -- self.rangeCheckCount = 0
            timer.outofrange = SpellRange.IsSpellInRange(timer.rangeCheck, "target") == 0			
            if timer.outofrange then
                timer.button.icon:SetVertexColor(1,0,0)
            else
                timer.button.icon:SetVertexColor(1,1,1)
            end
       -- end
    end
    
    if timer.manaCheck then
        --self.manaCheckCount = self.manaCheckCount + 1
        --if self.manaCheckCount > 8 then
            --self.manaCheckCount = 0
            local _,nomana = IsUsableSpell(timer.manaCheck)
			if nomana then
                timer.button.icon:SetVertexColor(0.5,0.5,1)
            else
                if timer.outofrange then
                    timer.button.icon:SetVertexColor(1,0,0)
                else
                    timer.button.icon:SetVertexColor(1,1,1)
                end
            end
        --end
    end
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


XiTimers.TimerEvent = function(self, event, ...)
	local timer = self.timer
	if timer.buffIsActive then return end
    if event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then 
		local start, duration, enable, charges, maxcharges
		if timer.type == "spell" and timer.hasCharges then
			charges, maxcharges, start, duration = GetSpellCharges(timer.spellID)
			self.count:SetText(charges)
			if charges == maxcharges then
				if timer.timer > 0 then
					timer:Stop()
				end
				local gcdstart, gcdduration = GetSpellCooldown(61304)
				if gcdduration and gcdduration > 0 then
					self.cooldown:SetDrawSwipe(true)
					self.cooldown:SetCooldown(gcdstart, gcdduration)
				end
			else
				timer:Start(start, start+duration, nil, nil, charges, maxcharges)
			end	
		else
			local gcdstart, gcdduration = GetSpellCooldown(61304)
			if timer.type == "spell" then			
				start, duration, enable = GetSpellCooldown(timer.spellID)
			else
				start, duration, enable = GetItemCooldown(timer.itemID)
			end
			if (timer.running and timer.endTime and timer.endTime <= gcdstart+gcdduration) or 
					(gcdstart == start and gcdduration == duration) then
				if timer.timer > 0 then
					timer:Stop()
				end
				self.cooldown:SetDrawSwipe(true)
				self.cooldown:SetCooldown(gcdstart, gcdduration)	
			else
				if duration == 0 and timer.timer > 0 then
					self.timer:Stop()
				elseif duration > 0 then
					self.timer:Start(start, start+duration)
				end
			end
		end
	end
end


function mergetable(target, source)
	for key, value in next, source, nil do
		if type(target[key]) == "nil" then
			if type(value) == "table" then
				target[key] = {}
				mergetable(target[key], value)
			else
				target[key] = value
			end
		end
	end

end

function XiTimers:LoadConfig()
	if self.CustomConfig then return end
	self:Deactivate()
	
	local role = GetSpecialization()
	if not profile.buttons then profile.buttons = {} end
	if not profile.buttons[class] then
		profile.buttons[class] = {}
		for i=1,GetNumSpecializations() do
			profile.buttons[class][i] = {}
		end
	end
	
	local config = profile.buttons[class][role][self.nr]
	if not config then 
		self.button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot")
		self:Deactivate()
		return
	end
	if config.type == "spell" and config.id then
		local spellID = config.id		
		local data = XiTimers.SpellData[spellID]
		if data and data.roles and data.roles[role] then
			data = data.roles[role]
		end
		
		if data and data.upgrade and IsPlayerSpell(data.upgrade) then
			data = XiTimers.SpellData[data.upgrade]
		elseif not IsPlayerSpell(config.id) or select(7, GetSpellInfo(GetSpellInfo(config.id))) ~= config.id then
			if data and data.alt then
				for i=1,#data.alt do 
					if IsPlayerSpell(data.alt[i]) then
						spellID = data.alt[i]
						data = XiTimers.SpellData[spellID]
						if data and data.roles and data.roles[role] then
							data = data.roles[role]
						end
						break
					end
				end
			end
			if spellID == config.id then return end
		end
		

		if data and data.extend and not data.isExtended and XiTimers.SpellData[data.extend] then
			local extender = XiTimers.SpellData[data.extend]
			if extender.roles and extender.roles[role] then extender = extender.roles[role] end
			mergetable(data, extender)
			data.isExtended = true
		end

		
		self.button.icon:SetTexture(GetSpellTexture(spellID))
		self.button:SetAttribute("type1", "spell")
		if data and data.button then
			self.button:SetAttribute("spell1", data.button)
		else
			self.button:SetAttribute("spell1", spellID)
		end
		self.spellID = spellID
		self.events[1] = "SPELL_UPDATE_COOLDOWN"
		self.type = "spell"
		
		local currentCharges, maxCharges = GetSpellCharges(spellID)
		if maxCharges and maxCharges > 1 then
			self.hasCharges = true
			self.button.count:Show()
			self.button.count:SetText(currentCharges)
		else
			self.button.count:Hide()
			self.hasCharges = false
		end

		if data then			
			if data.buff then 
				self.buff = data.buff
				buffTimers[data.buff] = self.nr
				self.noCooldownAfterBuff = data.noCooldownAfterBuff
			end
			self.continuousUpdate = data.continuousUpdate
		end
		if not data or not data.noManaCheck then
			self.manaCheck = spellID
		else
			self.manaCheck = nil
		end
		if not data or not data.noRangeCheck then
			self.rangeCheck = spellID
		else
			self.rangeCheck = nil
		end

	elseif config.type == "item" and config.id and config.item then
		self.button.icon:SetTexture(GetItemIcon(config.id))
		self.button:SetAttribute("*type*", "item")
		self.button:SetAttribute("*item*", config.item)
		self.type = "item"
		self.item = config.item
		self.itemID = config.id
		self.events[1] = "ACTIONBAR_UPDATE_COOLDOWN"
	end	
	self:Activate()
	self.button:SetScript("OnEvent", XiTimers.TimerEvent)
	self:SetReverseAlpha(true)
	self.dontFlash = true
	XiTimers.TimerEvent(self.button, "SPELL_UPDATE_COOLDOWN")
end



function XiTimers.ShowGrid()
	XiTimers.grid = true
	XiTimers.PositionTimersOnBars(true)
	for k,timer in pairs(XiTimers.timers) do
		timer.button:EnableMouse(true)
		if timer.configurable then
			timer.button:SetAttribute("unlocked", true)
			if not timer.active then
				timer.button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot")
				timer.button.icon:SetTexture(nil)
				timer.button:Show()
				--timer.button.NormalTexture:Show()
			end
		end
	end
end

function XiTimers.HideGrid()
	XiTimers.grid = false
	XiTimers.PositionTimersOnBars()
	for k,timer in pairs(XiTimers.timers) do
		timer.button:EnableMouse(not timer.clickthrough)
		if timer.configurable then
			timer.button:SetAttribute("unlocked", false)
			if not timer.active then
				timer.button:Hide()
			end
			timer.button:SetNormalTexture(nil)
			--timer.button.NormalTexture:Hide()
		end
	end
end

local function getAnchorTable(frame)
	if not profile.Anchors then profile.Anchors = {} end
	local name = frame:GetName()
	if not profile.Anchors[name] then
		profile.Anchors[name] = {}
	end
	return profile.Anchors[name]
end

XiTimers.getAnchorTable = getAnchorTable


function XiTimers.CreateDefaultBars()
	for i=1,5 do
		local frame = CreateFrame("Frame", "XiTimersBar"..i, UIParent)
		frame:SetWidth(100)
		frame:SetHeight(36)
		frame:SetPoint("CENTER", nil, "CENTER")
		libmov.RegisterMovable("XiTimers", frame, getAnchorTable, i)	
		baranchors[i] = frame
		
		bars[i] = {}
		for j=1,10 do
			local timer = XiTimers:new()
			bars[i][j] = timer
			if j > 1 then
				timer:Anchor(bars[i][j-1], "LEFT", "RIGHT")
			else
				timer.button:ClearAllPoints()
				timer:SetPoint("LEFT", frame, "LEFT")
			end
		end	
	end
end

function XiTimers.LoadProfile()	
	wipe(buffTimers)
	for k,t in pairs(XiTimers.timers) do
		if t.configurable then t:LoadConfig() end
	end
	for k,frame in pairs(baranchors) do
		frame:SetWidth(XiTimers.timers[1].button:GetWidth()*XiTimers.timers[1].button:GetScale()*10+XiTimers.timers[1].spacing*9*XiTimers.timers[1].button:GetScale())		
		frame:SetHeight(XiTimers.timers[1].button:GetHeight()*XiTimers.timers[1].button:GetScale())
		frame:SetScale(XiTimers.timers[1].button:GetScale())
	end
--	XiTimers.PositionTimersOnBars(XiTimers.grid)
	if XiTimers.grid then XiTimers.ShowGrid() else XiTimers.HideGrid() end
	libmov.UpdateMovableLayout("XiTimers")
	
end

function XiTimers.UnlockBars()
	XiTimers.buttonsUnlocked = true
	libmov.UnlockMovables("XiTimers")
end

function XiTimers.LockBars()
	XiTimers.buttonsUnlocked = false
	libmov.LockMovables("XiTimers")
end

function XiTimers.PositionTimersOnBars(unlocking)

	for i=1,#baranchors do

		for j = 1,#bars[i] do
			bars[i][j].button:ClearAllPoints()
			bars[i][j]:ClearAnchors()
		end
		
		if unlocking or bars[i].position == "grid" or not bars[i].position then
			bars[i][1].button:SetPoint("LEFT", baranchors[i], "LEFT")
			for j=2,#bars[i] do
				bars[i][j]:Anchor(bars[i][j-1], "LEFT", "RIGHT")
			end	
		elseif bars[i].position == "left" then
			lastactive = nil
			for timer = 1,#bars[i] do
				if bars[i][timer].active then
					lastactive = timer
					break
				end
			end
			if lastactive then
				bars[i][lastactive].button:ClearAllPoints()
				bars[i][lastactive].button:SetPoint("LEFT", baranchors[i], "LEFT")
				for timer=lastactive+1,#bars[i] do
					if bars[i][timer].active then
						bars[i][timer]:Anchor(bars[i][lastactive], "LEFT", "RIGHT")
						lastactive = timer
					end
				end
			end
		elseif bars[i].position == "right" then
				for j = 1,#bars[i] do
			bars[i][j].button:ClearAllPoints()
		end
			lastactive = nil
			for timer = #bars[i],1,-1 do
				if bars[i][timer].active then
					lastactive = timer
					break
				end
			end
			if lastactive then
				bars[i][lastactive].button:ClearAllPoints()
				bars[i][lastactive].button:SetPoint("RIGHT", baranchors[i], "RIGHT")
				for timer=lastactive-1,1,-1 do
					if bars[i][timer].active then
						bars[i][timer]:Anchor(bars[i][lastactive], "RIGHT", "LEFT")
						lastactive = timer
					end
				end
			end
		elseif bars[i].position == "center" then
			--count active timers
			local activetimers = {}
			for j=1,#bars[i] do
				if bars[i][j].active then
					table.insert(activetimers, bars[i][j])					
				end
			end
			
			if #activetimers % 2 == 0  and #activetimers > 0 then
				local middletimer = #activetimers / 2
				activetimers[middletimer]:SetPoint("RIGHT", baranchors[i], "CENTER", true)
				for j = middletimer-1, 1, -1 do
					activetimers[j]:Anchor(activetimers[j+1], "RIGHT", "LEFT")
				end
				activetimers[middletimer+1]:SetPoint("LEFT", baranchors[i], "CENTER", true)
				for j = middletimer+2, #activetimers do
					activetimers[j]:Anchor(activetimers[j-1], "LEFT", "RIGHT")
				end
			elseif #activetimers > 0 then
				local middletimer = ceil(#activetimers / 2)
				activetimers[middletimer].button:SetPoint("CENTER", baranchors[i], "CENTER")
				for j = middletimer-1, 1, -1 do
					activetimers[j]:Anchor(activetimers[j+1], "RIGHT", "LEFT")
				end
				for j = middletimer+1, #activetimers do
					activetimers[j]:Anchor(activetimers[j-1], "LEFT", "RIGHT")
				end
				
			end
		end
	end
end

XiTimers.CreateDefaultBars()



