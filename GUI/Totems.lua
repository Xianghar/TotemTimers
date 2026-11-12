if select(2,UnitClass("player")) ~= "SHAMAN" then return end

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers_GUI", true)

local _, TotemTimers = ...

local Elementss = {
	[EARTH_TOTEM_SLOT] = "earth",
	[FIRE_TOTEM_SLOT] = "fire",
	[WATER_TOTEM_SLOT] = "water",
	[AIR_TOTEM_SLOT] = "air",
}

TotemTimers.options.args.totems = {
    order = 5,
    type = "group",
    name = "Totems",
    -- tab: the elements are tabs inside the page instead of entries in the /tt window's left column
    childGroups = "tab",
    args = {
        [tostring(EARTH_TOTEM_SLOT)] = {
            order = 0,
            type = "group",
            name = L["Earth"],
            args = {
            },
        },  
        [tostring(FIRE_TOTEM_SLOT)] = {
            order = 1,
            type = "group",
            name = L["Fire"],
            args = {
            },
        },  
        [tostring(WATER_TOTEM_SLOT)] = {
            order = 2,
            type = "group",
            name = L["Water"],
            args = {
            },
        },  
        [tostring(AIR_TOTEM_SLOT)] = {
            order = 3,
            type = "group",
            name = L["Air"],
            args = {
            },
        },  
    },
}

for k,v in pairs(TotemData) do
    -- one checkbox per totem and line, labelled with the totem's icon and name (sorted by name)
    TotemTimers.options.args.totems.args[tostring(v.element)].args[tostring(k)] = {
        type = "toggle",
        width = "full",
        -- the leading spaces put some room between icon and text (the CheckBox widget leaves only 1 px)
        name = function() return "  " .. (TotemTimers.SpellNames[k] or C_Spell.GetSpellName(k) or tostring(k)) end,
        image = function() return (C_Spell.GetSpellTexture(k)) end,
        imageCoords = { 0.07, 0.93, 0.07, 0.93 },
        set = function(info, val) TotemTimers.ActiveProfile.HiddenTotems[k] = not val;
            TotemTimers.SetCastButtonSpells()
        end,
        get = function(info) return not TotemTimers.ActiveProfile.HiddenTotems[k] end,
    }
end

local ACD = LibStub("AceConfigDialog-3.0")
local frame, categoryID = ACD:AddToBlizOptions("TotemTimers", "Totems", "TotemTimers", "totems")
TotemTimers.HookGUIFrame(frame, categoryID)