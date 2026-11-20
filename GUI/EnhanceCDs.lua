if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local _, TotemTimers = ...


local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers_GUI", true)

local SpellIDs = TotemTimers.SpellIDs
local SpellNames = TotemTimers.SpellNames

function TotemTimers.OrderCDs(role)
    for i = 1, #TotemTimers.ActiveProfile.EnhanceCDs_Order[tonumber(role)] do
        if TotemTimers.options.args.enhancecds.args[role].args[tostring(TotemTimers.ActiveProfile.EnhanceCDs_Order[tonumber(role)][i])] then
            TotemTimers.options.args.enhancecds.args[role].args[tostring(TotemTimers.ActiveProfile.EnhanceCDs_Order[tonumber(role)][i])].order = i + 10
        end
    end
end

-- option name of a spell: the spell name, its ID if the game doesn't know the spell (yet) (AceConfig rejects nil names)
local function SpellOptionName(spell)
    return function()
        return SpellNames[spell] or C_Spell.GetSpellName(spell) or tostring(spell)
    end
end

local function changeOrder(spell, dir, role)
    role = tonumber(role)
    for i = 1, TotemTimers.num_CD_Spells[role] do
        if TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i] == spell and i + dir > 0 and i + dir <= TotemTimers.num_CD_Spells[role] then
            TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i], TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i + dir] = TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i + dir], TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i]
            break
        end
    end
    TotemTimers.OrderCDs(tostring(role))
    TotemTimers.ProcessSetting("EnhanceCDs")
end

local specializations = {}
local specInfoFunc = GetTalentTabInfo or C_SpecializationInfo.GetSpecializationInfo
for i = 1, 3 do
    local name, name2 = specInfoFunc(i)
    if type(name) == "number" then name = name2 end
    specializations[i] = name
end

