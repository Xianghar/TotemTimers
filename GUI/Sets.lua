if select(2,UnitClass("player")) ~= "SHAMAN" then return end

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers_GUI", true)


TotemTimers.options.args.sets = {
    order = 6,
    type = "group",
    name = "Sets",
    args = {},
}

local SpellNames = TotemTimers.SpellNames


local ACD = LibStub("AceConfigDialog-3.0")
local ACR =	LibStub("AceConfigRegistry-3.0")

local frame, categoryID = ACD:AddToBlizOptions("TotemTimers", "Sets", "TotemTimers", "sets")
TotemTimers.HookGUIFrame(frame, categoryID)


local reloadFrame

-- the options of the sets are built from the profile when they are shown (settings panel page or options window)
function TotemTimers.BuildSetsOptions()
    TotemTimers.options.args.sets.args = {}

    local args = TotemTimers.options.args.sets.args

    if #TotemTimers.ActiveProfile.TotemSets == 0 then
        args.desc = {
            type="description",
            name="You did not create any totem sets yet."
        }
    else
        for i = 1, #TotemTimers.ActiveProfile.TotemSets do
            local set = TotemTimers.ActiveProfile.TotemSets[i]

            -- AceConfig only accepts string keys
            args["header" .. i] = {
                type = "header",
                order = i * 10,
                name = not set.name and "Set "..i or set.name
            }

            local totems = {}
            for element = 1,4 do
                if set[element] then
                    if SpellNames[set[element]] and  TotemTimers.ElementColors[element] then
                        table.insert(totems, TotemTimers.ElementColors[element]:WrapTextInColorCode(SpellNames[set[element]]))
                    end
                end
            end

            args["totems" .. i] = {
                type = "description",
                order = i * 10 + 1,
                name = table.concat(totems, ", "),
            }

            args["rename" .. i] = {
                type = "input",
                name = L["Rename"],
                order = i * 10 + 2,
                set = function(self, value)
                    set.name = value
                    reloadFrame()
                end,
            }

            args["delete" .. i] = {
                type = "execute",
                name = L["Delete"],
                order = i * 10 + 3,
                func = function()
                    TotemTimers.ConfirmDeleteSet(i)
                end,
            }
        end
    end

    ACR:NotifyChange("TotemTimers")
end

-- after renaming or deleting a set
reloadFrame = TotemTimers.BuildSetsOptions

frame:HookScript("OnShow", TotemTimers.BuildSetsOptions)

-- after deleting a set (TotemTimers.ConfirmDeleteSet)
TotemTimers.OnSetsChanged = reloadFrame
