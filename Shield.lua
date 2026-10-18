if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers")

local Timers = XiTimers.timers

local SpellNames = TotemTimers.SpellNames
local SpellIDs = TotemTimers.SpellIDs
local SpellTextures = TotemTimers.SpellTextures

local shield = nil


-- The shield aura can be secret, so it is displayed by an AuraDisplay (see AuraDisplay.lua) over the tracker button.
-- Two slots: Lightning/Water Shield on top, Earth Shield (only with EarthShieldOnSelf) below.

local SLOT_SHIELD = "shield"
local SLOT_EARTHSHIELD = "earthshield"

local function SpellIDSet(...)
    local set = {}
    for i = 1, select("#", ...) do
        for _, id in pairs(TotemTimers.ShieldAuraSpells[select(i, ...)] or {}) do
            set[id] = true
        end
    end
    return set
end

local function CreateAuraDisplay()
    local display = TotemTimers.AuraDisplay:new(shield.button)
    if not display then return end
    display:AddSlot(SLOT_EARTHSHIELD, SpellIDSet(SpellIDs.EarthShield), 2)
    display:AddSlot(SLOT_SHIELD, SpellIDSet(SpellIDs.LightningShield, SpellIDs.WaterShield), 4)
    shield.auraDisplay = display
end


function TotemTimers.CreateShieldTracker()
    shield = XiTimers:new(1)
    shield.button.icons[1]:SetTexture(SpellTextures[SpellIDs.LightningShield])
    shield.button.anchorframe = TotemTimers_TrackerFrame
    shield.button:SetScript("OnEvent", TotemTimers.ShieldEvent)
    shield.events[1] = "UNIT_SPELLCAST_SUCCEEDED"
    shield.timeStyle = "blizz"
    shield.Activate = function(self)
        XiTimers.Activate(self)
        TotemTimers.ShieldEvent(self.button, "UNIT_AURA", "player")
        if not TotemTimers.ActiveProfile.ShieldTracker then
            self.button:Hide()
        end
    end
    shield.button:SetAttribute("*type*", "spell")
    shield.button:SetAttribute("*unit*", "player")
    shield.button:RegisterForClicks("AnyDown")


    for k,v in pairs(TotemTimers.ShieldButtons) do
        shield.button:SetAttribute("*spell"..k, v)
    end


    shield.button:SetScript("OnDragStop", function(self)
        XiTimers.StopMoving(self)
    end)

    CreateAuraDisplay()

    TotemTimers.ShieldTracker = shield
end

table.insert(TotemTimers.Modules, TotemTimers.CreateShieldTracker)


local ShieldChargesOnly = false

-- charges only: the time and the swipe of the aura display are hidden, only the charges are shown
local function ConfigShieldButtonUpdate(sco)
    local display = Timers[6].auraDisplay
    if display then
        display:SetTimeShown(not sco)
    end
end

function TotemTimers.SetShieldUpdate()
    ShieldChargesOnly = TotemTimers.ActiveProfile.ShieldChargesOnly
    ConfigShieldButtonUpdate(ShieldChargesOnly)
    TotemTimers.ShieldEvent(Timers[6].button, "UNIT_AURA", "player")
end


-- UNIT_AURA is only sent by the addon itself to apply settings, the aura container tracks the auras
function TotemTimers.ShieldEvent(self, event, unit)
    if event == "UNIT_AURA" and unit == "player" then
        local display = self.timer.auraDisplay
        if display then
            display:SetSlotEnabled(SLOT_EARTHSHIELD, TotemTimers.ActiveProfile.EarthShieldOnSelf)
        end
    end
end
