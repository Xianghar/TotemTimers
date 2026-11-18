if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...

local SpellIDs = TotemTimers.SpellIDs
local SpellTextures = TotemTimers.SpellTextures
local AvailableSpells = TotemTimers.AvailableSpells

local TotemicCall = SpellIDs.TotemicCall
local TotemicRecall = SpellIDs.TotemicRecall

-- Totemic Call button (option TotemicCallButton): leftclick casts Totemic Call, rightclick Totemic Recall. The timer
-- shows the cooldown of Totemic Call; without it the button shows the global cooldown of Totemic Call
-- (XiTimers:UpdateGCD). It sits next to the multicast button, or in its place without it (TotemTimers.OrderTimers).
-- Created after the trackers, so it doesn't shift their timer indices.

-- The cooldown can be secret, so the timer is started with a DurationObject of the cooldown and only the never secret
-- isActive and isOnGCD flags of the cooldown info are read (like the Ankh tracker).
local function CallEvent(self, event)
    if event == "SPELL_UPDATE_COOLDOWN" then
        if not AvailableSpells[TotemicCall] then
            self.timer:Stop(1)
            return
        end
        local info = C_Spell.GetSpellCooldown(TotemicCall)
        if not info or not info.isActive then
            self.timer:Stop(1)
        elseif not info.isOnGCD and not self.timer.timers[1] then
            self.timer:Start(1, C_Spell.GetSpellCooldownDuration(TotemicCall, true))
        end
    end
end

function TotemTimers.CreateTotemicCallButton()
    if not TotemicCall then return end
    local call = XiTimers:new(1)
    local button = call.button

    button.icons[1]:SetTexture(SpellTextures[TotemicCall])
    -- dragging moves the totem timers
    button.anchorframe = TotemTimersFrame
    button:SetScript("OnEvent", CallEvent)
    call.events[1] = "SPELL_UPDATE_COOLDOWN"
    call.showCooldown = true
    -- the time follows the totem timers' options: TimersOnButtons, TimerTimePos, TimerTimeHeight, TimerTimeSpacing and
    -- TotemTimerBarWidth (Settings.lua); OrderTimers keeps the other buttons clear of its timer bar
    call.timerOnButton = true
    call.dontAlpha = true
    -- no warning flash (neither the red one nor the icon's) for the short cooldown
    call.dontFlash = true
    -- the icon is tinted blue while the mana for Totemic Call is missing (checked once the timer is active)
    call:SetManaCheck(TotemicCall)
    button.icons[1]:SetAlpha(1)
    button.cooldown.noCooldownCount = true

    button:RegisterForClicks("AnyDown")
    button:SetAttribute("*type1", "spell")
    button:SetAttribute("*spell1", TotemicCall)
    button:SetAttribute("*type2", "spell")
    button:SetAttribute("*spell2", TotemicRecall)
    button:SetAttribute("tooltip", true)
    button.tooltip = TotemTimers.Tooltips.TotemicCall:new(button)

    call.Activate = function(self)
        XiTimers.Activate(self)
        CallEvent(self.button, "SPELL_UPDATE_COOLDOWN")
        self:UpdateGCD()
    end

    button:SetScript("OnDragStop", function(self)
        XiTimers.StopMoving(self)
        if not InCombatLockdown() then
            TotemTimers.PositionCastButtons()
        end
    end)

    TotemTimers.TotemicCallTimer = call
end

table.insert(TotemTimers.Modules, TotemTimers.CreateTotemicCallButton)

-- the button is shown with option TotemicCallButton while the totem timers are shown and Totemic Call is known
function TotemTimers.UpdateTotemicCallButton()
    local call = TotemTimers.TotemicCallTimer
    if not call or InCombatLockdown() then return end
    local profile = TotemTimers.ActiveProfile
    if profile.TotemicCallButton and profile.Show and AvailableSpells[TotemicCall] then
        call:Activate()
    else
        call:Deactivate()
    end
    TotemTimers.OrderTimers()
end

-- Totemic Call learned
table.insert(TotemTimers.SpellUpdaters, function()
    TotemTimers.UpdateTotemicCallButton()
    local call = TotemTimers.TotemicCallTimer
    if call and call.active then CallEvent(call.button, "SPELL_UPDATE_COOLDOWN") end
end)
