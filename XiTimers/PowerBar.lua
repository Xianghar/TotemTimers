local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

if XiTimers.PowerBar then return end
local libmov = LibStub:GetLibrary("LibMovable-1.0")


local powerbar = CreateFrame("StatusBar", "XiTimers_PowerBar", UIParent, "XiTimersTimerBarTemplate")
powerbar:ClearAllPoints()
powerbar:SetPoint("CENTER", UIParent, "CENTER")
powerbar:Hide()
libmov.RegisterMovable("XiTimers", powerbar, XiTimers.getAnchorTable, "Power Bar")


XiTimers.PowerBar = powerbar
powerbar.text = getglobal("XiTimers_PowerBarTime")
powerbar.background = getglobal("XiTimers_PowerBarBackground")
powerbar.text:Show()
powerbar.background:Show()
powerbar.background:SetAllPoints(powerbar)
powerbar:SetWidth(100)
powerbar:SetScript("OnEnter", nil)
powerbar:SetScript("OnLeave", nil)
powerbar.OOCAlpha = 0.4


local function PowerBar_UpdateValue(self)
	local currentPower = UnitPower("player",self.powerIndex);
	self:SetValue(currentPower);
	self.value = currentPower
	self.text:SetText(currentPower)
end

local function PowerBar_UpdateMaxValues(self)
	local maxPower = UnitPowerMax("player",self.powerIndex);
	self:SetMinMaxValues(0, maxPower);
end

local function PowerBar_OnEvent(self, event, unit)
	if event == "UNIT_DISPLAYPOWER" or event == "UPDATE_VEHICLE_ACTIONBAR" then
		PowerBar_UpdateValue(self)
	elseif event=="PLAYER_ENTERING_WORLD" then
		PowerBar_UpdateMaxValues(self)
		PowerBar_UpdateValue(self)
	elseif event == "UNIT_MAXPOWER" and unit == "player" then
		PowerBar_UpdateMaxValues(self)
	elseif self:IsShown() then
		if event == "UNIT_POWER_UPDATE" and unit == "player" then
			PowerBar_UpdateValue(self)
		end
	end
end

function powerbar.enable(self)
	self.active = true
	if ( not self.powerName ) then
		self.powerName = "MANA";
		self.powerIndex = 0;
	end
	
	self:RegisterEvent("UNIT_POWER_UPDATE");
	self:RegisterEvent("UNIT_MAXPOWER");
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:RegisterEvent("UNIT_DISPLAYPOWER");
	self:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR");
	
	local info = PowerBarColor[self.powerName]
	self:SetStatusBarColor(info.r, info.g, info.b)
	PowerBar_UpdateMaxValues(self)
	self.background:SetStatusBarColor(info.r, info.g, info.b, 0.4)
	self.background:SetValue(1)
	if not InCombatLockdown() and not XiTimers.ActiveProfile.PowerBarHideOOC then
		powerbar:Show()
	end
end

function powerbar.disable(self)
	self.active = false
	self:UnregisterAllEvents()
	self:Hide()
end

powerbar:SetScript("OnEvent", PowerBar_OnEvent)
powerbar:SetScript("OnUpdate", PowerBar_UpdateValue)