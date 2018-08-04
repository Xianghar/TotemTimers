-- Copyright © 2008 - 2012 Xianghar  <xian@zron.de>
-- All Rights Reserved.
-- This code is not to be modified or distributed without written permission by the author.
-- Current distribution permissions only include curse.com, wowinterface.com and their respective addon updaters

if select(2,UnitClass("player")) ~= "SHAMAN" then return end

local addonName, TotemTimers = ...

local libmov = LibStub:GetLibrary("LibMovable-1.0")

local SpellIDs = TotemTimers.SpellIDs
local SpellTextures = TotemTimers.SpellTextures
local AvailableSpells = TotemTimers.AvailableSpells
local FlameShockID = SpellIDs.FlameShockDebuff
local FlameShockName = GetSpellInfo(SpellIDs.FlameShock)

local fsAnchor = CreateFrame("Frame", "TotemTimers_FSAnchor", UIParent)
TotemTimers.FSAnchor = fsAnchor
fsAnchor:SetPoint("CENTER", UIParent, "CENTER")
fsAnchor:SetWidth(100)
fsAnchor:SetHeight(16)
fsAnchor:Hide()
libmov.RegisterMovable("XiTimers", fsAnchor, XiTimers.getAnchorTable, FlameShockName)

local playerName = UnitName("player")
local role = 2

local fs = XiTimers:new()
fs.SetPoint = function() end
fs.SetTimerBarPos = function() end
fs.SetTimeSpacing = function() end

fs.button:ClearAllPoints()
fs.button:SetWidth(16)
fs.button:SetHeight(16)
fs.timerBar:SetWidth(100)
fs.timerBar:SetHeight(16)
fs.timerBar.background:SetAllPoints(fs.timerBar)
local oldsetwidth = fs.timerBar.SetHeight
fs.timerBar:ClearAllPoints()
fs.button:SetPoint("RIGHT", fsAnchor, "LEFT")
fs.timerBar:SetAllPoints(fsAnchor)

fs.button:Disable()
fs.button.icon:SetVertexColor(1,1,1)
TotemTimers.FlameshockBar = fs
fs.CustomConfig = true


local AuraGUID = nil
local FSName, FSEv, FSSource, FSTarget, FSSpell, FSBuffType, FSDuration, FSExpires, FSID = nil

local function CheckFSBuff(self, unit)
	local _
	local fsFound = false	
	FSName = ""
	local counter = 0
	while true do 
		counter = counter + 1
        FSName,_,_,_,FSDuration,FSExpires,FSSource,_,_,FSID = UnitDebuff(unit, counter)
		if not FSName then break end
        if FSID == FlameShockID and FSSource == "player" and FSDuration then
			self.timer:Start(FSExpires - FSDuration, FSExpires)
			fsFound = true
			break
        end		
	end
	if not fsFound then
		self.timer:Stop()
	end
end

function TotemTimers.FlameShockEvent(self,event,unit,...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local cevent = ...
		if cevent == "UNIT_DIED" then
            if AuraGUID and FSTarget == AuraGUID then
                self.timer:Stop(1)
                AuraGUID = nil
            end
        end
    elseif (event == "PLAYER_TARGET_CHANGED" and UnitExists("target"))
	  or (event == "UNIT_AURA" and unit == "target") then
        AuraGUID = UnitGUID("target")
        CheckFSBuff(self, "target")
	elseif event == "PET_BATTLE_OPENING_START" then
		if self:IsShown() then
			self.shownBeforePet = true
			self:Hide()
		end
	elseif event == "PET_BATTLE_CLOSE" then
		if self.shownBeforePet then
			self:Show()
			self.shownBeforePet = false
		end
    end
end

fs.button.icon:SetTexture(GetSpellTexture(SpellIDs.FlameShock))
fs.dontAlpha = true
fs.dontFlash = true
fs.timeStyle = "sec"
fs.button:SetAttribute("type1", "spell")
fs.button:SetAttribute("spell1", SpellIDs.FlameShock)
fs.button.icon:SetAlpha(1)
-- fs.reverseAlpha = true
fs.rangeCheck = SpellIDs.FlameShock
fs.manaCheck = SpellIDs.FlameShock
fs.button:SetScript("OnEvent", TotemTimers.FlameShockEvent)
fs.events[1] = "COMBAT_LOG_EVENT_UNFILTERED"
fs.events[2] = "UNIT_AURA"
fs.events[3] = "PLAYER_REGEN_ENABLED"
fs.events[4] = "PLAYER_REGEN_DISABLED"
fs.events[5] = "PLAYER_TARGET_CHANGED"
fs.forceBar = true
--fs:SetTimerBarPos("RIGHT")
fs:SetTimeWidth(100)
fs:SetBarColor(1,0.5,0)


