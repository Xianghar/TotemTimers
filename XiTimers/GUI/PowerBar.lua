local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

local L = LibStub("AceLocale-3.0"):GetLocale(Addon.XiTimersGUILocale, true)


XiTimers.options.args.powerbars = {
    type = "group",
    name = "powerbars",
    args = {
		OOCAlpha = {
            order = 8,
            type = "range",
            name = L["OOC Alpha"],
			desc = L["OOC Alpha Desc"],
            min = 0.1,
            max = 1,
            step = 0.1,
            bigStep = 0.1,
            set = function(info, val)
                        XiTimers.ActiveProfile.PowerBarOOCAlpha = val  XiTimers.ProcessSetting("PowerBarOOCAlpha")	
						XiTimers.LoadProfile()
                  end,
            get = function(info) return XiTimers.ActiveProfile.PowerBarOOCAlpha end,
        },
		hideooc = {
			order = 9,
			type = "toggle",
			name = L["Hide out of combat"],
			set = function(info, val)
						XiTimers.ActiveProfile.PowerBarHideOOC = val
						XiTimers.invokeOOCFader()
					end,
			get = function(info) return XiTimers.ActiveProfile.PowerBarHideOOC end,
        },
		hsize = {
		    order = 10,
            type = "header",
            name = "",
		},
		PowerBarSize = {
            order = 11,
            type = "range",
            name = L["Scaling"],
            min = 0.5,
            max = 4,
            step = 0.1,
            bigStep = 0.1,
            set = function(info, val)
                        XiTimers.ActiveProfile.PowerBarSize = val  XiTimers.ProcessSetting("PowerBarSize")	
                  end,
            get = function(info) return XiTimers.ActiveProfile.PowerBarSize end,
        },
		PowerBarWidth = {
            order = 12,
            type = "range",
            name = L["Width"],
            min = 50,
            max = 200,
            step = 1,
            bigStep = 10,
            set = function(info, val)
                        XiTimers.ActiveProfile.PowerBarWidth = val  XiTimers.ProcessSetting("PowerBarWidth")	
						XiTimers.LoadProfile()
                  end,
            get = function(info) return XiTimers.ActiveProfile.PowerBarWidth end,
        },
        powerBarFontSize = {
            order = 13,
            type = "range",
            name = L["Font Size"],
            min = 5,
            max = 30,
            step = 1,
            set = function(info, val)
                        XiTimers.ActiveProfile.PowerBarFontSize = val  XiTimers.ProcessSetting("PowerBarFontSize")
                  end,
            get = function(info) return XiTimers.ActiveProfile.PowerBarFontSize end,
        },
		h2 = {
            order = 30,
            type = "header",
            name = "",
        },
		PowerBarFontColor = {
			order = 34,
			type = "color",
			name = L["Font Color"],
			set = function(info, r,g,b)
				XiTimers.ActiveProfile.PowerBarFontColor.r = r
				XiTimers.ActiveProfile.PowerBarFontColor.g = g
				XiTimers.ActiveProfile.PowerBarFontColor.b = b
				XiTimers.ProcessSetting("PowerBarFontColor")
			end,
			get = function(info) return XiTimers.ActiveProfile.PowerBarFontColor.r,
										XiTimers.ActiveProfile.PowerBarFontColor.g,
										XiTimers.ActiveProfile.PowerBarFontColor.b,
										1
				  end,
		},
		PowerBarFont = {
			order = 41,
			type = "select",
			name = L["Font"] ,
			values = AceGUIWidgetLSMlists.font,
			set = function(info, val) XiTimers.ActiveProfile.PowerBarFont = val XiTimers.ProcessSetting("PowerBarFont") end,
			get = function(info) return XiTimers.ActiveProfile.PowerBarFont end,
			dialogControl = "LSM30_Font",
		},
		PowerBarTexture = {
			order = 42,
			type = "select",
			name = L["Texture"],
			values = AceGUIWidgetLSMlists.statusbar,
			set = function(info, val) XiTimers.ActiveProfile.PowerBarTexture = val XiTimers.ProcessSetting("PowerBarTexture") end,
			get = function(info) return XiTimers.ActiveProfile.PowerBarTexture end,
			dialogControl = "LSM30_Statusbar",
		},		

    },	
}


local ACD = LibStub("AceConfigDialog-3.0")
local frame = ACD:AddToBlizOptions(addonName, L["Power Bars"], addonName, "powerbars")
frame:SetScript("OnEvent", function(self) InterfaceOptionsFrame:Hide() end)
frame:HookScript("OnShow", function(self) if InCombatLockdown() then InterfaceOptionsFrame:Hide() end XiTimers.LastGUIPanel = self end)
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
