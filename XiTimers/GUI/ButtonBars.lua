-- Copyright © 2016 Xianghar  <xian@zron.de>
-- All Rights Reserved.
-- This code is not to be modified or distributed without written permission by the author.

local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

local L = LibStub("AceLocale-3.0"):GetLocale(Addon.XiTimersGUILocale, true)


XiTimers.options.args.buttonbars = {
    type = "group",
    name = "timers",
    args = {
    },
}

for i = 1,5 do
	XiTimers.options.args.buttonbars.args["hbar"..i] = {
		order = 100*i,
		type = "header",
		name = L["Bar"].." "..i
	}
	XiTimers.options.args.buttonbars.args["barbuttonpos"..i] = {
	    order = 100*i+1,
		type = "select",
		name = L["Move Active Buttons to"],
		desc = L["Move Active Buttons to Desc"],
		values = { ["center"] = L["Center"], ["left"] = L["Left"], ["right"] = L["Right"], ["grid"] = L["Don't Move"]},
		set = function(info, val)
					XiTimers.ActiveProfile.ActionBarButtonPosition[i] = val
					XiTimers.ProcessSetting("ActionBarButtonPosition")	
					XiTimers.PositionTimersOnBars(XiTimers.grid)
			  end,
		get = function(info) return XiTimers.ActiveProfile.ActionBarButtonPosition[i] end,
	}
end

local ACD = LibStub("AceConfigDialog-3.0")
local frame = ACD:AddToBlizOptions(addonName, L["Button Bars"], addonName, "buttonbars")
frame:SetScript("OnEvent", function(self) InterfaceOptionsFrame:Hide() end)
frame:HookScript("OnShow", function(self) if InCombatLockdown() then InterfaceOptionsFrame:Hide() end XiTimers.LastGUIPanel = self end)
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
