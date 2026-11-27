if select(2,UnitClass("player")) ~= "SHAMAN" then return end

-- Combat cooldowns: a row (or two) of cooldown buttons of the spells of the specialization
-- (TotemTimers.CombatCooldownSpells), the Flame Shock duration timer and the Maelstrom tracker.

local _, TotemTimers = ...

local SpellIDs = TotemTimers.SpellIDs
local SpellTextures = TotemTimers.SpellTextures
local SpellNames = TotemTimers.SpellNames
local AvailableSpells = TotemTimers.AvailableSpells

local cds = {}
TotemTimers.EnhanceCDs = cds

local role = 2

local CDSpells = TotemTimers.CombatCooldownSpells

-- number of cooldown spells per specialization (also the bound of the order changes in the options)
local numCDSpells = {}
local maxCDSpells = 0
for spec, spells in pairs(CDSpells) do
    numCDSpells[spec] = #spells
    maxCDSpells = math.max(maxCDSpells, #spells)
end
TotemTimers.num_CD_Spells = numCDSpells

-- order of the cooldown buttons of a specialization (indices into CDSpells[spec]): the saved order
-- (EnhanceCDs_Order) without indices beyond the spell list and duplicates, missing indices appended; saved back
local function GetCDOrder(spec)
    local saved = TotemTimers.ActiveProfile.EnhanceCDs_Order[spec] or {}
    local order, seen = {}, {}
    for i = 1, #saved do
        local index = saved[i]
        if type(index) == "number" and index >= 1 and index <= (numCDSpells[spec] or 0) and not seen[index] then
            seen[index] = true
            order[#order + 1] = index
        end
    end
    for index = 1, numCDSpells[spec] or 0 do
        if not seen[index] then order[#order + 1] = index end
    end
    TotemTimers.ActiveProfile.EnhanceCDs_Order[spec] = order
    return order
end

local FlameShockDuration = null
local Maelstrom, MaelstromIcon --, MaelstromButton
-- stacks of a full Maelstrom bar (like the old tracker: Lightning Bolt/Chain Lightning are instant at 5)
local MAELSTROM_MAX_STACKS = 5
TotemTimers.MaelstromMaxStacks = MAELSTROM_MAX_STACKS -- also the glow of the Gamepad UI's Lightning Bolt buttons

-- a spell dragged (shift + drag from another cooldown button, or from the spell book) onto a cooldown button swaps
-- the two buttons (secure _onreceivedrag: kind "spell", the cursor info's spell ID is the fourth value)
local function ChangeCDOrder(self, _, _, spell)
    if InCombatLockdown() or not spell or not CDSpells[role] then return end

    local spell1 = TotemTimers.GetBaseSpellID(spell)
    local spell2 = self.cdspell and TotemTimers.GetBaseSpellID(self.cdspell)

    local order = GetCDOrder(role)
    local orderIndex1, orderIndex2
    for orderIndex, spellIndex in ipairs(order) do
        local cdspell = cds[spellIndex] and cds[spellIndex].button.cdspell
        if cdspell and TotemTimers.GetBaseSpellID(cdspell) == spell1 then orderIndex1 = orderIndex end
        if cdspell and TotemTimers.GetBaseSpellID(cdspell) == spell2 then orderIndex2 = orderIndex end
    end

    if orderIndex1 and orderIndex2 and orderIndex1 ~= orderIndex2 then
        order[orderIndex1], order[orderIndex2] = order[orderIndex2], order[orderIndex1]
        if TotemTimers.OrderCDs then TotemTimers.OrderCDs(tostring(role)) end
        TotemTimers.LayoutEnhanceCDs()
    end
end

function TotemTimers.CreateEnhanceCDs()
    -- cooldown buttons, as many as the longest spell list; the spells are assigned by ConfigEnhanceCDs
    for i = 1, maxCDSpells do
        local cd = XiTimers:new(1)
        cds[i] = cd
        cd.dontFlash = true
        cd.button.anchorframe = TotemTimers_EnhanceCDsFrame
        cd.button:SetAttribute("*type*", "spell")
        -- the icon is dimmed while the spell is on cooldown
        cd.reverseAlpha = true
        cd.alpha = 0.7
        cd.showCooldown = true
        cd.button.icons[1]:SetAlpha(1)
        cd.button.cooldown.noCooldownCount = true
        -- secure action buttons act on key down (CVar ActionButtonUseKeyDown), a button registered only for "Up"
        -- clicks never casts
        cd.button:RegisterForClicks("AnyDown")
        cd.Activate = function(self)
            XiTimers.Activate(self)
            local handler = self.button:GetScript("OnEvent")
            if handler then
                handler(self.button, "SPELL_UPDATE_COOLDOWN")
                handler(self.button, "PLAYER_TOTEM_UPDATE", FIRE_TOTEM_SLOT)
            end
            self:UpdateGCD()
        end
    end

    FlameShockDuration = XiTimers:new(1)
    TotemTimers.FlameShockDuration = FlameShockDuration
    -- leftclick casts Flame Shock (secure action buttons act on key down, see the Maelstrom button)
    FlameShockDuration.button:RegisterForClicks("AnyDown")
    FlameShockDuration.button.icons[1]:SetVertexColor(1,1,1)
    FlameShockDuration.button.bar:SetStatusBarColor(1,0.2,0.2,0.8)

    FlameShockDuration.button.icons[1]:SetTexture(SpellTextures[SpellIDs.FlameShock])
    FlameShockDuration.button.anchorframe = TotemTimers_EnhanceCDsFrame
    FlameShockDuration.dontAlpha = true
    FlameShockDuration.dontFlash = true
    FlameShockDuration.button:SetAttribute("*type1", "spell")
    FlameShockDuration.button:SetAttribute("spell1", SpellNames[SpellIDs.FlameShock])
    FlameShockDuration.button.icons[1]:SetAlpha(1)
	FlameShockDuration.rangeCheck = SpellNames[SpellIDs.FlameShock]
	FlameShockDuration.manaCheck = SpellNames[SpellIDs.FlameShock]
	FlameShockDuration.forceBar = true
    FlameShockDuration.timerBarPos = nil
    FlameShockDuration.timerBars[1]:ClearAllPoints()
    FlameShockDuration.timerBars[1]:SetPoint("LEFT", FlameShockDuration.button, "LEFT")
    FlameShockDuration.timerBars[1]:SetFrameStrata("LOW")
    FlameShockDuration:SetBarColor(1,0.5,0)

    -- The debuff can be secret, so it is displayed by an AuraDisplay (see AuraDisplay.lua) on the target.
    -- The XiTimers timer itself is never started, its (hidden) timer bar is the anchor and look of the
    -- display's bar: forceBar, starting at the button under the icon, as wide as set by LayoutEnhanceCDs.
    local display = TotemTimers.AuraDisplay:new(FlameShockDuration.button, "target")
    if display then
        display.iconAboveBar = true
        local spellIDs = {}
        for _, id in pairs(TotemTimers.FlameShockAuraSpells or { SpellIDs.FlameShock }) do
            spellIDs[id] = true
        end
        display:AddSlot("flameshock", spellIDs, 2, "HARMFUL|PLAYER")
        FlameShockDuration.auraDisplay = display
    end


    -- shift + drag picks the spell up (to drop it on another cooldown button: they swap places); the combat
    -- cooldowns are moved in the Edit Mode (EditMode.lua)
    for i = 1, #cds do
        cds[i].button:RegisterForDrag("LeftButton")
        cds[i].button:SetAttribute("_ondragstart", [[if IsShiftKeyDown() then
                                                    return "spell", self:GetAttribute("spell1")
                                              end]])
        cds[i].button:SetAttribute("_onreceivedrag", [[ if kind == "spell" then
                                                   control:CallMethod("ChangeCDOrder", value, ...)
                                                    return "clear"
                                              end]])
        cds[i].button.ChangeCDOrder = ChangeCDOrder
    end


    -- Maelstrom Weapon tracker: the stacks of the buff fill the bar and are shown on it. The buff can be secret,
    -- so it is displayed by an AuraDisplay (see AuraDisplay.lua) with an application bar; the stack count is never
    -- read in Lua, the XiTimers timer isn't started (its hidden timer bar is anchor and look of the display's bar).
    -- The button is clicked on itself and on its bar (its hit rect reaches over the bar, see LayoutEnhanceCDs):
    -- leftclick Lightning Bolt, rightclick Chain Lightning.
    Maelstrom = XiTimers:new(1)
    TotemTimers.Maelstrom = Maelstrom

    Maelstrom.button.icons[1]:SetVertexColor(1,1,1)
    Maelstrom.button.icons[1]:SetTexture((C_Spell.GetSpellTexture(SpellIDs.Maelstrom)))
    Maelstrom.button.anchorframe = TotemTimers_EnhanceCDsFrame
    Maelstrom.dontAlpha = true
    Maelstrom.dontFlash = true
    Maelstrom.button:SetAttribute("*type*", "spell")
    -- like the other timer buttons: secure action buttons act on key down (CVar ActionButtonUseKeyDown), a button
    -- registered only for "Up" clicks never casts
    Maelstrom.button:RegisterForClicks("AnyDown")
    Maelstrom.button:SetAttribute("spell1", SpellIDs.LightningBolt)
    Maelstrom.button:SetAttribute("spell2", SpellIDs.ChainLightning)
    Maelstrom.button.icons[1]:SetAlpha(1)
    Maelstrom.rangeCheck = SpellNames[SpellIDs.LightningBolt]
    Maelstrom.manaCheck = SpellNames[SpellIDs.LightningBolt]
    Maelstrom.forceBar = true
    Maelstrom.timerBarPos = nil
    Maelstrom.timerBars[1]:ClearAllPoints()
    Maelstrom.timerBars[1]:SetPoint("LEFT", Maelstrom.button, "LEFT")
    Maelstrom.timerBars[1]:SetFrameStrata("LOW")
    Maelstrom:SetTimeWidth(100)
    -- the bar shows a lightning bolt in the style of the Lightning Bolt icon, drawn for the bar's shape without the
    -- icon's border (textures/lightning_bar.tga, tools/lightning_texture.py), uncolored; the aura display takes over
    -- texture and colors of this bar (the bar texture setting TimerBarTexture skips Maelstrom)
    local lightningTexture = "Interface\\AddOns\\TotemTimers\\textures\\lightning_bar"
    Maelstrom.timerBars[1]:SetStatusBarTexture(lightningTexture)
    Maelstrom.timerBars[1].background:SetStatusBarTexture(lightningTexture)
    Maelstrom:SetBarColor(1, 1, 1, 1)
    Maelstrom.button.icons[1]:SetAllPoints(Maelstrom.button)
    Maelstrom.Update = function() end

    local spellIDs = {}
    for _, id in pairs(TotemTimers.MaelstromAuraSpells or {}) do
        spellIDs[id] = true
    end

    local msDisplay = TotemTimers.AuraDisplay:new(Maelstrom.button)
    if msDisplay then
        msDisplay.iconAboveBar = true
        msDisplay.maxApplications = MAELSTROM_MAX_STACKS
        msDisplay:SetTimeShown(false)
        msDisplay:AddSlot("maelstrom", spellIDs, 2)
        Maelstrom.auraDisplay = msDisplay

        -- glow around button and bar (the hidden timer bar spans both) from 5 stacks on, decided by the game (an
        -- aura feeds only one application bar per slot button, so the glow has a display of its own); below the
        -- stack display, so the glow only brightens around it
        local glowDisplay = TotemTimers.AuraDisplay:new(Maelstrom.button, "player", {
            glow = { region = Maelstrom.timerBars[1], minApplications = MAELSTROM_MAX_STACKS },
        })
        if glowDisplay then
            glowDisplay:AddSlot("maelstromglow", spellIDs, 1)
            Maelstrom.glowDisplay = glowDisplay
        end
    end

    -- the large stack icon above the bar: textures/mw<n> for n stacks (the images add a bolt per stack, mw5 adds the
    -- emblem), from 5 stacks on mw5 with a slight pulse. The stacks can be secret, so each image is an AuraDisplay
    -- in image mode of its own (one application bar per slot button), shown by the game for exactly its count
    -- (mw5: from 5 on). The icon has its own settings (MaelstromLayout "bar" hides it,
    -- MaelstromIconSize) and is no child of the button: it stays visible when the Gamepad UI option
    -- GamePadHideTimers makes the button invisible; it is shown with the active tracker (UpdateMaelstromIcon).
    MaelstromIcon = CreateFrame("Frame", "TotemTimers_MaelstromIcon", UIParent)
    TotemTimers.MaelstromIcon = MaelstromIcon
    MaelstromIcon:SetSize(100, 50)
    MaelstromIcon:SetFrameStrata(Maelstrom.button:GetFrameStrata())
    MaelstromIcon:SetFrameLevel(Maelstrom.button:GetFrameLevel())
    MaelstromIcon:Hide()
    Maelstrom.iconDisplays = {}
    for count = 1, MAELSTROM_MAX_STACKS do
        local last = count == MAELSTROM_MAX_STACKS
        local display = TotemTimers.AuraDisplay:new(MaelstromIcon, "player", {
            image = {
                region = MaelstromIcon,
                texture = "Interface/AddOns/TotemTimers/textures/mw" .. count,
                applications = count,
                exact = not last,
                pulse = last,
            },
        })
        if display then
            display:AddSlot("maelstrom" .. count, spellIDs, 3 + count)
            Maelstrom.iconDisplays[count] = display
        end
    end

    -- the warning and the glow of the Lightning Bolt/Chain Lightning buttons need the stack count in Lua, which can
    -- be secret (the Gamepad UI's Lightning Bolt buttons show stacks and glow with AuraDisplays)
end

table.insert(TotemTimers.Modules, TotemTimers.CreateEnhanceCDs)

-- preview of the stack icon while the options are open: the 5 stacks image (with its pulse) over the icon, so
-- size changes are seen directly; the real icon is made invisible meanwhile. A plain frame of its own (the aura
-- displays only show what the game decides), created on first use.
local maelstromPreview

local function GetMaelstromPreview()
    if maelstromPreview then return maelstromPreview end
    local preview = CreateFrame("Frame", nil, UIParent)
    preview:SetAllPoints(MaelstromIcon)
    preview:SetFrameStrata(MaelstromIcon:GetFrameStrata())
    preview:SetFrameLevel(MaelstromIcon:GetFrameLevel() + 10)
    preview:Hide()
    local texture = preview:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(preview)
    texture:SetTexture("Interface/AddOns/TotemTimers/textures/mw" .. MAELSTROM_MAX_STACKS)
    -- the same pulse as the image mode of AuraDisplay
    local pulse = preview:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local scale = pulse:CreateAnimation("Scale")
    scale:SetTarget(texture)
    scale:SetScaleFrom(1, 1)
    scale:SetScaleTo(1.06, 1.06)
    scale:SetOrigin("CENTER", 0, 0)
    scale:SetDuration(0.4)
    scale:SetSmoothing("IN_OUT")
    preview.pulse = pulse
    maelstromPreview = preview
    return preview
end

-- Maelstrom tracker enabled (talent and options, set by ConfigEnhanceCDs); the layout setting MaelstromLayout
-- decides what is shown: "both" (bar + stack icon), "bar" (bar only), "icon" (stack icon only, in the place of the
-- bar, the button isn't activated), "gamepad" (neither, only the overlays of the Gamepad UI's Lightning Bolt
-- buttons, GamePad/GamePadActionButtons.lua, which need the tracker enabled in every layout)
local maelstromEnabled = false
local MAELSTROM_LAYOUTS = { both = true, bar = true, icon = true, gamepad = true }

local function GetMaelstromLayout()
    local layout = TotemTimers.ActiveProfile.MaelstromLayout
    return MAELSTROM_LAYOUTS[layout] and layout or "both"
end

TotemTimers.GetMaelstromLayout = GetMaelstromLayout

-- Flame Shock timer enabled (spell known and enabled for the specialization, set by ConfigEnhanceCDs); with option
-- FlameShockDurationGamePadOnly the timer button isn't activated and the time is only shown on the Gamepad UI's
-- Flame Shock buttons (GamePad/GamePadActionButtons.lua, which need the timer enabled), like the Maelstrom layout
-- "gamepad"
local flameShockEnabled = false

function TotemTimers.IsFlameShockEnabled()
    return flameShockEnabled
end

function TotemTimers.IsFlameShockGamePadOnly()
    return TotemTimers.ActiveProfile.FlameShockDurationGamePadOnly and true or false
end

function TotemTimers.IsMaelstromEnabled()
    return maelstromEnabled
end

-- the stack icon is shown while the tracker is enabled with the layouts "both" and "icon"; while the options are
-- open the preview replaces it
-- opacity of the icon: above the character it follows the game's opacity of proc graphics (CVar
-- spellActivationOverlayOpacity, "Spell Alert Opacity", 0 to 1; SpellActivationOverlay.lua sets it as the alpha of
-- its frame), otherwise opaque
local function GetMaelstromIconAlpha()
    if not TotemTimers.ActiveProfile.MaelstromIconAtCharacter then return 1 end
    local value = tonumber(C_CVar.GetCVar("spellActivationOverlayOpacity"))
    if not value then return 1 end
    return math.max(0, math.min(1, value))
end

function TotemTimers.UpdateMaelstromIcon()
    if not MaelstromIcon or not TotemTimers.ActiveProfile then return end
    local layout = GetMaelstromLayout()
    local shown = maelstromEnabled and (layout == "both" or layout == "icon")
    MaelstromIcon:SetShown(shown)
    local previewShown = shown and TotemTimers.IsOptionsShown and TotemTimers.IsOptionsShown() or false
    -- the out-of-combat fade of the tracker (EnhanceCDsOOCAlpha, mouseover alpha) on top
    local alpha = GetMaelstromIconAlpha() * (Maelstrom.button:GetAlpha() or 1)
    MaelstromIcon:SetAlpha(previewShown and 0 or alpha)
    if previewShown or maelstromPreview then
        local preview = GetMaelstromPreview()
        preview:SetShown(previewShown)
        preview:SetAlpha(alpha)
        if previewShown then
            preview.pulse:Play()
        else
            preview.pulse:Stop()
        end
    end
end

TotemTimers.OptionsShownChanged = function(shown)
    TotemTimers.UpdateMaelstromIcon()
end

-- the tracker's button was faded (out of combat, mouseover): the icon isn't its child, so it follows here
hooksecurefunc(XiTimers, "UpdateFade", function() TotemTimers.UpdateMaelstromIcon() end)

-- the game's opacity of proc graphics changed (Options > Combat or Accessibility)
local cvarFrame = CreateFrame("Frame")
cvarFrame:RegisterEvent("CVAR_UPDATE")
cvarFrame:SetScript("OnEvent", function(_, _, name)
    if type(name) == "string" and name:lower() == "spellactivationoverlayopacity" then
        TotemTimers.UpdateMaelstromIcon()
    end
end)

-- the Gamepad UI buttons with Flame Shock show its duration while the Flame Shock timer is active
-- (GamePad/GamePadActionButtons.lua, loaded later)
local function UpdateGamePadButtons()
    local GamePad = TotemTimers.GamePad
    if GamePad and GamePad.UpdateActionButtons then
        GamePad.UpdateActionButtons()
    end
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- Glow of a cooldown button: the game's proc glow of the spell (procGlow) and, for the spells in RESET_GLOW, a glow
-- when the cooldown ends early (resetGlow: for RESET_GLOW seconds or until the spell goes on cooldown again). The
-- glow is shown while either is on.
local RESET_GLOW = {
    [SpellIDs.StormStrike] = 3,
}

local function UpdateCooldownGlow(timer)
    local button = timer.button
    if button.procGlow or button.resetGlow then
        timer:ShowOverlayGlow()
    else
        timer:HideOverlayGlow()
    end
end

-- names of the spells whose reset glow is on, also shown on the Gamepad UI buttons of these spells
-- (GamePad/GamePadActionButtons.lua, with option GamePadTimers)
local resetGlowNames = {}

function TotemTimers.GetResetGlowNames()
    return resetGlowNames
end

local function UpdateResetGlowNames()
    wipe(resetGlowNames)
    for _, cd in ipairs(cds) do
        local name = cd.button.resetGlow and cd.button.cdspell and SpellNames[cd.button.cdspell]
        if name then resetGlowNames[name] = true end
    end
    local GamePad = TotemTimers.GamePad
    if GamePad and GamePad.UpdateResetGlows then GamePad.UpdateResetGlows() end
end

local function SetResetGlow(button, duration)
    -- a token per glow, so the end of an older one doesn't hide a newer one
    local token = duration and {} or nil
    button.resetGlow = token
    UpdateCooldownGlow(button.timer)
    UpdateResetGlowNames()
    if token then
        C_Timer.After(duration, function()
            if button.resetGlow == token then
                button.resetGlow = nil
                UpdateCooldownGlow(button.timer)
                UpdateResetGlowNames()
            end
        end)
    end
end

-- the cooldown timer was stopped before its duration ran out (XiTimers:Stop, like the early expiration warnings):
-- the cooldown was reset, glow for the spells in RESET_GLOW, with option EnhanceCDsStopPulse also the stop pulse
local function OnEarlyStop(timer)
    local button = timer.button
    local glow = button.cdspell and RESET_GLOW[button.cdspell]
    if glow and timer.active then
        SetResetGlow(button, glow)
        if timer.ResetPulse then
            timer:PlayStopPulse()
        end
    end
end

-- events of a cooldown button: the cooldown of its spell, and the game's proc glow of the spell.
-- The cooldown can be secret, so the timer is started with a DurationObject of the cooldown and only the never
-- secret isActive and isOnGCD flags of the cooldown info are read (like the Ankh tracker).
local function CooldownEvent(self, event, spellID)
    local spell = self.cdspell and SpellNames[self.cdspell]
    if not spell then return end
    if event == "SPELL_UPDATE_COOLDOWN" then
        local info = C_Spell.GetSpellCooldown(spell)
        if not info or not info.isActive then
            self.timer:Stop(1)
        elseif info.isOnGCD then
            -- only the global cooldown is left: the own cooldown ended or was reset during it (an early stop only if
            -- it would have run longer than the GCD, XiTimers:EarlyStop)
            if self.timer.timers[1] then
                self.timer:Stop(1, C_Spell.GetSpellCooldownDuration(spell))
            end
        elseif not self.timer.timers[1] then
            local durObj = C_Spell.GetSpellCooldownDuration(spell, true)
            if durObj then
                self.timer:Start(1, durObj)
                -- on cooldown again: the glow of an early end ends
                if self.resetGlow then SetResetGlow(self, nil) end
            end
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if not spellID or IsSecret(spellID) then return end
        if C_Spell.GetSpellName(spellID) == spell then
            self.procGlow = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or nil
            UpdateCooldownGlow(self.timer)
        end
    end
end

local COOLDOWN_EVENTS = {}
for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }) do
    if C_EventUtils.IsEventValid(event) then table.insert(COOLDOWN_EVENTS, event) end
end

-- the totem timer of the fire element (the timers 1-4 can be reordered, Settings.lua Order)
local function GetFireTotemTimer()
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        if timer and timer.nr == FIRE_TOTEM_SLOT then return timer end
    end
end

-- Searing and Magma Totem have no cooldown: their buttons show the remaining time of the totem while it is the
-- active fire totem. The totem data can be secret, so the time is taken from the fire totem timer (its totem,
-- activeTotem, is also known in combat, see SetupTimers.lua TotemEvent), after it has handled the event; without an
-- active fire totem timer the buttons show nothing.
local function FireTotemEvent(self, event, slot)
    if event ~= "PLAYER_TOTEM_UPDATE" or slot ~= FIRE_TOTEM_SLOT then return end
    C_Timer.After(0, function()
        local timer = self.timer
        if not timer.active then return end
        local fire = GetFireTotemTimer()
        local durObj = fire and fire.active and fire.timers[1]
        local totem = fire and fire.activeTotem
        if durObj and totem and self.cdspell
                and TotemTimers.GetBaseSpellID(totem) == TotemTimers.GetBaseSpellID(self.cdspell) then
            if timer.timers[1] ~= durObj then timer:Start(1, durObj) end
        elseif timer.timers[1] then
            timer:Stop(1)
        end
    end)
end

-- spells cast by the right and middle button of the shock buttons
local SHOCK_ALTERNATIVES = {
    [SpellIDs.FlameShock] = { SpellIDs.EarthShock, SpellIDs.FrostShock },
    [SpellIDs.EarthShock] = { SpellIDs.FlameShock, SpellIDs.FrostShock },
}

-- option EnhanceCDsStopPulse: only the Stormstrike button pulses, and only when its cooldown ends early (reset,
-- OnEarlyStop), not on every stop (StopPulse stays off)
local function UpdateStopPulse(cd)
    local profile = TotemTimers.ActiveProfile
    cd.ResetPulse = profile and profile.EnhanceCDsStopPulse and cd.button.cdspell == SpellIDs.StormStrike or false
end

function TotemTimers.UpdateCDStopPulse()
    for _, cd in ipairs(cds) do
        UpdateStopPulse(cd)
    end
end

-- assigns the spell (from CombatCooldownSpells, nil: none) to a cooldown button
local function SetCooldownSpell(cd, spell)
    local button = cd.button
    -- a timer of the previous spell
    if cd.timers[1] then
        cd.stopQuiet = true
        cd:Stop(1)
    end
    cd:CancelEarlyStop(1)
    button.procGlow = nil
    if button.resetGlow then
        button.resetGlow = nil
        UpdateResetGlowNames()
    end
    if cd.HideOverlayGlow then cd:HideOverlayGlow() end
    button.cdspell = spell
    UpdateStopPulse(cd)
    if not spell then return end

    -- Way of Earth changes Earth Shock
    if spell == SpellIDs.EarthShock and SpellIDs.WayOfEarth and SpellIDs.EarthShockTank
            and AvailableSpells[SpellIDs.WayOfEarth] then
        button.cdspell = SpellIDs.EarthShockTank
    end
    local isFireTotem = spell == SpellIDs.Searing or spell == SpellIDs.Magma

    button.icons[1]:SetTexture(SpellTextures[spell])
    local alternatives = SHOCK_ALTERNATIVES[spell]
    button:SetAttribute("spell1", spell)
    button:SetAttribute("spell2", alternatives and alternatives[1] or nil)
    button:SetAttribute("spell3", alternatives and alternatives[2] or nil)
    button:SetAttribute("orderspell", spell)
    -- the highest known ranks
    TotemTimers.UpdateRank(button)

    -- totems have no range
    cd.rangeCheck = not isFireTotem and SpellNames[spell] or nil
    cd.manaCheck = SpellNames[spell]
    cd.prohibitCooldown = false
    cd.playerEvents = {}
    if isFireTotem then
        cd.events = { "PLAYER_TOTEM_UPDATE" }
        button:SetScript("OnEvent", FireTotemEvent)
        cd.OnEarlyStop = nil
    else
        cd.events = { unpack(COOLDOWN_EVENTS) }
        button:SetScript("OnEvent", CooldownEvent)
        cd.OnEarlyStop = OnEarlyStop
    end
end

function TotemTimers.ConfigEnhanceCDs()
    role = TotemTimers.Specialization --GetSpecialization()
    if not role then role = 0 end

    for i = 1, #cds do
        cds[i]:Deactivate()
    end
    FlameShockDuration:Deactivate()
    flameShockEnabled = false
    Maelstrom:Deactivate()
    maelstromEnabled = false
    TotemTimers.UpdateMaelstromIcon()

    if role == 0 or not TotemTimers.ActiveProfile.EnhanceCDs then
        UpdateGamePadButtons()
        return
    end

    local spells = CDSpells[role] or {}
    for i = 1, #cds do
        SetCooldownSpell(cds[i], spells[i])
    end

    if AvailableSpells[SpellIDs.FlameShock] and TotemTimers.ActiveProfile.EnhanceCDsFlameShockDuration_Specialization[role] then
        flameShockEnabled = true
        if not TotemTimers.IsFlameShockGamePadOnly() then
            FlameShockDuration:Activate()
        end
    end

    if TotemTimers.AvailableTalents.Maelstrom and TotemTimers.ActiveProfile.EnhanceCDsMaelstrom then
        maelstromEnabled = true
        local layout = GetMaelstromLayout()
        if layout == "both" or layout == "bar" then
            Maelstrom:Activate()
        end
    end
    TotemTimers.UpdateMaelstromIcon()
    UpdateGamePadButtons()

    local enabled = TotemTimers.ActiveProfile.EnhanceCDs_Spells[role] or {}
    for i = 1, #spells do
        if enabled[i] and AvailableSpells[spells[i]] then
            cds[i]:Activate()
        end
    end
end


-- side of the game's proc graphics frame at the screen center (SpellActivationOverlay.lua: 256 * 0.8)
local OVERLAY_LONG_SIDE = 256 * 0.8

local function SizeToWidthHeight(size)
    size = min(3, size or 1)

    local spacing = TotemTimers.ActiveProfile.CooldownSpacing
    local height = 19 + (size-1) * 4

    --button + bar = 3 normal buttons + spacing, 4 btn for size 2, 5 btn for size 3
    local width = 108 + spacing * 2
    width = width + (size-1) * (36 + spacing)

    return width, height
end

-- the cooldown buttons in one row centered on the anchor frame, or with more than 5 buttons (and not
-- EnhanceCDsOneRow) in two rows; returns the top and bottom edge of the rows relative to the anchor frame's center
local function LayoutCooldownRows(activeCDs)
    local frame = TotemTimers_EnhanceCDsFrame
    local numActiveCDs = #activeCDs
    local topRow, bottomRow = numActiveCDs, 0

    if numActiveCDs > 5 and not TotemTimers.ActiveProfile.EnhanceCDsOneRow then
        topRow = floor(numActiveCDs / 2)
        bottomRow = ceil(numActiveCDs / 2)
    end

    local split = ceil(topRow / 2)
    if topRow % 2 == 0 then
        activeCDs[split]:SetPoint("RIGHT", frame, "CENTER", true)
    else
        activeCDs[split]:SetPoint("CENTER", frame)
    end

    for i = split - 1, 1, -1 do
        activeCDs[i]:Anchor(activeCDs[i + 1], "RIGHT")
    end
    for i = split + 1, topRow do
        activeCDs[i]:Anchor(activeCDs[i - 1], "LEFT")
    end

    if bottomRow > 0 then
        local bottomSplit = topRow + ceil(bottomRow / 2)
        if bottomRow == topRow then
            activeCDs[bottomSplit]:Anchor(activeCDs[split], "TOP")
        elseif topRow % 2 == 0 then
            activeCDs[bottomSplit]:Anchor(activeCDs[split], "TOPLEFT", "BOTTOM", true)
        else
            activeCDs[bottomSplit]:Anchor(activeCDs[split], "TOPRIGHT", "BOTTOM", true)
        end
        for i = bottomSplit - 1, topRow + 1, -1 do
            activeCDs[i]:Anchor(activeCDs[i + 1], "RIGHT")
        end
        for i = bottomSplit + 1, numActiveCDs do
            activeCDs[i]:Anchor(activeCDs[i - 1], "LEFT")
        end
    end

    -- the buttons are 36 high, scaled by EnhanceCDsSize; their offsets (spacing, timer bars) are in their own scale
    local cd = activeCDs[1]
    local scale = cd.button:GetScale()
    local topBorder, bottomBorder = cd:GetBorder("TOP"), cd:GetBorder("BOTTOM")
    local top = (18 + topBorder) * scale
    local bottom = -(18 + bottomBorder) * scale
    if bottomRow > 0 then
        bottom = bottom - (cd.spacing + topBorder + 36 + bottomBorder) * scale
    end
    return top, bottom
end

function TotemTimers.LayoutEnhanceCDs()
    if role == 0 then return end

    local activeCDs = {}
    if CDSpells[role] then
        for _, index in ipairs(GetCDOrder(role)) do
            if cds[index] and cds[index].active then
                table.insert(activeCDs, cds[index])
            end
        end
    end
    for i = 1, #cds do
        cds[i]:ClearAnchors()
        cds[i].button:ClearAllPoints()
    end
    FlameShockDuration.button:ClearAllPoints()

    local width, height = SizeToWidthHeight(FlameShockDuration.size)

    FlameShockDuration:SetTimeWidth(width)
    FlameShockDuration:SetTimeHeight(height)
    FlameShockDuration.button:SetSize(height, height)
    FlameShockDuration.button.icons[1]:SetAllPoints(FlameShockDuration.button)

    local msWidth, msHeight = SizeToWidthHeight(Maelstrom.size)
    Maelstrom.button:ClearAllPoints()
    Maelstrom:SetTimeWidth(msWidth)
    Maelstrom:SetTimeHeight(msHeight)
    Maelstrom.button:SetSize(msHeight, msHeight)
    Maelstrom.button.icons[1]:SetAllPoints(Maelstrom.button)
    -- the bar starts at the button and is msWidth wide: a negative right inset extends the button's clickable area
    -- over the whole bar
    Maelstrom.button:SetHitRectInsets(0, msHeight - msWidth, 0, 0)

    -- the stack icon above the bar (centered over button + bar, the hidden timer bar spans both; the images are
    -- 2:1 with the bolts in their lower half, so the icon reaches a little into the bar's top); its size setting
    -- MaelstromIconSize scales it (1 = 75% of the bar's width)
    -- option MaelstromIconAtCharacter: the icon above the character instead, where the game shows proc graphics at
    -- the top (SpellActivationOverlay.lua: a 204.8 square frame at the screen center, "Top" overlays 204.8 x 102.4
    -- (2:1 like the mw textures) on its top edge); MaelstromIconSize scales it there too. Its bottom edge is at the
    -- anchor frame TotemTimers_MaelstromIconFrame (default on that top edge), moved in the Edit Mode
    local atCharacter = TotemTimers.ActiveProfile.MaelstromIconAtCharacter
    local iconScale = TotemTimers.ActiveProfile.MaelstromIconSize or 1
    local iconWidth = atCharacter and OVERLAY_LONG_SIDE * iconScale or msWidth * 0.75 * iconScale
    MaelstromIcon:SetSize(iconWidth, iconWidth / 2)
    MaelstromIcon:ClearAllPoints()
    -- displays whose look depends on these sizes (glow outset, mask margin) are rebuilt if they changed
    for _, display in pairs(Maelstrom.iconDisplays or {}) do display:ScheduleBuild() end
    if Maelstrom.glowDisplay then Maelstrom.glowDisplay:ScheduleBuild() end
    -- the icon alone in the place of the bar (not with the icon above the character)
    local iconOnly = maelstromEnabled and GetMaelstromLayout() == "icon" and not atCharacter
    if atCharacter then
        MaelstromIcon:SetPoint("BOTTOM", TotemTimers_MaelstromIconFrame, "CENTER")
    elseif not iconOnly then
        MaelstromIcon:SetPoint("BOTTOM", Maelstrom.timerBars[1], "TOP", 0, -iconWidth / 2 * 0.15)
    end

    local frame = TotemTimers_EnhanceCDsFrame
    local halfSpacing = TotemTimers.ActiveProfile.CooldownSpacing / 2

    if #activeCDs > 0 then
        -- the cooldown rows centered on the anchor frame; the Flame Shock timer above them (FlameShockDurationOnTop)
        -- or below them, the Maelstrom tracker (bar or, with layout "icon", the stack icon) above everything
        local spacing = TotemTimers.ActiveProfile.CooldownSpacing
        local top, bottom = LayoutCooldownRows(activeCDs)
        local y = top + spacing
        if FlameShockDuration.active and TotemTimers.ActiveProfile.FlameShockDurationOnTop then
            FlameShockDuration.button:SetPoint("BOTTOMLEFT", frame, "CENTER", -width / 2, y)
            y = y + height + spacing
        else
            FlameShockDuration.button:SetPoint("TOPLEFT", frame, "CENTER", -width / 2, bottom - spacing)
        end
        if iconOnly then
            MaelstromIcon:SetPoint("BOTTOM", frame, "CENTER", 0, y)
        end
        -- the inactive button (layout "icon") keeps a position (its bar isn't shown)
        Maelstrom.button:SetPoint("BOTTOMLEFT", frame, "CENTER", -msWidth / 2, y)
    elseif iconOnly then
        -- without cooldown buttons the Flame Shock timer and the Maelstrom tracker (each button + bar) are centered
        -- on the anchor frame, with both active the Maelstrom tracker on top
        -- the icon alone in the place of the bar: above the Flame Shock timer, otherwise centered on the anchor
        if FlameShockDuration.active then
            MaelstromIcon:SetPoint("BOTTOM", frame, "CENTER", 0, halfSpacing)
            FlameShockDuration.button:SetPoint("TOPLEFT", frame, "CENTER", -width / 2, -halfSpacing)
        else
            MaelstromIcon:SetPoint("CENTER", frame, "CENTER")
            FlameShockDuration.button:SetPoint("LEFT", frame, "CENTER", -width / 2, 0)
        end
        -- the inactive button keeps a position (its bar isn't shown)
        Maelstrom.button:SetPoint("LEFT", frame, "CENTER", -msWidth / 2, 0)
    elseif FlameShockDuration.active and Maelstrom.active then
        Maelstrom.button:SetPoint("BOTTOMLEFT", frame, "CENTER", -msWidth / 2, halfSpacing)
        FlameShockDuration.button:SetPoint("TOPLEFT", frame, "CENTER", -width / 2, -halfSpacing)
    else
        Maelstrom.button:SetPoint("LEFT", frame, "CENTER", -msWidth / 2, 0)
        FlameShockDuration.button:SetPoint("LEFT", frame, "CENTER", -width / 2, 0)
    end
end

function TotemTimers.ActivateEnhanceCDs()
    TotemTimers.ConfigEnhanceCDs()
    TotemTimers.LayoutEnhanceCDs()
end

function TotemTimers.DeactivateEnhanceCDs()
    for i = 1, #cds do
        cds[i]:Deactivate()
    end
    FlameShockDuration:Deactivate()
    flameShockEnabled = false
    Maelstrom:Deactivate()
    maelstromEnabled = false
    TotemTimers.UpdateMaelstromIcon()
    UpdateGamePadButtons()
end
