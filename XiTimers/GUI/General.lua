-- Copyright © 2008 - 2012 Xianghar  <xian@zron.de>
-- All Rights Reserved.
-- This code is not to be modified or distributed without written permission by the author.

local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

local nrfonts = 0

local L = LibStub("AceLocale-3.0"):GetLocale(Addon.XiTimersGUILocale, true)

local LSM = LibStub:GetLibrary("LibSharedMedia-3.0", true)

local LibDialog = LibStub:GetLibrary("LibDialog-1.0")


XiTimers.options = {
    type = "group",
    args = {
        general = {
            type = "group",
            name = "general",
            args = {
                version= {
                    order = 0,
                    type ="description",
                    name = L["Version"]..": "..tostring(GetAddOnMetadata("XiTimers", "Version"))
                },
				unlockspells = {
				    order = 1,
                    type = "execute",
                    name = L["Unlock Spells"],
                    desc = L["Unlock Spells Desc"],
                    func = function(info, val) XiTimers.ShowGrid() LibDialog:Spawn("XiTimers_Spells") InterfaceOptionsFrame:Hide() end,			
                    get = function(info) return XiTimers.ActiveProfile.UnlockSpells end,
				},
                unlock = {
                    order = 2,
                    type = "execute",
                    name = L["Unlock Bars"],
                    desc = L["Unlock Bars Desc"],
                    func = function(info, val) XiTimers.UnlockBars() LibDialog:Spawn("XiTimers_Bars") InterfaceOptionsFrame:Hide() end,
                },   
                flashred = {
                    order = 3,
                    type = "toggle",
                    name = L["Red Flash Color"],
                    desc = L["RedFlash Desc"],
                    set = function(info, val) XiTimers.ActiveProfile.FlashRed = val XiTimers.ProcessSetting("FlashRed") end,
                    get = function(info) return XiTimers.ActiveProfile.FlashRed end,
                }, 
                --[[stoppulse = {
                    order = 4,
                    type = "toggle",
                    name = L["Stop Pulse"],
                    desc = L["Stop Pulse Desc"],
                    set = function(info, val) XiTimers.ActiveProfile.StopPulse = val XiTimers.ProcessSetting("StopPulse") end,
                    get = function(info) return XiTimers.ActiveProfile.StopPulse end,
                },]]
                tooltips = {
                    order = 9,
                    type = "toggle",
                    name = L["Show Tooltips"],
                    desc = L["Shows tooltips of spells"],
                    set = function(info, val) XiTimers.ActiveProfile.Tooltips = val XiTimers.ProcessSetting("Tooltips") end,
                    get = function(info) return XiTimers.ActiveProfile.Tooltips end,
                },  
                tooltipsatbuttons = {
                    order = 10,
                    type = "toggle",
                    name = L["Tooltips At Buttons"],
                    desc = L["Tooltips At Buttons Desc"],
                    set = function(info, val) XiTimers.ActiveProfile.TooltipsAtButtons = val XiTimers.ProcessSetting("TooltipsAtButtons") end,
                    get = function(info) return XiTimers.ActiveProfile.TooltipsAtButtons end,
                },
                HideInVehicle = {
                    order = 11,
                    type = "toggle",
                    name = L["Hide In Vehicles"],
                    desc = L["Hide In Vehicles Desc"],
                    set = function(info, val) XiTimers.ActiveProfile.HideInVehicle = val XiTimers.ProcessSetting("HideInVehicle") end,
                    get = function(info) return XiTimers.ActiveProfile.HideInVehicle end,
                },                
                --[[Keybinds = {
                     order = 12,
                   type = "toggle",
                    name = L["Show Key Bindings"],
                    desc = L["Shows key bindings on buttons"],
                    set = function(info, val) XiTimers.ActiveProfile.ShowKeybinds = val XiTimers.ProcessSetting("ShowKeybinds") end,
                    get = function(info) return XiTimers.ActiveProfile.ShowKeybinds end,
                },  ]]               
				hm = {
					order = 200,
					type = "header",
					name = "",
				},
            },
        },
    },
}

if XiTimers.CustomGUI and XiTimers.CustomGUI.general then XiTimers.CustomGUI.general() end

local ACR =	LibStub("AceConfigRegistry-3.0")
ACR:RegisterOptionsTable(addonName, XiTimers.options)
local ACD = LibStub("AceConfigDialog-3.0")
local frame = ACD:AddToBlizOptions(addonName, addonName, nil, "general")
frame:SetScript("OnEvent", function(self) InterfaceOptionsFrame:Hide() end)
frame:HookScript("OnShow", function(self) if InCombatLockdown() then InterfaceOptionsFrame:Hide() end XiTimers.LastGUIPanel = self end)
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
XiTimers.LastGUIPanel = frame




