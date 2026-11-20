if select(2,UnitClass("player")) ~= "SHAMAN" then return end

-- For now only the Flame Shock duration timer and the Maelstrom tracker are active, everything else is commented out.

local _, TotemTimers = ...

local SpellIDs = TotemTimers.SpellIDs
local SpellTextures = TotemTimers.SpellTextures
local SpellNames = TotemTimers.SpellNames
local AvailableSpells = TotemTimers.AvailableSpells
--local FlameShockID = SpellIDs.FlameShock
--local FlameShockName = SpellNames[SpellIDs.FlameShock]

--[==[
local cds = {}
TotemTimers.EnhanceCDs = cds
]==]

local role = 2

--[==[
local function NoUpdate()
end

local ShieldName = SpellNames[SpellIDs.LightningShield]

local CDSpells = TotemTimers.CombatCooldownSpells
]==]

local FlameShockDuration = null
local Maelstrom, MaelstromIcon --, MaelstromButton
-- stacks of a full Maelstrom bar (like the old tracker: Lightning Bolt/Chain Lightning are instant at 5)
local MAELSTROM_MAX_STACKS = 5
TotemTimers.MaelstromMaxStacks = MAELSTROM_MAX_STACKS -- also the glow of the Gamepad UI's Lightning Bolt buttons

--[==[
local CenterProcAnchor = CreateFrame("Frame", "CenterProcAnchor", UIParent)
TotemTimers.EnhanceCDsCenterProcAnchor = CenterProcAnchor
CenterProcAnchor:Hide()
CenterProcAnchor:SetSize(130,65)
CenterProcAnchor:Show()

local LeftProcAnchor = CreateFrame("Frame", "LeftProcAnchor", UIParent)
TotemTimers.EnhanceCDsLeftProcAnchor = LeftProcAnchor
LeftProcAnchor:Hide()
LeftProcAnchor:SetSize(65, 130)



local RightProcAnchor = CreateFrame("Frame", nil, UIParent)
TotemTimers.EnhanceCDsRightProcAnchor = RightProcAnchor
RightProcAnchor:Hide()
RightProcAnchor:SetSize(65, 130)


local function ChangeCDOrder(self, _, _, spell)
    if InCombatLockdown() then return end
    if not spell then return end

    local spell1 = TotemTimers.GetBaseSpellID(spell)
    local spell2 = TotemTimers.GetBaseSpellID(self:GetAttribute("spell1"))

    local orderIndex1, orderIndex2

    for orderIndex, spellIndex in pairs(TotemTimers.ActiveProfile.EnhanceCDs_Order[TotemTimers.Specialization]) do
        if CDSpells[role][spellIndex] == spell1 then orderIndex1 = orderIndex end
        if CDSpells[role][spellIndex] == spell2 then orderIndex2 = orderIndex end
    end

    if orderIndex1 and orderIndex2 then
        TotemTimers.ActiveProfile.EnhanceCDs_Order[role][orderIndex1], TotemTimers.ActiveProfile.EnhanceCDs_Order[role][orderIndex2] =
            TotemTimers.ActiveProfile.EnhanceCDs_Order[role][orderIndex2], TotemTimers.ActiveProfile.EnhanceCDs_Order[role][orderIndex1]
    end

    TotemTimers.LayoutEnhanceCDs()
end
]==]

