-- Copyright © 2008 - 2012 Xianghar  <xian@zron.de>
-- All Rights Reserved.
-- This code is not to be modified or distributed without written permission by the author.
-- Current distribution permissions only include curse.com, wowinterface.com and their respective addon updaters

local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

local SpellIDs = XiTimers.SpellIDs

XiTimers.DefaultGlobalSettings = {
	Version = Addon.XiTimersSettingsVersion,
    Profiles = {},
    Sink = {}
}

XiTimers_Profiles = {
    ["default"] = {}
}
XiTimers_GlobalSettings = {}

XiTimers.DefaultProfile = {

    --General            
        FlashRed = true,
        ShowTimerBars = true,

        Tooltips = true,
        TooltipsAtButtons = false,
        TimeFont = "Friz Quadrata TT",
        TimeColor = {r=1,g=1,b=1},
        TimerBarTexture = "Blizzard",
        TimerBarColor = {r=0.5,g=0.5,b=1.0,a=1.0},
		BuffBarColor = {r=0.6,g=0.6,b=1.0,a=0.7},
        ShowKeybinds = true,
        HideInVehicle = true,
        StopPulse = true,
        TimersOnButtons = true,
		PowerBarFontColor = {r=1,g=0.82,b=0,a=1.0},
		PowerBarTexture = "Blizzard",
		PowerBarFont = "Friz Quadrata TT",
		PowerBarSize = 1,
		PowerBarWidth = 100,
		PowerBarFontSize = 10,
		OOCAlpha = 0.4,
		PowerBarOOCAlpha = 0.4,
		PowerBarHideOOC = false,
		HideOOC = false,
		ActiveCooldownAlpha = 0.4,
		

		
		ActionBarButtonPosition = {
			"center",
			"center",
			"center",
			"right",
			"left",
		},

        TimeStyle = "mm:ss",
        TimerTimePos = "BOTTOM",   
        TimerSize = 32,
        TimerTimeHeight = 12,	
        TimerSpacing = 5,
        TimerTimeSpacing = 0,
        ProcFlash = true,
        Clickthrough = false,

		["Anchors"] = {
			["XiTimersBar5"] = {
				["pointFrom"] = "RIGHT",
				["xOffset"] = -139.559768676758,
				["pointTo"] = "RIGHT",
				["yOffset"] = -107.200096130371,
			},
			["XiTimersBar1"] = {
				["yOffset"] = -107.199920654297,
			},
			["XiTimersBar3"] = {
				["pointFrom"] = "LEFT",
				["pointTo"] = "LEFT",
				["xOffset"] = 139.466781616211,
				["yOffset"] = -72.0003509521484,
			},
			["XiTimers_PowerBar"] = {
				["pointFrom"] = "BOTTOM",
				["pointTo"] = "BOTTOM",
				["yOffset"] = 210.564834594727,
			},
			["XiTimersBar2"] = {
				["xOffset"] = 4.66856909042690e-005,
				["yOffset"] = -142.400451660156,
			},
			["XiTimersBar4"] = {
				["pointFrom"] = "LEFT",
				["xOffset"] = 139.426254272461,
				["pointTo"] = "LEFT",
				["yOffset"] = -107.199775695801,
			},
		},

}

XiTimers.ActiveProfile = XiTimers_Profiles.default


local function copy(object) 
    if type(object) ~= "table" then
        return object
    else
        local newtable = {}
        for k,v in pairs(object) do
            newtable[k] = copy(v)
        end
        return newtable
    end
end




function XiTimers.CreateProfile(name)
    if not XiTimers_Profiles[name] then
        XiTimers.ResetProfile(name)
        return true
    else
        return false
    end
end


function XiTimers.DeleteProfile(name)
    if name == "default" then return end
    XiTimers_Profiles[name] = nil
    for u,p in pairs(XiTimers_GlobalSettings.Profiles) do
        for i = 1,3 do
            for _,v in pairs({"none","party","arena","pvp","raid"}) do
                if p[i][v] == name then
                    p[i][v] = "default"
                end
            end
        end
    end
end

function XiTimers.ResetProfile(name)
    XiTimers_Profiles[name] = copy(XiTimers.DefaultProfile)
end

function XiTimers.ResetAllProfiles()
	wipe(XiTimers_Profiles)
    XiTimers_Profiles.default = {}
    XiTimers.ResetProfile("default")
end

function XiTimers.SelectActiveProfile()
    local player = UnitName("player")
    local specialization = GetSpecialization()
    if not specialization then specialization = 2 end
    local _,instance = IsInInstance()
	if not instance then instance = "party" end
    XiTimers.ActiveProfile = XiTimers_Profiles[XiTimers_GlobalSettings.Profiles[player][specialization][instance]] or XiTimers_Profiles.default
	XiTimers.SetProfile(XiTimers.ActiveProfile)
end


function XiTimers.ExecuteProfile()
	XiTimers.ProcessAllSettings()
	XiTimers.LoadProfile()    
end

local SettingsConverters = {
}

	
function XiTimers.UpdateProfiles()

    if not XiTimers_Profiles then XiTimers_Profiles = {default={}} print("default") end
    
	if not XiTimers_GlobalSettings.Version or XiTimers_GlobalSettings.Version < Addon.XiTimersSettingsVersion then
		print(addonName..": Too old or no saved settings found, loading defaults...")
        wipe(XiTimers_GlobalSettings)
		XiTimers.ResetAllProfiles()
	--[[elseif XiTimers_GlobalSettings.Version ~= Version then
        if not SettingsConverters[XiTimers_GlobalSettings.Version] then
            --DEFAULT_CHAT_FRAME:AddMessage("TotemTimers: Unknown settings found, loading defaults...")
            wipe(XiTimers_GlobalSettings)
            XiTimers.ResetAllProfiles()
        else
            while SettingsConverters[XiTimers_GlobalSettings.Version] do
                SettingsConverters[XiTimers_GlobalSettings.Version]()
            end
        end]]
    end

	for k,v in pairs(XiTimers.DefaultProfile) do
        for _,profile in pairs(XiTimers_Profiles) do
            if profile[k] == nil then
                profile[k] = copy(v)
            end
        end
	end
    
    for k,v in pairs(XiTimers.DefaultGlobalSettings) do
        if XiTimers_GlobalSettings[k] == nil then
            XiTimers_GlobalSettings[k] = copy(v)
        end
    end
    
    local player = UnitName("player")
    if not XiTimers_GlobalSettings.Profiles[player] then
        XiTimers_GlobalSettings.Profiles[player] = {
            [1] = {none="default",pvp="default",arena="default",party="default",raid="default",scenario="default"},
            [2] = {none="default",pvp="default",arena="default",party="default",raid="default",scenario="default"},
            [3] = {none="default",pvp="default",arena="default",party="default",raid="default",scenario="default"},
        }
    end
end

function XiTimers.ResetProfilePositions(name)
    XiTimers_Profiles[name].Anchors = copy(XiTimers.DefaultProfile.Anchors)
	local libmov = LibStub:GetLibrary("LibMovable-1.0")
    libmov.UpdateMovableLayout("XiTimers")
end

function XiTimers.CopyProfile(p1,p2)
    XiTimers_Profiles[p2] = copy(XiTimers_Profiles[p1])
end

function XiTimers.CopyFramePositions(p1, p2)
    XiTimers_Profiles[p2].Anchors = copy(XiTimers_Profiles[p1].Anchors)
	local libmov = LibStub:GetLibrary("LibMovable-1.0")
    libmov.UpdateMovableLayout("XiTimers")
end

