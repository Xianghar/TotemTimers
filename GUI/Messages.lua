if select(2,UnitClass("player")) ~= "SHAMAN" then return end


local sink = LibStub("LibSink-2.0")
--[[if sink then
    TotemTimers.options.args.messages = sink.GetSinkAce3OptionsDataTable(TotemTimers)
else
    TotemTimers.options.args.messages = {}
end]]

--[[for k,v in pairs(TotemTimers.options.args.messages.args) do
    if v.order and v.order < 0 then v.order = v.order - 50 end
end]]

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers_GUI", true)

TotemTimers.options.args.messages = {
    order = 4,
    type = "group",
    name = "Warnings",
    -- tab: in the /tt window the warning groups are a tree inside the page (in a "Warnings" tab)
    -- instead of being added to the window's left column
    childGroups = "tab",
    args = {
        ActivateHiddenTimers = {
            order = 0,
            type = "toggle",
            name = L["Show warnings of disabled trackers"],
            desc = L["disabled warnings desc"],
            width = 'full',
            set = function(info, val)
                      TotemTimers.ActiveProfile.ActivateHiddenTimers = val
                      TotemTimers.ProcessSetting("ActivateHiddenTimers")
                  end,
            get = function(info) return TotemTimers.ActiveProfile.ActivateHiddenTimers end,
        },
        Messages = {
            order = 1,
            type = "group",
            name = L["Warnings"],
            args = {
                output = sink.GetSinkAce3OptionsDataTable(TotemTimers),
                TotemExpirationMsg = {
                    order = 2,
                    type = "group",
                    name = L["Totem Expiration Message"],
                    desc = L["Totem Expiration Desc"],
                    args = {
                        enable = {
                            order = 0,
                            type = "toggle",
                            name = L["Enable"],
                            set = function(info, val) TotemTimers.ActiveProfile.Warnings.TotemExpiration.enabled = val end,
                            get = function(info) return TotemTimers.ActiveProfile.Warnings.TotemExpiration.enabled end,
                        },
                        color =  {
                            order = 1,
                            type = "color",
                            name = L["Color"],
                            hasAlpha = false,
                            set = function(info, r,g,b)
                                TotemTimers.ActiveProfile.Warnings.TotemExpiration.r = r
                                TotemTimers.ActiveProfile.Warnings.TotemExpiration.g = g
                                TotemTimers.ActiveProfile.Warnings.TotemExpiration.b = b
                            end,
                            get = function(info)
                                return TotemTimers.ActiveProfile.Warnings.TotemExpiration.r,
                                       TotemTimers.ActiveProfile.Warnings.TotemExpiration.g,
                                       TotemTimers.ActiveProfile.Warnings.TotemExpiration.b, 1
                            end,
                        },
                        sound = {
                            order = 2,
                            type = "select",
                            name = L["Sound"],
                            values = AceGUIWidgetLSMlists.sound,
                            set = function(info, val) TotemTimers.ActiveProfile.Warnings.TotemExpiration.sound = val end,
                            get = function(info) return TotemTimers.ActiveProfile.Warnings.TotemExpiration.sound end,
                            dialogControl = "LSM30_Sound",
                        },
                        nosound = {
                            order = 3,
                            type = "execute", 
                            name = L["No Sound"],
                            func = function(info) TotemTimers.ActiveProfile.Warnings.TotemExpiration.sound = "" end,
                        },
                    },
                },
                TotemDestroyedMsg = {
                    order = 3,
                    type = "group",
                    name = L["Totem Destruction Message"],
                    desc = L["Totem Desctruction Desc"],
                    args = {
                        enable = {
                            order = 0,
                            type = "toggle",
                            name = L["Enable"],
                            set = function(info, val) TotemTimers.ActiveProfile.Warnings.TotemDestroyed.enabled = val end,
                            get = function(info) return TotemTimers.ActiveProfile.Warnings.TotemDestroyed.enabled end,
                        },
                        color =  {
                            order = 1,
                            type = "color",
                            name = L["Color"],
                            hasAlpha = false,
                            set = function(info, r,g,b)
                                TotemTimers.ActiveProfile.Warnings.TotemDestroyed.r = r
                                TotemTimers.ActiveProfile.Warnings.TotemDestroyed.g = g
                                TotemTimers.ActiveProfile.Warnings.TotemDestroyed.b = b
                            end,
                            get = function(info)
                                return TotemTimers.ActiveProfile.Warnings.TotemDestroyed.r,
                                       TotemTimers.ActiveProfile.Warnings.TotemDestroyed.g,
                                       TotemTimers.ActiveProfile.Warnings.TotemDestroyed.b, 1
                            end,
                        },
                        sound = {
                            order = 2,
                            type = "select",
                            name = L["Sound"],
                            values = AceGUIWidgetLSMlists.sound,
                            set = function(info, val) TotemTimers.ActiveProfile.Warnings.TotemDestroyed.sound = val end,
                            get = function(info) return TotemTimers.ActiveProfile.Warnings.TotemDestroyed.sound end,
                            dialogControl = "LSM30_Sound",
                        },
                        nosound = {
                            order = 3,
                            type = "execute", 
                            name = L["No Sound"],
                            func = function(info) TotemTimers.ActiveProfile.Warnings.TotemDestroyed.sound = "" end,
                        },
                    },
                },
                WeaponMsg = {
                    order = 6,
                    type = "group",
                    name = L["Weapon buff warnings"],
                    args = {
                        enable = {
                            order = 0,
                            type = "toggle",
                            name = L["Enable"],
                            set = function(info, val) TotemTimers.ActiveProfile.Warnings.Weapon.enabled = val end,
                            get = function(info) return TotemTimers.ActiveProfile.Warnings.Weapon.enabled end,
                        },
                        color =  {
                            order = 1,
                            type = "color",
                            name = L["Color"],
                            hasAlpha = false,
                            set = function(info, r,g,b, a)
                                TotemTimers.ActiveProfile.Warnings.Weapon.r = r
                                TotemTimers.ActiveProfile.Warnings.Weapon.g = g
                                TotemTimers.ActiveProfile.Warnings.Weapon.b = b
                            end,
                            get = function(info)
                                return TotemTimers.ActiveProfile.Warnings.Weapon.r,
                                TotemTimers.ActiveProfile.Warnings.Weapon.g,
                                TotemTimers.ActiveProfile.Warnings.Weapon.b, 1
                            end,
                        },
                        sound = {
                            order = 2,
                            type = "select",
                            name = L["Sound"],
                            values = AceGUIWidgetLSMlists.sound,
                            set = function(info, val) TotemTimers.ActiveProfile.Warnings.Weapon.sound = val end,
                            get = function(info) return TotemTimers.ActiveProfile.Warnings.Weapon.sound end,
                            dialogControl = "LSM30_Sound",
                        },
                        nosound = {
                            order = 3,
                            type = "execute",
                            name = L["No Sound"],
                            func = function(info) TotemTimers.ActiveProfile.Warnings.Weapon.sound = "" end,
                        },
                    },
                },
            },
        },
    },
}

local ACD = LibStub("AceConfigDialog-3.0")
local frame, categoryID = ACD:AddToBlizOptions("TotemTimers", L["Warnings"], "TotemTimers", "messages")
TotemTimers.HookGUIFrame(frame, categoryID)
