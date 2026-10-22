if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local SpellNames = TotemTimers.SpellNames
local SpellIDs = TotemTimers.SpellIDs
local SpellTextures = TotemTimers.SpellTextures
local AvailableSpells = TotemTimers.AvailableSpells

function TotemTimers.CreateAnkhTracker()
    local ankh = XiTimers:new(1)

    ankh.button:SetScript("OnEvent", TotemTimers.AnkhEvent)
    ankh.button.icons[1]:SetTexture(SpellTextures[SpellIDs.Ankh])
    ankh.events[1] = "SPELL_UPDATE_COOLDOWN"
    ankh.events[2] = "BAG_UPDATE"
    ankh.button.anchorframe = TotemTimers_TrackerFrame
    ankh.showCooldown = true
    ankh.dontAlpha = true
    ankh.button.icons[1]:SetAlpha(1)
    ankh.timeStyle = "blizz"
    ankh.Activate = function(self)
        XiTimers.Activate(self)
        TotemTimers.AnkhEvent(ankh.button, "SPELL_UPDATE_COOLDOWN")
        TotemTimers.AnkhEvent(ankh.button, "BAG_UPDATE")
    end
    ankh.button:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    ankh.button.cooldown.noCooldownCount = true
    ankh.button.cooldown.noOCC = true

    TotemTimers.AnkhTracker = ankh
end

table.insert(TotemTimers.Modules, TotemTimers.CreateAnkhTracker)

local AnkhName = SpellNames[SpellIDs.Ankh]
local AnkhID = SpellIDs.Ankh
local AnkhItem = 17030

-- The cooldown can be secret, so the timer is started with a DurationObject of the cooldown and only the
-- never secret isActive and isOnGCD flags of the cooldown info are read.
function TotemTimers.AnkhEvent(self, event)
    if event == "SPELL_UPDATE_COOLDOWN" then
        if not AvailableSpells[SpellIDs.Ankh] then
            return
        end
        local info = C_Spell.GetSpellCooldown(AnkhID)
        if not info or not info.isActive then
            self.timer:Stop(1)
        elseif not info.isOnGCD and not self.timer.timers[1] then
            self.timer:Start(1, C_Spell.GetSpellCooldownDuration(AnkhID, true))
        end
    else
        local countfunc = GetItemCount or C_Item.GetItemCount
        self.count:SetText(countfunc(AnkhItem))
    end
end
