if select(2,UnitClass("player")) ~= "SHAMAN" then return end

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers_GUI", true)

local SpellIDs = TotemTimers.SpellIDs
local SpellNames = TotemTimers.SpellNames


function TotemTimers.OrderCDs(role)
    for i = 1,#TotemTimers.ActiveProfile.EnhanceCDs_Order[tonumber(role)] do
        if TotemTimers.options.args.enhancecds.args[role].args[tostring(TotemTimers.ActiveProfile.EnhanceCDs_Order[tonumber(role)][i])] then
            TotemTimers.options.args.enhancecds.args[role].args[tostring(TotemTimers.ActiveProfile.EnhanceCDs_Order[tonumber(role)][i])].order = i+10
        end
    end
end

local function changeOrder(spell, dir, role)
    role = tonumber(role)
    for i=1,TotemTimers.num_CD_Spells[role] do
        if TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i] == spell and i+dir>0 and i+dir<=TotemTimers.num_CD_Spells[role] then
            TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i],TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i+dir] =
                    TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i+dir],TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i]
            break
        end
    end
    TotemTimers.OrderCDs(tostring(role))
    TotemTimers.ProcessSetting("EnhanceCDs")
end

TotemTimers.options.args.enhancecds = {
    type = "group",
    name = "enhancecds",
    args = {
        enable = {
            order = 0,
            type = "toggle",
            name = L["Enable"],
            set = function(info, val) TotemTimers.ActiveProfile.EnhanceCDs = val  TotemTimers.ProcessSetting("EnhanceCDs") end,
            get = function(info) return TotemTimers.ActiveProfile.EnhanceCDs end,
        },
       --[[ header = {
            order = 10,
            type = "header",
            name = "",
        }, ]]   
        clickthrough = {
            order = 1,
            type = "toggle", 
            name = L["Clickthrough"],
            desc = L["Clickthrough Desc"],
            set = function(info, val) TotemTimers.ActiveProfile.EnhanceCDs_Clickthrough = val  TotemTimers.ProcessSetting("EnhanceCDs_Clickthrough") end,
            get = function(info) return TotemTimers.ActiveProfile.EnhanceCDs_Clickthrough end,
        },
        CDTimersOnButtons = {
            order = 11,
            type = "toggle",
            name = L["Timers On Buttons"],
            set = function(info, val) TotemTimers.ActiveProfile.CDTimersOnButtons = val
                        TotemTimers.ProcessSetting("TimersOnButtons") end,
            get = function(info) return TotemTimers.ActiveProfile.CDTimersOnButtons end,
        },  
        HideEnhanceCDsOOC = {
            order = 12,
            type = "toggle",
            name = L["Hide out of combat"],
            desc = L["Hide OOC Desc"],
            set = function(info, val) TotemTimers.ActiveProfile.HideEnhanceCDsOOC = val  TotemTimers.ProcessSetting("HideEnhanceCDsOOC") end,
            get = function(info) return TotemTimers.ActiveProfile.HideEnhanceCDsOOC end,
        }, 
        FlameShockOnTop = {
            order = 12,
            type = "toggle", 
            name = L["Flame Shock on top"],
            desc = L["Flame Shock on top desc"],
            set = function(info, val) TotemTimers.ActiveProfile.FlameShockDurationOnTop = val  TotemTimers.LayoutEnhanceCDs() end,
            get = function(info) return TotemTimers.ActiveProfile.FlameShockDurationOnTop end, 
        },
		spacing = {
            order = 13,
            type = "range",
            name = L["Spacing"] ,
            desc = L["Sets the space between timer buttons"],
            min = 0,
            max = 20,
            step = 1,
            set = function(info, val)
                        TotemTimers.ActiveProfile.CooldownSpacing = val  TotemTimers.ProcessSetting("CooldownSpacing")	
                  end,
            get = function(info) return TotemTimers.ActiveProfile.CooldownSpacing end,
        },
 
        maelstromheight = {
            order = 23,
            type = "range",
            name = L["Maelstrom Bar Height"],
            min = 6,
            max = 40,
            step = 1,
            set = function(info, val)
                        TotemTimers.ActiveProfile.EnhanceCDsMaelstromHeight = val  TotemTimers.ProcessSetting("EnhanceCDsMaelstromHeight")	
                  end,
            get = function(info) return TotemTimers.ActiveProfile.EnhanceCDsMaelstromHeight end,
        },
    },
}
    
local ACD = LibStub("AceConfigDialog-3.0")
local frame = ACD:AddToBlizOptions("TotemTimers", L["Cooldowns"], "TotemTimers", "enhancecds")    
frame:SetScript("OnEvent", function(self) InterfaceOptionsFrame:Hide() end)
frame:HookScript("OnShow", function(self) if InCombatLockdown() then InterfaceOptionsFrame:Hide() end TotemTimers.LastGUIPanel = self end)
frame:RegisterEvent("PLAYER_REGEN_DISABLED")