function TotemTimers.CreateEnhanceCDs()
    --[==[
    for i = 1,12 do
        cds[i] = XiTimers:new(1)
        cds[i].events = {"SPELL_UPDATE_COOLDOWN"}
        cds[i].dontFlash = true
        cds[i].button.anchorframe = TotemTimers_EnhanceCDsFrame
        cds[i].button:SetAttribute("*type*", "spell")
        cds[i].reverseAlpha = true
        cds[i].alpha = 0.7
        cds[i].button.icons[1]:SetAlpha(1)
        cds[i].button:SetScript("OnEvent", TotemTimers.EnhanceCDEvents)
        cds[i].button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    end
    ]==]

    FlameShockDuration = XiTimers:new(1)
    TotemTimers.FlameShockDuration = FlameShockDuration
    FlameShockDuration.button:Disable()
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


    --[==[
    for i=1,#cds do
        cds[i].button:SetAttribute("_ondragstart",[[if IsShiftKeyDown() then
                                                    return "spell", self:GetAttribute("spell1")
                                              else control:CallMethod("StartMove") end]])
        cds[i].button:SetAttribute("_onreceivedrag",[[ if kind == "spell" then
                                                   control:CallMethod("ChangeCDOrder", value, ...)
                                                    return "clear"
                                              end]])
        cds[i].button.ChangeCDOrder = ChangeCDOrder
    end
    ]==]


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

function TotemTimers.ConfigEnhanceCDs()
    role = TotemTimers.Specialization --GetSpecialization()
    if not role then role = 0 end

    --[==[
    for i=1,#cds do
        cds[i]:Deactivate()
    end
    ]==]
    FlameShockDuration:Deactivate()
    Maelstrom:Deactivate()
    maelstromEnabled = false
    TotemTimers.UpdateMaelstromIcon()

    if role == 0 or not TotemTimers.ActiveProfile.EnhanceCDs then
        UpdateGamePadButtons()
        return
    end

    --[==[
    if LE_EXPANSION_LEVEL_CURRENT > LE_EXPANSION_WRATH_OF_THE_LICH_KING and role == 2 then
        for id, spell in ipairs(CDSpells[role]) do
            if spell == SpellIDs.StormStrike or spell == SpellIDs.PrimalStrike then
                if AvailableSpells[SpellIDs.StormStrike] then
                    CDSpells[role][id] = SpellIDs.StormStrike
                else
                    CDSpells[role][id] = SpellIDs.PrimalStrike
                end
                break
            end
        end
    end

    for i=1,#CDSpells[role] do
        local spell = CDSpells[role][i]
        local cd = cds[i]
        cd.button.cdspell = spell
        cd.button.icons[1]:SetTexture(SpellTextures[spell])
        cd.button:SetAttribute("spell1", spell)
        if spell == SpellIDs.FlameShock then
            cd.button:SetAttribute("spell2", SpellIDs.EarthShock)
            cd.button:SetAttribute("spell3", SpellIDs.FrostShock)
        elseif spell == SpellIDs.EarthShock then
            if SpellIDs.WayOfEarth and AvailableSpells[SpellIDs.WayOfEarth] then
                cd.button.cdspell = SpellIDs.EarthShockTank
            end
            cd.button:SetAttribute("spell2", SpellIDs.FlameShock)
            cd.button:SetAttribute("spell2", SpellIDs.FrostShock)
        else
		    cd.button:SetAttribute("spell2", nil)
		end
		cd.button:SetAttribute("spell3", nil)
        cd.rangeCheck = SpellNames[CDSpells[role][i]]
        cd.manaCheck = SpellNames[CDSpells[role][i]]
        cd.Update = nil
        cd.prohibitCooldown = false
        cd.button:SetAttribute("orderspell", CDSpells[role][i])

        cd.reverseAlpha = true
        cd.Stop = nil

        cd.events = {"SPELL_UPDATE_COOLDOWN"}
        cd.playerEvents = {}

        --cd.button.bar:SetStatusBarColor(0.6,0.6,1.0,0.5)

        --[[if spell == SpellIDs.FlameShock or spell == SpellIDs.EarthShock then
            cd.button:SetScript("OnEvent", TotemTimers.ShockEvent)
            cd.playerEvents[1] = "UNIT_AURA"
        else]]
        if spell == SpellIDs.StormStrike then
            cd.button:SetScript("OnEvent", TotemTimers.StormStrikeEvent)
            cd.events[2] = "UNIT_AURA"
            cd.events[3] = "PLAYER_TARGET_CHANGED"
        elseif spell == SpellIDs.Searing or spell == SpellIDs.Magma then
            cd.button:SetScript("OnEvent", TotemTimers.FireTotemEvent)
            cd.events[2] = "PLAYER_TOTEM_UPDATE"
        else
            cd.button:SetScript("OnEvent", TotemTimers.EnhanceCDEvents)
        end
    end
    ]==]

    if AvailableSpells[SpellIDs.FlameShock] and TotemTimers.ActiveProfile.EnhanceCDsFlameShockDuration_Specialization[role] then
        FlameShockDuration:Activate()
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

    --[==[
    for i=1,#CDSpells[role] do
        if TotemTimers.ActiveProfile.EnhanceCDs_Spells[role][i] and AvailableSpells[cds[i].button.cdspell] then
            cds[i]:Activate()
        end
    end
    ]==]

