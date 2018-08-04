local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

local L = LibStub("AceLocale-3.0"):GetLocale(Addon.XiTimersGUILocale, true)


local SelectedProfile = "default"
local NameInput = ""
local CopyFrom = "default"
local CopyTo = "default"

local function CreateProfileList()
    local v = {}
    for k,_ in pairs(XiTimers_Profiles) do
        v[k] = k
    end
    v["default"] = L["default"]
    return v
end

XiTimers.options.args.profiles = {
    type = "group",
    name = "profiles",
    args = {
        ["select"] = {
            order = 1,
            type = "group",
            name = L["Select Profiles"],
            childGroups = "tab",
            args = {}
		},
        ["manage"] = {
            order = 2,
            type = "group",
            name = L["Manage Profiles"],
            childGroups = "tab",
            args = {
                ["select"] = {
                    order = 1,
                    type = "select",
                    name = L["Profile"],
                    values = CreateProfileList,
                    set = function(info, val)
                        SelectedProfile = val
                    end,
                    get = function(info) return SelectedProfile end,
                },
                ["name"] = {
                    order = 2,
                    type = "input",
                    name = L["New Name"],
                    get = function(info) return NameInput end,
                    set = function(info, val) NameInput = val end,
                },
                ["create"] = {
                    order = 3,
                    type = "execute",
                    name = L["Create Profile"],
                    func = function(info) 
                        if NameInput ~= "" then
                            if XiTimers_Profiles[NameInput] or NameInput == L["default"] or NameInput == "default" then
                                print(L["Profile already exists."])
                            else
                                XiTimers.CreateProfile(NameInput)
                                SelectedProfile = NameInput
                                frame:Show()
                            end
                        else
                            print(L["You need to enter a profile name first."])
                        end
                    end,
                },
                ["delete"] = {
                    order = 5,
                    type = "execute",
                    name = L["Delete Profile"],
                    func = function(info)
						if SelectedProfile == "defeault" then return end
                        XiTimers.DeleteProfile(SelectedProfile)
                        XiTimers.SelectActiveProfile()
                        XiTimers.ExecuteProfile()
                        SelectedProfile = "default"
                        frame:Show()
                    end,
                    confirm = true,
                    confirmText = L["Really delete profile?"],
                },
                ["reset"] = {
                    order = 6,
                    type = "execute",
                    name = L["Reset Profile"],
                    func = function(info) XiTimers.ResetProfile(SelectedProfile) end,
                    confirm = true,
                    confirmText = L["Really reset profile?"],
                },
                ["resetFramePos"] = {
                    order = 7,
                    type = "execute",
                    name = L["Reset Frame Positions"],
                    func = function(info) XiTimers.ResetProfilePositions(SelectedProfile) end,
                    confirm = true,
                    confirmText = L["Really reset frame positions?"],
                },
                ["h1"] = {
                    order = 8,
                    type = "header",
                    name = L["Copy Settings"],
                },
                copyFrom = {
                    order = 15,
                    type = "select",
                    name = L["Copy From"],
                    values = CreateProfileList,
                    set = function(info, val)
                        CopyFrom = val
                    end,
                    get = function(info) return CopyFrom end,
                },
                copyTo = {
                    order = 16,
                    type = "select",
                    name = L["Copy To"],
                    values = CreateProfileList,
                    set = function(info, val)
                        CopyTo = val
                    end,
                    get = function(info) return CopyTo end,
                },
                copyAll = {
                    order = 17,
                    type = "execute",
                    name = L["Copy All"],
                    func = function()
                        XiTimers.CopyProfile(CopyFrom, CopyTo)
                        XiTimers.ExecuteProfile()
                    end,
                },
                copyFramePos = {
                    order = 18,
                    type = "execute",
                    name = L["Copy Frame Positions"],
                    func = function()
                        XiTimers.CopyFramePositions(CopyFrom, CopyTo)
                        XiTimers.ExecuteProfile()
                    end,
                },
            },
        },
    },
}

local ACD = LibStub("AceConfigDialog-3.0")
local frame = ACD:AddToBlizOptions(addonName, L["Profiles"], addonName, "profiles")

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	for i=1,GetNumSpecializations() do
		XiTimers.options.args.profiles.args.select.args[tostring(i)] = {
			order = i,
			type = "group",
			name = select(2, GetSpecializationInfo(i)),
			args = {
				["solo"] = {
					type = "select",
					name = L["Solo"],
					values = CreateProfileList,
					set = function(info, val)
						XiTimers_GlobalSettings.Profiles[UnitName("player")][i].none = val
						XiTimers.SelectActiveProfile()
						XiTimers.ExecuteProfile()
					end,
					get = function(info) return XiTimers_GlobalSettings.Profiles[UnitName("player")][i].none end,
				},
				["party"] = {
					type = "select",
					name = L["Party"],
					values = CreateProfileList,
					set = function(info, val)
						XiTimers_GlobalSettings.Profiles[UnitName("player")][i].party = val
						XiTimers.SelectActiveProfile()
						XiTimers.ExecuteProfile()
					end,
					get = function(info) return XiTimers_GlobalSettings.Profiles[UnitName("player")][i].party end,
				},
				["arena"] = {
					type = "select",
					name = L["Arena"],
					values = CreateProfileList,
					set = function(info, val)
						XiTimers_GlobalSettings.Profiles[UnitName("player")][i].arena = val
						XiTimers.SelectActiveProfile()
						XiTimers.ExecuteProfile()
					end,
					get = function(info) return XiTimers_GlobalSettings.Profiles[UnitName("player")][i].arena end,
				},
				["pvp"] = {
					type = "select",
					name = L["Battleground"],
					values = CreateProfileList,
					set = function(info, val)
						XiTimers_GlobalSettings.Profiles[UnitName("player")][i].pvp = val
						XiTimers.SelectActiveProfile()
						XiTimers.ExecuteProfile()
					end,
					get = function(info) return XiTimers_GlobalSettings.Profiles[UnitName("player")][i].pvp end,
				},
				["raid"] = {
					type = "select",
					name = L["Raid"],
					values = CreateProfileList,
					set = function(info, val)
						XiTimers_GlobalSettings.Profiles[UnitName("player")][i].raid = val
						XiTimers.SelectActiveProfile()
						XiTimers.ExecuteProfile()
					end,
					get = function(info) return XiTimers_GlobalSettings.Profiles[UnitName("player")][i].raid end,
				},
				["scenario"] = {
					type = "select",
					name = L["Scenario"],
					values = CreateProfileList,
					set = function(info, val)
						XiTimers_GlobalSettings.Profiles[UnitName("player")][i].scenario = val
						XiTimers.SelectActiveProfile()
						XiTimers.ExecuteProfile()
					end,
					get = function(info) return XiTimers_GlobalSettings.Profiles[UnitName("player")][i].scenario end,
				},
			},
		}
	end
	frame:UnregisterAllEvents()
	frame:SetScript("OnEvent", function(self) InterfaceOptionsFrame:Hide() end)
	frame:HookScript("OnShow", function(self) if InCombatLockdown() then InterfaceOptionsFrame:Hide() end XiTimers.LastGUIPanel = self end)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
end)




