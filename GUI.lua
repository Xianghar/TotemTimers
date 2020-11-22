if select(2,UnitClass("player")) ~= "SHAMAN" then return end

local _, TotemTimers = ...

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers_GUI", true)

local LibDialog = LibStub:GetLibrary("LibDialog-1.0")

XiTimers.options.args.general.args.hideblizztimers = {
    order = 7,
    type = "toggle",
    name = L["Hide Blizzard Timers"],
    set = function(info, val) XiTimers.ActiveProfile.HideBlizzTimers = val XiTimers.ProcessSetting("HideBlizzTimers") end,
    get = function(info) return XiTimers.ActiveProfile.HideBlizzTimers end,
}

XiTimers.options.args.general.args.flameshockbar = {
    order = 203,
    type = "toggle",
    name = L["Flame Shock Duration"],
    desc = L["Flame Shock Duration Desc"],
    set = function(info, val) XiTimers.ActiveProfile.FlameshockBar = val XiTimers.ProcessSetting("FlameshockBar") end,
    get = function(info) return XiTimers.ActiveProfile.FlameshockBar end,
}

XiTimers.options.args.general.args.flameshockbarresto = {
    order = 204,
    type = "toggle",
    name = L["Flame Shock Duration Restoration"],
    desc = L["Flame Shock Duration Restoration Desc"],
    set = function(info, val) XiTimers.ActiveProfile.FlameshockBarRestoration = val XiTimers.ProcessSetting("FlameshockBarRestoration") end,
    get = function(info) return XiTimers.ActiveProfile.FlameshockBarRestoration end,
}


XiTimers.options.args.general.args.reincarnationheader = {
    order = 210,
    type = "header",
    name = "",
}

XiTimers.options.args.general.args.reincarnation = {
    order = 211,
    type = "execute",
    name = GetSpellInfo(TotemTimers.SpellIDs.Reincarnation),
    desc = L["Put Reincarnation Spell on Bar"],
    func = function()
        XiTimers.ShowGrid()
        LibDialog:Spawn("XiTimers_Spells")
        InterfaceOptionsFrame:Hide()
        PickupSpell(TotemTimers.SpellIDs.Reincarnation)
    end,
}


XiTimers.options.args.powerbars.args.maelstrombar = {
    order = 1,
    type = "toggle",
    name = L["Maelstrom Bar"],
    desc = L["Maelstrom Bar Desc"],
    set = function(info, val) XiTimers.ActiveProfile.MaelstromBar = val XiTimers.ProcessSetting("MaelstromBar") end,
    get = function(info) return XiTimers.ActiveProfile.MaelstromBar end,
}

XiTimers.options.args.powerbars.args.manabar = {
    order = 2,
    type = "toggle",
    name = L["Mana Bar"],
    desc = L["Mana Bar Desc"],
    set = function(info, val) XiTimers.ActiveProfile.ManaBar = val XiTimers.ProcessSetting("ManaBar") end,
    get = function(info) return XiTimers.ActiveProfile.ManaBar end,
}

XiTimers.options.args.powerbars.args.hm = {
    order = 3,
    type = "header",
    name = "",
}