end

--[==[
local activeCDs = {}

local function ConvertCoords(frame1, frame2)
    return frame1:GetEffectiveScale()/frame2:GetEffectiveScale()
end
]==]


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

--local x = 0
function TotemTimers.LayoutEnhanceCDs()
    --wipe(activeCDs)
    if role == 0 then return end

    --[==[
    for i=1,#CDSpells[role] do
        if cds[TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i]].active then
            table.insert(activeCDs,cds[TotemTimers.ActiveProfile.EnhanceCDs_Order[role][i]])
        end
    end
    for i=1,12 do
        cds[i]:ClearAnchors()
        cds[i].button:ClearAllPoints()
    end
    ]==]
    FlameShockDuration.button:ClearAllPoints()
    --[==[
    if Maelstrom then Maelstrom.button:ClearAllPoints() end

    local numActiveCDs = #activeCDs

    if numActiveCDs == 0 then return end

    local topRow, bottomRow = numActiveCDs, 0

    if numActiveCDs > 5 and not TotemTimers.ActiveProfile.EnhanceCDsOneRow then
        topRow = floor(numActiveCDs / 2)
        bottomRow = ceil(numActiveCDs / 2)
    end

    local split = ceil(topRow / 2)
    if topRow % 2 == 0 then
        activeCDs[split]:SetPoint("RIGHT", TotemTimers_EnhanceCDsFrame, "CENTER", -3, 0)
    else
        activeCDs[split]:SetPoint("CENTER", TotemTimers_EnhanceCDsFrame)
    end

    for i=split-1, 1, -1 do
        activeCDs[i]:Anchor(activeCDs[i+1], "RIGHT")
    end
    for i = split + 1, topRow do
        activeCDs[i]:Anchor(activeCDs[i-1], "LEFT")
    end

    local bottomSplit
    if bottomRow > 0 then
        bottomSplit = topRow + ceil(bottomRow / 2)
        if bottomRow == topRow then
            activeCDs[bottomSplit]:Anchor(activeCDs[split], "TOP")
        else
            if topRow %2 == 0 then
                activeCDs[bottomSplit]:Anchor(activeCDs[split], "TOPLEFT", "BOTTOM", true)
            else
                activeCDs[bottomSplit]:Anchor(activeCDs[split], "TOPRIGHT", "BOTTOM", true)
            end
        end
        for i=bottomSplit-1, topRow+1, -1 do
            activeCDs[i]:Anchor(activeCDs[i+1], "RIGHT")
        end
        for i = bottomSplit + 1, numActiveCDs do
            activeCDs[i]:Anchor(activeCDs[i-1], "LEFT")
        end
    end

    local spacing = TotemTimers.ActiveProfile.CooldownSpacing
    ]==]

    local width, height = SizeToWidthHeight(FlameShockDuration.size)

    FlameShockDuration:SetTimeWidth(width)
    FlameShockDuration:SetTimeHeight(height)
    FlameShockDuration.button:SetSize(height, height)
    FlameShockDuration.button.icons[1]:SetAllPoints(FlameShockDuration.button)

    --[==[
    local fspoint, fsy = "BOTTOMLEFT", 0

    if TotemTimers.ActiveProfile.FlameShockDurationOnTop then
        fsy = 18 + spacing + activeCDs[1]:GetBorder("TOP")
    else
        fspoint = "TOPLEFT"
        local border = spacing + activeCDs[1]:GetBorder("BOTTOM")
        fsy = -18 - border
        if bottomRow > 0 then
            fsy = fsy - 36 - border
        end
    end

    FlameShockDuration.button:SetPoint(fspoint, TotemTimers_EnhanceCDsFrame, "CENTER", -width / 2, fsy)
    ]==]
    -- without the cooldown buttons the Flame Shock timer and the Maelstrom tracker (each button + bar) are centered
    -- on the anchor frame, with both active the Maelstrom tracker on top
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
    -- (2:1 like the mw textures) on its top edge); MaelstromIconSize scales it there too
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
        MaelstromIcon:SetPoint("BOTTOM", UIParent, "CENTER", 0, OVERLAY_LONG_SIDE / 2)
    elseif not iconOnly then
        MaelstromIcon:SetPoint("BOTTOM", Maelstrom.timerBars[1], "TOP", 0, -iconWidth / 2 * 0.15)
    end

    if iconOnly then
        -- the icon alone in the place of the bar: above the Flame Shock timer, otherwise centered on the anchor
        if FlameShockDuration.active then
            local halfSpacing = TotemTimers.ActiveProfile.CooldownSpacing / 2
            MaelstromIcon:SetPoint("BOTTOM", TotemTimers_EnhanceCDsFrame, "CENTER", 0, halfSpacing)
            FlameShockDuration.button:SetPoint("TOPLEFT", TotemTimers_EnhanceCDsFrame, "CENTER", -width / 2, -halfSpacing)
        else
            MaelstromIcon:SetPoint("CENTER", TotemTimers_EnhanceCDsFrame, "CENTER")
            FlameShockDuration.button:SetPoint("LEFT", TotemTimers_EnhanceCDsFrame, "CENTER", -width / 2, 0)
        end
        -- the inactive button keeps a position (its bar isn't shown)
        Maelstrom.button:SetPoint("LEFT", TotemTimers_EnhanceCDsFrame, "CENTER", -msWidth / 2, 0)
    elseif FlameShockDuration.active and Maelstrom.active then
        local halfSpacing = TotemTimers.ActiveProfile.CooldownSpacing / 2
        Maelstrom.button:SetPoint("BOTTOMLEFT", TotemTimers_EnhanceCDsFrame, "CENTER", -msWidth / 2, halfSpacing)
        FlameShockDuration.button:SetPoint("TOPLEFT", TotemTimers_EnhanceCDsFrame, "CENTER", -width / 2, -halfSpacing)
    else
        Maelstrom.button:SetPoint("LEFT", TotemTimers_EnhanceCDsFrame, "CENTER", -msWidth / 2, 0)
        FlameShockDuration.button:SetPoint("LEFT", TotemTimers_EnhanceCDsFrame, "CENTER", -width / 2, 0)
    end

    --[==[
    local cprocy = 18 + spacing + activeCDs[1]:GetBorder("TOP")

    if FlameShockDuration.active and TotemTimers.ActiveProfile.FlameShockDurationOnTop then
        cprocy = cprocy + spacing + height
    end

    CenterProcAnchor:ClearAllPoints()
    CenterProcAnchor:SetPoint("CENTER", TotemTimers_EnhanceCDsFrame, "CENTER", 0, cprocy + 12)

    LeftProcAnchor:ClearAllPoints()
    RightProcAnchor:ClearAllPoints()
    if bottomRow == 0 then
        LeftProcAnchor:SetPoint("RIGHT", activeCDs[1].button, "LEFT", LeftProcAnchor:GetWidth() / 3 * LeftProcAnchor:GetScale(), 0)
        RightProcAnchor:SetPoint("LEFT", activeCDs[numActiveCDs].button, "RIGHT", -RightProcAnchor:GetWidth() / 3 * RightProcAnchor:GetScale(), 0)
    end

    if Maelstrom then
        local msWidth, msHeight = SizeToWidthHeight(Maelstrom.size)
        Maelstrom:SetTimeWidth(msWidth)
        Maelstrom:SetTimeHeight(msHeight)
        Maelstrom.button:SetSize(msHeight, msHeight)
        Maelstrom.button.icons[1]:SetAllPoints(Maelstrom.button)
        MaelstromButton:SetSize(msWidth, msHeight)
        MaelstromIcon:SetSize(msWidth * 0.75, msWidth * 0.75 / 2)

        local msy = 18 + spacing + activeCDs[1]:GetBorder("TOP")

        if FlameShockDuration.active and TotemTimers.ActiveProfile.FlameShockDurationOnTop then
            msy = msy + spacing + height
        end

        Maelstrom.button:SetPoint("BOTTOMLEFT", TotemTimers_EnhanceCDsFrame, "CENTER", -msWidth / 2, msy)
        MaelstromIcon:SetPoint("CENTER", TotemTimers_EnhanceCDsFrame, "CENTER", 0, msy + 12)

    end
    ]==]
end

function TotemTimers.ActivateEnhanceCDs()
    TotemTimers.ConfigEnhanceCDs()
    TotemTimers.LayoutEnhanceCDs()
end

function TotemTimers.DeactivateEnhanceCDs()
    --[==[
    for k,v in pairs(cds) do
        v:Deactivate()
    end
    ]==]
    FlameShockDuration:Deactivate()
    Maelstrom:Deactivate()
    maelstromEnabled = false
    TotemTimers.UpdateMaelstromIcon()
    UpdateGamePadButtons()
end

--[==[
function TotemTimers.EnhanceCDEvents(self, event, spell)
    local settings = TotemTimers.ActiveProfile

    if event == "SPELL_UPDATE_COOLDOWN" then
        local cdspell = self.cdspell
        cdspell = SpellNames[cdspell]
        -- the cooldown can be secret: only the never secret isActive and isOnGCD flags are read,
        -- timer and swirl are driven by DurationObjects
        local info = C_Spell.GetSpellCooldown(cdspell)
        if not info or not info.isActive then
            self.timer:Stop(1)
        else
            if info.isOnGCD then
                self.timer:Stop(1)
            else
                self.timer:Start(1, C_Spell.GetSpellCooldownDuration(cdspell, true))
            end
            local durObj = C_Spell.GetSpellCooldownDuration(cdspell)
            if durObj then self.cooldown:SetCooldownFromDurationObject(durObj) end
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        if spell == self.glowSpell then
            self.timer:ShowOverlayGlow()
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if spell == self.glowSpell then
            self.timer:HideOverlayGlow()
        end
    end
end


function TotemTimers.FireTotemEvent(self,event,...)
    local element = ...
    if event == "PLAYER_TOTEM_UPDATE" then
        if element == 1 then
            local _, totem, startTime, duration, icon = GetTotemInfo(1)
            if icon == self.icon:GetTexture() and duration > 0 then
				self.icon:SetTexture(icon)
                self.timer:Start(1, duration)
            elseif self.timer.timers[1] > 0 then
                self.timer:Stop(1)
            end
        end
    else
        -- TotemTimers.EnhanceCDEvents(self,event,...)
    end
end


function TotemTimers.ShieldChargeEvent(self, event, ...)
	if event == "UNIT_AURA" and select(1,...) =="player" then
		local name,_,texture,count,_,duration,endtime = UnitAura("player", ShieldName)
		if name then
			if role == 1 then
				self.timer:Start(1, count, 15)
			else
				self.timer:Start(1, endtime-GetTime(), duration)
			end
		elseif self.timer.timers[1]>0 then
			self.timer:Stop(1)
		end
	elseif event ~= "SPELL_UPDATE_COOLDOWN" then
        TotemTimers.EnhanceCDEvents(self,event,...)
    end
end
]==]


--[==[
local StormStrike = SpellNames[SpellIDs.StormStrike]

function TotemTimers.StormStrikeEvent(self, event, unit, ...)
    if (event == "UNIT_AURA" and unit == "target") or event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") then
            for i = 1,40 do
                local name,_,_,_,duration,endtime = UnitDebuff("target", i)
                if name then
                    if name == StormStrike then
                        local timeleft = endtime - GetTime()
                        self.timer:StartBarTimer(timeleft, duration)
                        return
                     end
                else
                    break
                end
            end
        end
        if self.timer.barTimer>0 then
            self.timer:StopBarTimer()
        end
    else
        TotemTimers.EnhanceCDEvents(self, event, unit, ...)
    end
end


local Focused = 43339
local ElementalFocus = 16164
local ClearCasting = 16246
local ShockBuffActive = {}
function TotemTimers.ShockEvent(self, event, unit, ...)
    if event == "UNIT_AURA" and unit == "player" then
        for i = 1,40 do
            local name,_,_,_,duration,endtime,_,_,_,spellID = UnitBuff("player", i)
            if spellID then
                if (spellID == Focused or spellID == ElementalFocus or spellID == ClearCasting) then
                    if not ShockBuffActive[self.timer.nr] then
                        ShockBuffActive[self.timer.nr] = true
                        self.timer:ShowOverlayGlow()
                    end
                    return
                 end
            else
                break
            end
        end
        if ShockBuffActive[self.timer.nr] then
            ShockBuffActive[self.timer.nr] = false
            self.timer:HideOverlayGlow()
        end
    else
        TotemTimers.EnhanceCDEvents(self, event, unit, ...)
    end
end


local actionToButton = {}
if _G["ActionButton_Update"] then
    hooksecurefunc("ActionButton_Update", function(self)
        if self.action then actionToButton[self.action] = self end
    end)
end

--[[local multiBarButtonNames = {
    [3] = "MultiBarRightButton",
    [4] = "MultiBarLeftButton",
    [5] = "MultiBarBottomRightButton",
    [6] = "MultiBarBottomLeftButton",
}]]

local function slotToButton(slot)
    if _G["BT4Button"..slot] then
        return _G["BT4Button"..slot]
    end
    if ElvUI then
        return _G["ElvUI_Bar"..ceil(slot/12).."Button"..((slot - 1) % 12 + 1)]
    end
    return actionToButton[slot]
    --[[if slot < 25 then
        if floor(slot/12) == GetActionBarPage() - 1 then
            return _G["ActionButton"..(slot % 12)]
        end
    elseif slot < 73 then
        return _G[multiBarButtonNames[ceil(slot/12)]..(slot % 12)]
    end]]
end


local function FindActionButtons(spellList)
    local buttons = {}
    for i = 1,#spellList do
        local spell = spellList[i]
        if AvailableSpells[spell] then
            local spellName = SpellNames[spell]
            local spellID = C_Spell.GetSpellIDForSpellIdentifier(spell)

            local slots = C_ActionBar.FindSpellActionButtons(spellID);
            if slots then
                for slot = 1,#slots do
                    local button = slotToButton(slots[slot])
                    if button then
                        table.insert(buttons, button)
                    end
                end
            end
            for cd = 1,#cds do
                if cds[cd].button.cdspell == spell then
                    table.insert(buttons, cds[cd].button)
                end
            end
        end
    end
    return buttons
end
TotemTimers.FindActionButtons = FindActionButtons

local ShowOverlayGlow
local HideOverlayGlow

if ActionButton_ShowOverlayGlow then
    ShowOverlayGlow = ActionButton_ShowOverlayGlow
    HideOverlayGlow = ActionButton_HideOverlayGlow
elseif ActionButtonSpellAlertManager then
    ShowOverlayGlow = function(button)
        ActionButtonSpellAlertManager:ShowAlert(button)
    end
    HideOverlayGlow = function(button)
        ActionButtonSpellAlertManager:HideAlert(button)
    end
end


local function ShowButtonsOverlayGlow(buttonList)
    for b = 1, #buttonList do
        ShowOverlayGlow(buttonList[b])
    end
end
TotemTimers.ShowButtonsOverlayGlow = ShowButtonsOverlayGlow

local function HideButtonsOverlayGlow(buttonList)
    for b = 1, #buttonList do
        HideOverlayGlow(buttonList[b])
    end
end
TotemTimers.HideButtonsOverlayGlow = HideButtonsOverlayGlow

local maelstromSpells = TotemTimers.MaelstromSpells
local maelstromSpellsButtons = nil

local MaelstromName = C_Spell.GetSpellName(SpellIDs.Maelstrom)
local lastMaelstromCount = 0

function TotemTimers.MaelstromEvent(self)
    local _,_,count = AuraUtil.FindAuraByName(MaelstromName, "player", "HELPFUL")
    local numberOnly = Maelstrom.NumberOnly

    if (not count or count < 5) and maelstromSpellsButtons and #maelstromSpellsButtons > 0 then
        HideButtonsOverlayGlow(maelstromSpellsButtons)
        maelstromSpellsButtons = nil
        HideOverlayGlow(TotemTimers.MaelstromButton)
    end

    if not count then
        Maelstrom:Stop(1)
        Maelstrom.timerBars[1].time:SetText("")
        Maelstrom.timerBars[1].time.AnimGroup:Stop()

        if not numberOnly then
            MaelstromIcon:Hide()
            MaelstromIcon.icon:SetTexture(nil)
            MaelstromIcon.icon.AnimGroup:Stop()
        end
    else
        Maelstrom.timerBars[1].time:SetText(count)
        Maelstrom:Start(1, count, 5)
        --Maelstrom:SetBarColor(.6 + count * .04, .6 + count * .04, .8 + count * .04)
        Maelstrom:SetBarColor(0, RAID_CLASS_COLORS.SHAMAN.g * 0.8 + count * .04, RAID_CLASS_COLORS.SHAMAN.b * 0.8 + count * .04)

        local animate
        if numberOnly then
            MaelstromIcon:Hide()
            MaelstromIcon.icon.AnimGroup:Stop()
            animate = Maelstrom.timerBars[1].time
        else
            MaelstromIcon:Show()
            MaelstromIcon.icon:SetTexture("Interface/AddOns/TotemTimers/textures/mw"..count) -- ..(count < 5 and "_"..count or ""))
            animate = MaelstromIcon.icon
            HideOverlayGlow(TotemTimers.MaelstromButton)
        end


        if count ~= 5 and count ~= 10 then
            animate.AnimGroup:Stop()
        else
            animate.AnimGroup:Play()

            if lastMaelstromCount < count then
                XiTimers.PlayWarning(self, "Maelstrom")
                if Maelstrom.StopPulseOn5 then
                    Maelstrom.animation.icon:SetTexture("Interface/AddOns/TotemTimers/textures/mw"..count)
                    Maelstrom.animation:Play()
                end
                if TotemTimers.ActiveProfile.OverlayGlow then
                    maelstromSpellsButtons = FindActionButtons(maelstromSpells)
                    ShowButtonsOverlayGlow(maelstromSpellsButtons)
                end
            end

            if numberOnly then
                ShowOverlayGlow(TotemTimers.MaelstromButton)
            end
        end

        lastMaelstromCount = count
    end
end



function gmb()
    maelstromSpellsButtons = FindActionButtons(TotemTimers.MaelstromSpells)
end

function smb()
    for b = 1, #maelstromSpellsButtons do
        ShowOverlayGlow(maelstromSpellsButtons[b])
    end
end

function hmb()
    for b = 1, #maelstromSpellsButtons do
        HideOverlayGlow(maelstromSpellsButtons[b])
    end
end
]==]