TotemTimers.options.args.enhancecds = {
    order = 3,
    type = "group",
    name = "Combat Cooldowns",
    childGroups = "tab",
    args = {
        options = {
            order = 1,
            type = "group",
            name = "Combat Cooldowns",
            args = {
                enable = {
                    order = 0,
                    type = "toggle",
                    name = L["Enable"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.EnhanceCDs = val
                        TotemTimers.ProcessSetting("EnhanceCDs")
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.EnhanceCDs
                    end,
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
                    set = function(info, val)
                        TotemTimers.ActiveProfile.EnhanceCDs_Clickthrough = val
                        TotemTimers.ProcessSetting("EnhanceCDs_Clickthrough")
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.EnhanceCDs_Clickthrough
                    end,
                },
                CDTimersOnButtons = {
                    order = 5,
                    type = "toggle",
                    name = L["Timers On Buttons"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.CDTimersOnButtons = val
                        TotemTimers.ProcessSetting("CDTimersOnButtons")
                        TotemTimers.LayoutEnhanceCDs()
                        TotemTimers.LayoutLongCooldowns()
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.CDTimersOnButtons
                    end,
                },
                OOCAlpha = {
                    order = 6,
                    type = "range",
                    min = 0,
                    max = 1,
                    step = 0.1,
                    name = L["OOC Opacity"],
                    desc = L["OOC Opacity Desc"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.EnhanceCDsOOCAlpha = val
                        TotemTimers.ProcessSetting("EnhanceCDsOOCAlpha")
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.EnhanceCDsOOCAlpha
                    end,
                },
                HideEnhanceCDsOOC = {
                    order = 7,
                    type = "toggle",
                    name = L["Hide out of combat"],
                    desc = L["Hide OOC Desc"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.HideEnhanceCDsOOC = val
                        TotemTimers.ProcessSetting("HideEnhanceCDsOOC")
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.HideEnhanceCDsOOC
                    end,
                },
                OneButtonRow = {
                    order = 7,
                    type = "toggle",
                    name = L["One Button Row"],
                    desc = L["Displays combat cooldowns on one button row instead of two"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.EnhanceCDsOneRow = val
                        TotemTimers.LayoutEnhanceCDs()
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.EnhanceCDsOneRow
                    end,
                },

                scalingheader = {
                    order = 10,
                    type = "header",
                    name = L["Scaling"],
                },
                ECDSize = {
                    order = 11,
                    type = "range",
                    name = L["Button Size"],
                    min = 16,
                    max = 96,
                    step = 1,
                    bigStep = 2,
                    set = function(info, val)
                        TotemTimers.ActiveProfile.EnhanceCDsSize = val
                        TotemTimers.ProcessSetting("EnhanceCDsSize")
                        TotemTimers.LayoutEnhanceCDs()
                        TotemTimers.LayoutLongCooldowns()
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.EnhanceCDsSize
                    end,
                },
                spacing = {
                    order = 13,
                    type = "range",
                    name = L["Spacing"],
                    desc = L["Sets the space between timer buttons"],
                    min = 0,
                    max = 20,
                    step = 1,
                    set = function(info, val)
                        TotemTimers.ActiveProfile.CooldownSpacing = val
                        TotemTimers.ProcessSetting("CooldownSpacing")
                        TotemTimers.LayoutEnhanceCDs()
                        TotemTimers.LayoutLongCooldowns()
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.CooldownSpacing
                    end,
                },

                stoppulseheader = {
                    order = 20,
                    type = "header",
                    name = "Stop Pulse",
                },
                stoppulse = {
                    order = 21,
                    type = "toggle",
                    name = L["Stop Pulse Animation"],
                    desc = L["Stop Pulse Desc"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.EnhanceCDsStopPulse = val
                        TotemTimers.ProcessSetting("EnhanceCDsStopPulse")
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.EnhanceCDsStopPulse
                    end,
                },
                stoppulsedemo = {
                    order = 22,
                    type = "execute",
                    name = L["Demo"],
                    func = function()
                        local timer = nil
                        for _, t in pairs(TotemTimers.EnhanceCDs) do
                            if t.active then
                                timer = t
                                break
                            end
                        end
                        timer.animation:SetTexture(timer.button.icons[1]:GetTexture())
                        timer.animation:Play()
                    end
                },

                flameshockheader = {
                    order = 30,
                    type = "header",
                    name = SpellOptionName(SpellIDs.FlameShock),
                },
                FlameShockDuration = {
                    order = 31,
                    type = "description",
                    name = "Flame shock duration is now changed for each spec in spells section below",
                },
                FlameShockOnTop = {
                    order = 32,
                    type = "toggle",
                    name = L["Flame Shock on top"],
                    desc = L["Flame Shock on top desc"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.FlameShockDurationOnTop = val
                        TotemTimers.LayoutEnhanceCDs()
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.FlameShockDurationOnTop
                    end,
                },
                FlameShockSize = {
                    order = 33,
                    type = "range",
                    name = L["Size"],
                    min = 1,
                    max = 3,
                    step = 1,
                    set = function(info, val)
                        TotemTimers.ActiveProfile.FlameShockDurationSize = val
                        TotemTimers.ProcessSetting("FlameShockDurationSize")
                        TotemTimers.LayoutEnhanceCDs()
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.FlameShockDurationSize
                    end,
                },
                FlameShockStopPulse = {
                    order = 33,
                    type = "toggle",
                    name = L["Stop Pulse Animation"],
                    desc = L["Stop Pulse Desc"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.FlameShockDurationStopPulse = val
                        TotemTimers.ProcessSetting("FlameShockDurationStopPulse")
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.FlameShockDurationStopPulse
                    end,
                },

                lc = {
                    order = 70,
                    type = "header",
                    name = L["Long Cooldowns"],
                },
                lcenable = {
                    order = 71,
                    type = "toggle",
                    name = L["Enable"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.LongCooldowns = val
                        TotemTimers.ProcessSetting("LongCooldowns")
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.LongCooldowns
                    end
                },
                lcarrange = {
                    order = 72,
                    type = "select",
                    name = L["Arrangement"],
                    values = { vertical = L["vertical"], horizontal = L["horizontal"], },
                    set = function(info, val)
                        TotemTimers.ActiveProfile.LongCooldownsArrange = val
                        TotemTimers.LayoutLongCooldowns()
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.LongCooldownsArrange
                    end,
                },
                lcnewline = {
                    order = 73,
                    type = "description",
                    name = "",
                },
                lcstoppulse = {
                    order = 74,
                    type = "toggle",
                    name = L["Stop Pulse Animation"],
                    desc = L["Stop Pulse Desc"],
                    set = function(info, val)
                        TotemTimers.ActiveProfile.LongCooldownsStopPulse = val
                        TotemTimers.ProcessSetting("LongCooldownsStopPulse")
                    end,
                    get = function(info)
                        return TotemTimers.ActiveProfile.LongCooldownsStopPulse
                    end,
                },
                lcstoppulsedemo = {
                    order = 75,
                    type = "execute",
                    name = L["Demo"],
                    func = function()
                        local timer = nil
                        for _, t in pairs(TotemTimers.LongCooldowns) do
                            if t.active then
                                timer = t
                                break
                            end
                        end
                        if timer then
                            timer.animation:SetTexture(timer.button.icons[1]:GetTexture())
                            timer.animation:Play()
                        end
                    end
                },

            },
        },


        ["2"] = {
            order = 81,
            type = "group",
            name = specializations[2] or "Enhancement",
            args = {
            },
        },
        ["1"] = {
            order = 82,
            type = "group",
            name = specializations[1] or "Elemental",
            args = {
            },
        },
        ["3"] = {
            order = 83,
            type = "group",
            name = specializations[3] or "Restoration",
            args = {
            },
        },
        ["4"] = {
            order = 84,
            type = "group",
            name = L["Long Cooldowns"],
            args = {},
        },
    },
}

for spec = 1, 3 do
    for index, spell in pairs(TotemTimers.CombatCooldownSpells[spec]) do
        TotemTimers.options.args.enhancecds.args[tostring(spec)].args[tostring(index)] = {
            order = 10 + index,
            type = "toggle",
            name = SpellOptionName(spell),
            width = "normal",
            set = function(info, val)
                TotemTimers.ActiveProfile.EnhanceCDs_Spells[spec][index] = val
                TotemTimers.ConfigEnhanceCDs()
                TotemTimers.LayoutEnhanceCDs()
            end,
            get = function(info)
                return TotemTimers.ActiveProfile.EnhanceCDs_Spells[spec][index]
            end,
        }
    end
    TotemTimers.options.args.enhancecds.args[tostring(spec)].args.FlameShockDuration = {
        order = 0,
        type = "toggle",
        name = L["Flame Shock duration"],
        width = "full",
        set = function(info, val)
            TotemTimers.ActiveProfile.EnhanceCDsFlameShockDuration_Specialization[spec] = val
            TotemTimers.ConfigEnhanceCDs()
            TotemTimers.LayoutEnhanceCDs()
        end,
        get = function(info)
            return TotemTimers.ActiveProfile.EnhanceCDsFlameShockDuration_Specialization[spec]
        end,
    }
end

if (TotemTimers.LongCooldownSpells) then
    for i,lc in pairs(TotemTimers.LongCooldownSpells) do
        local spellID = lc.spell
        TotemTimers.options.args.enhancecds.args["4"].args[tostring(spellID)] = {
            order = i,
            type = "toggle",
            name = SpellOptionName(spellID),
            set = function(info, val)
                TotemTimers.ActiveProfile.LongCooldownSpells[spellID] = val
                TotemTimers.ProcessSetting("LongCooldowns")
            end,
            get = function()
                local val = TotemTimers.ActiveProfile.LongCooldownSpells[spellID]
                return val == nil or val
            end
        }
    end
end


TotemTimers.options.args.enhancecds.args.options.args.OverlayGlow = {
    order = 9,
    type = "toggle",
    name = L["Overlay Glow"],
    desc = L["Show an overlay glow for affected spells on your action bars for some procs like Maelstrom Weapon, supports default action bars and Bartender"],
    set = function(info, val)
        TotemTimers.ActiveProfile.OverlayGlow = val
    end,
    get = function(info)
        return TotemTimers.ActiveProfile.OverlayGlow
    end,
}


local MaelstromName = SpellOptionName(SpellIDs.Maelstrom)

TotemTimers.options.args.enhancecds.args.options.args.MaelstromHeader = {
    order = 40,
    type = "header",
    name = MaelstromName,
}

TotemTimers.options.args.enhancecds.args.options.args.Maelstrom = {
    order = 41,
    type = "toggle",
    name = MaelstromName,
    set = function(info, val)
        TotemTimers.ActiveProfile.EnhanceCDsMaelstrom = val
        TotemTimers.ConfigEnhanceCDs()
        TotemTimers.LayoutEnhanceCDs()
    end,
    get = function(info)
        return TotemTimers.ActiveProfile.EnhanceCDsMaelstrom
    end,
}

TotemTimers.options.args.enhancecds.args.options.args.MaelstromSize = {
    order = 44,
    type = "range",
    name = L["Size"],
    min = 1,
    max = 3,
    step = 1,
    set = function(info, val)
        TotemTimers.ActiveProfile.MaelstromSize = val
        TotemTimers.ProcessSetting("MaelstromSize")
        TotemTimers.LayoutEnhanceCDs()
    end,
    get = function(info)
        return TotemTimers.ActiveProfile.MaelstromSize
    end,
}

TotemTimers.options.args.enhancecds.args.options.args.MaelstromStopPulse = {
    order = 43,
    type = "toggle",
    name = L["Stop Pulse Animation"],
    desc = L["MaelstromStopPulseDesc"],
    set = function(info, val)
        TotemTimers.ActiveProfile.MaelstromStopPulse = val
        TotemTimers.ProcessSetting("MaelstromStopPulse")
    end,
    get = function(info)
        return TotemTimers.ActiveProfile.MaelstromStopPulse
    end,
}

-- layout of the tracker, the entries are pictures instead of text, composed by the ImageSelect widget from the
-- tracker's own textures (units: the widget scales them): a small Maelstrom bar (the Maelstrom icon at its left, 5
-- stacks as number) and/or the 5 stacks icon (mw5), for "gamepad" the connected controller
-- (CONTROLLER_TEXTURES) and the Lightning Bolt icon
local LAYOUT_WIDTH, LAYOUT_HEIGHT = 40, 20
local LAYOUT_BAR_WIDTH, LAYOUT_BAR_HEIGHT = 36, 6
local LIGHTNING_BAR = "Interface/AddOns/TotemTimers/textures/lightning_bar"
local MAELSTROM_ICON = "Interface/AddOns/TotemTimers/textures/mw5"

-- the bar with the Maelstrom icon at its left and "5" in its center, top: its top edge
local function AddLayoutBar(entry, top)
    local left = (LAYOUT_WIDTH - LAYOUT_BAR_WIDTH) / 2
    table.insert(entry.layers, { texture = LIGHTNING_BAR, left = left, top = top,
        width = LAYOUT_BAR_WIDTH, height = LAYOUT_BAR_HEIGHT })
    local icon = C_Spell.GetSpellTexture(SpellIDs.Maelstrom)
    if icon then
        table.insert(entry.layers, { texture = icon, left = left, top = top,
            width = LAYOUT_BAR_HEIGHT, height = LAYOUT_BAR_HEIGHT })
    end
    table.insert(entry.texts, { text = "5", left = left, top = top + 0.5,
        width = LAYOUT_BAR_WIDTH, height = LAYOUT_BAR_HEIGHT - 1 })
end

-- the stack icon like above the tracker's bar: 75% of the bar's width, 2:1, reaching 15% into the bar
local function AddLayoutIcon(entry, barTop)
    local width = LAYOUT_BAR_WIDTH * 0.75
    local height = width / 2
    table.insert(entry.layers, { texture = MAELSTROM_ICON, left = (LAYOUT_WIDTH - width) / 2,
        top = barTop - height * 0.85, width = width, height = height })
end

-- controller pictures by type (GamePad.GetControllerType); the PNGs are Kenney's Input Prompts icons (CC0)
local CONTROLLER_TEXTURES = {
    dualsense = "Interface/AddOns/TotemTimers/textures/controller_playstation5.png",
    dualshock4 = "Interface/AddOns/TotemTimers/textures/controller_playstation4.png",
    -- Switch 2 Pro Controller picture, also for the Switch 1 Pro Controller (both Nintendo, "switch")
    switch = "Interface/AddOns/TotemTimers/textures/controller_switch_pro.png",
    xbox = "Interface/AddOns/TotemTimers/textures/controller_xboxone.png",
}

local function NewLayoutEntry(tooltip)
    return { width = LAYOUT_WIDTH, height = LAYOUT_HEIGHT, layers = {}, texts = {}, tooltip = tooltip }
end

TotemTimers.options.args.enhancecds.args.options.args.MaelstromLayout = {
    order = 42,
    type = "select",
    -- a row of large picture buttons instead of a dropdown (GUI/ImageSelect.lua)
    dialogControl = "TotemTimers-ImageSelect",
    width = "full",
    name = L["Layout"],
    desc = L["MaelstromLayoutDesc"],
    values = function()
        local barTop = LAYOUT_HEIGHT - LAYOUT_BAR_HEIGHT - 1
        local both = NewLayoutEntry(L["MaelstromLayoutBothDesc"])
        AddLayoutIcon(both, barTop)
        AddLayoutBar(both, barTop)

        local bar = NewLayoutEntry(L["MaelstromLayoutBarDesc"])
        AddLayoutBar(bar, (LAYOUT_HEIGHT - LAYOUT_BAR_HEIGHT) / 2)

        local icon = NewLayoutEntry(L["MaelstromLayoutIconDesc"])
        table.insert(icon.layers, { texture = MAELSTROM_ICON, left = 0, top = 0,
            width = LAYOUT_WIDTH, height = LAYOUT_HEIGHT })

        -- the picture of the connected controller's type (GamePad/GamePad.lua), the Xbox controller for all others
        -- and without a controller
        local lightningBolt = C_Spell.GetSpellTexture(SpellIDs.LightningBolt)
        local function GamePadEntry(controllerType, tooltip)
            local entry = NewLayoutEntry(tooltip)
            table.insert(entry.layers, { texture = CONTROLLER_TEXTURES[controllerType] or CONTROLLER_TEXTURES.xbox,
                left = 1, top = 1, width = 18, height = 18 })
            if lightningBolt then
                table.insert(entry.layers, { texture = lightningBolt, left = 21, top = 1, width = 18, height = 18 })
            end
            return entry
        end
        local controllerType = TotemTimers.GetControllerType and TotemTimers.GetControllerType() or "xbox"
        return { both = both, bar = bar, icon = icon,
            gamepad = GamePadEntry(controllerType, L["MaelstromLayoutGamePadDesc"]) }
    end,
    sorting = { "both", "bar", "icon", "gamepad" },
    set = function(info, val)
        TotemTimers.ActiveProfile.MaelstromLayout = val
        TotemTimers.ProcessSetting("MaelstromLayout")
    end,
    get = function(info)
        return TotemTimers.ActiveProfile.MaelstromLayout or "both"
    end,
}

-- size of the stack icon above the bar, relative to the bar (1 = 75% of its width)
TotemTimers.options.args.enhancecds.args.options.args.MaelstromIconSize = {
    order = 45,
    type = "range",
    name = L["Icon Size"],
    desc = L["MaelstromIconSizeDesc"],
    min = 0.5,
    max = 2,
    step = 0.05,
    isPercent = true,
    set = function(info, val)
        TotemTimers.ActiveProfile.MaelstromIconSize = val
        TotemTimers.ProcessSetting("MaelstromIconSize")
    end,
    get = function(info)
        return TotemTimers.ActiveProfile.MaelstromIconSize or 1
    end,
}

local ACD = LibStub("AceConfigDialog-3.0")
local frame, categoryID = ACD:AddToBlizOptions("TotemTimers", L["Combat Cooldowns"], "TotemTimers", "enhancecds")
TotemTimers.HookGUIFrame(frame, categoryID)