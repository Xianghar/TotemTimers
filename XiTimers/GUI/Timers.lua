-- Copyright © 2008 - 2016 Xianghar  <xian@zron.de>
-- All Rights Reserved.
-- This code is not to be modified or distributed without written permission by the author.

local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

local L = LibStub("AceLocale-3.0"):GetLocale(Addon.XiTimersGUILocale, true)


XiTimers.options.args.timers = {
    type = "group",
    name = "timers",
    args = {
        clickthrough = {
            order = 1,
            type = "toggle", 
            name = L["Clickthrough"],
            desc = L["Clickthrough Desc"],
            set = function(info, val) XiTimers.ActiveProfile.Clickthrough = val  XiTimers.ProcessSetting("Clickthrough") end,
            get = function(info) return XiTimers.ActiveProfile.Clickthrough end,
        },
        h1 = {
            order = 2,
            type = "header",
            name = "",
        },
		OOCAlpha = {
            order = 3,
            type = "range",
            name = L["OOC Alpha"],
			desc = L["OOC Alpha Desc"],
            min = 0.1,
            max = 1,
            step = 0.1,
            bigStep = 0.5,
            set = function(info, val)
                        XiTimers.ActiveProfile.OOCAlpha = val  XiTimers.ProcessSetting("OOCAlpha")	
						XiTimers.LoadProfile()
                  end,
            get = function(info) return XiTimers.ActiveProfile.OOCAlpha end,
        },
		hideooc = {
			order = 4,
			type = "toggle",
			name = L["Hide out of combat"],
			set = function(info, val)
						XiTimers.ActiveProfile.HideOOC = val
						XiTimers.ProcessSetting("HideOOC")
					end,
			get = function(info) return XiTimers.ActiveProfile.HideOOC end,
        },
		ActiveCooldownAlpha = {
            order = 3,
            type = "range",
            name = L["Active Cooldown Transparency"],
			name = L["Active Cooldown Transparency Desc"],
            min = 0.1,
            max = 1,
            step = 0.1,
            bigStep = 0.5,
            set = function(info, val)
                        XiTimers.ActiveProfile.ActiveCooldownAlpha = val  XiTimers.ProcessSetting("ActiveCooldownAlpha")	
						XiTimers.LoadProfile()
                  end,
            get = function(info) return XiTimers.ActiveProfile.ActiveCooldownAlpha end,
        },
		hbars = {
		    order = 10,
            type = "header",
            name = "",
		},
		showTimerBars = {
			order = 5,
			type = "toggle",
			name = L["Show Timer Bars"],
			desc = L["Show Timer Bars Desc"],
			set = function(info, val) XiTimers.ActiveProfile.ShowTimerBars = val XiTimers.ProcessSetting("ShowTimerBars") end,
			get = function(info) return XiTimers.ActiveProfile.ShowTimerBars end,
		},
		timersonbuttons = {
			order = 6,
			type = "toggle",
			name = L["Timers On Buttons"],
			desc = L["Timers On Buttons Desc"],
			set = function(info, val) 
				XiTimers.ActiveProfile.TimersOnButtons = val 
				XiTimers.ProcessSetting("TimersOnButtons")
				for i=1,#XiTimers.timers do
					XiTimers.timers[i]:SetTimerBarPos(XiTimers.timers[i].timerBarPos)
				end
			end,
			get = function(info) return XiTimers.ActiveProfile.TimersOnButtons end,
		},
        time = {
            order = 8,
            type = "select",
            name = L["Time Style"],
            desc = L["Time Style Desc"],
            values = {["mm:ss"] = "mm:ss", blizz = L["Blizz Style"], },
            set = function(info, val)
                        XiTimers.ActiveProfile.TimeStyle = val  XiTimers.ProcessSetting("TimeStyle")
                  end,
            get = function(info) return XiTimers.ActiveProfile.TimeStyle end,
        },
        timepos = {
            order = 9,
            type = "select",
            name = L["Timer Bar Position"],
            desc = L["Timer Bar Position Desc"],
            values = {	["TOP"] = L["Top"], ["BOTTOM"] = L["Bottom"],},
            set = function(info, val)
                        XiTimers.ActiveProfile.TimerTimePos = val  XiTimers.ProcessSetting("TimerTimePos")	
                  end,
            get = function(info) return XiTimers.ActiveProfile.TimerTimePos end,
        },
        sizes = {
            order = 10,
            type = "header",
            name = L["Scaling"],
        },
        timerSize = {
            order = 11,
            type = "range",
            name = L["Scaling"],
            desc = L["Scales the timer buttons"],
            min = 16,
            max = 96,
            step = 1,
            bigStep = 2,
            set = function(info, val)
                        XiTimers.ActiveProfile.TimerSize = val  XiTimers.ProcessSetting("TimerSize")	
						XiTimers.LoadProfile()
                  end,
            get = function(info) return XiTimers.ActiveProfile.TimerSize end,
        },
        timerTimeHeight = {
            order = 12,
            type = "range",
            name = L["Time Font Size"],
            desc = L["Sets the font size of time strings"],
            min = 6,
            max = 40,
            step = 1,
            set = function(info, val)
                        XiTimers.ActiveProfile.TimerTimeHeight = val  XiTimers.ProcessSetting("TimerTimeHeight")
                  end,
            get = function(info) return XiTimers.ActiveProfile.TimerTimeHeight end,
        },
        spacing = {
            order = 13,
            type = "range",
            name = L["Spacing"] ,
            desc = L["Sets the space between timer buttons"],
            min = -2,
            max = 20,
            step = 1,
            set = function(info, val)
                        XiTimers.ActiveProfile.TimerSpacing = val  XiTimers.ProcessSetting("TimerSpacing")	
						XiTimers.LoadProfile()
                  end,
            get = function(info) return XiTimers.ActiveProfile.TimerSpacing end,
        },
        timeSpacing = {
            order = 14,
            type = "range",
            name = L["Time Spacing"],
            desc = L["Sets the space between timer buttons and timer bars"],
            min = 0,
            max = 20,
            step = 1,
            set = function(info, val)
                        XiTimers.ActiveProfile.TimerTimeSpacing = val  XiTimers.ProcessSetting("TimerTimeSpacing")	
                  end,
            get = function(info) return XiTimers.ActiveProfile.TimerTimeSpacing end,
        },
        --[[timerBarWidth = {
            order = 15,
            type = "range",
            name = L["Timer Bar Width"],
            desc = L["Timer Bar Width Desc"],
            min = 36,
            max = 300,
            step = 4,
            set = function(info, val)
                        XiTimers.ActiveProfile.TotemTimerBarWidth = val  XiTimers.ProcessSetting("TotemTimerBarWidth")	
                  end,
            get = function(info) return XiTimers.ActiveProfile.TotemTimerBarWidth end,
        },]]
		h2 = {
			order = 30,
			type = "header",
			name = "",
		},
		BuffBarColor = {
			order = 32,
			type = "color",
			name = L["Buff Color"],
			desc = L["Buff Color Desc"],
			hasAlpha = true,
			set = function(info, r,g,b,a)
				XiTimers.ActiveProfile.BuffBarColor.r = r
				XiTimers.ActiveProfile.BuffBarColor.g = g
				XiTimers.ActiveProfile.BuffBarColor.b = b
				XiTimers.ActiveProfile.BuffBarColor.a = a
				XiTimers.ProcessSetting("BuffBarColor")
			end,
			get = function(info) return XiTimers.ActiveProfile.BuffBarColor.r,
										XiTimers.ActiveProfile.BuffBarColor.g,
										XiTimers.ActiveProfile.BuffBarColor.b,
										XiTimers.ActiveProfile.BuffBarColor.a
				  end,
		},
		TimeColor = {
			order = 34,
			type = "color",
			name = L["Time Color"],
			desc = L["Time Color Desc"],
			set = function(info, r,g,b)
				XiTimers.ActiveProfile.TimeColor.r = r
				XiTimers.ActiveProfile.TimeColor.g = g
				XiTimers.ActiveProfile.TimeColor.b = b
				XiTimers.ProcessSetting("TimeColor")
			end,
			get = function(info) return XiTimers.ActiveProfile.TimeColor.r,
										XiTimers.ActiveProfile.TimeColor.g,
										XiTimers.ActiveProfile.TimeColor.b,
										1
				  end,
		},	
		TimerBarColor = {
			order = 35,
			type = "color",
			name = L["Timer Bar Color"],
			hasAlpha = true,
			set = function(info, r,g,b,a)
				XiTimers.ActiveProfile.TimerBarColor.r = r
				XiTimers.ActiveProfile.TimerBarColor.g = g
				XiTimers.ActiveProfile.TimerBarColor.b = b
				XiTimers.ActiveProfile.TimerBarColor.a = a
				XiTimers.ProcessSetting("TimerBarColor")
			end,
			get = function(info) return XiTimers.ActiveProfile.TimerBarColor.r,
										XiTimers.ActiveProfile.TimerBarColor.g,
										XiTimers.ActiveProfile.TimerBarColor.b,
										XiTimers.ActiveProfile.TimerBarColor.a
				  end,
		},
		h3 = {
			order = 40,
			type = "header",
			name = "",
		},
		TimerBarTexture = {
			order = 41,
			type = "select",
			name = L["Timer Bar Texture"],
			values = AceGUIWidgetLSMlists.statusbar,
			set = function(info, val) XiTimers.ActiveProfile.TimerBarTexture = val XiTimers.ProcessSetting("TimerBarTexture") end,
			get = function(info) return XiTimers.ActiveProfile.TimerBarTexture end,
			dialogControl = "LSM30_Statusbar",
		},  
	
		TimeFont = {
			order = 42,
			type = "select",
			name = L["Time Font"] ,
			values = AceGUIWidgetLSMlists.font,
			set = function(info, val) XiTimers.ActiveProfile.TimeFont = val XiTimers.ProcessSetting("TimeFont") end,
			get = function(info) return XiTimers.ActiveProfile.TimeFont end,
			dialogControl = "LSM30_Font",
		}, 


                                   
    },
}


local ACD = LibStub("AceConfigDialog-3.0")
local frame = ACD:AddToBlizOptions(addonName, L["Timers"], addonName, "timers")
frame:SetScript("OnEvent", function(self) InterfaceOptionsFrame:Hide() end)
frame:HookScript("OnShow", function(self) if InCombatLockdown() then InterfaceOptionsFrame:Hide() end XiTimers.LastGUIPanel = self end)
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
