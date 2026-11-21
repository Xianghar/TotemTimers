if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...




local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers", true)

local RaidMembers = {}

local RAID_CLASS_COLORS = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS

local BuffNames = TotemTimers.BuffNames
local SpellNames = TotemTimers.SpellNames
local TextureToName = TotemTimers.TextureToName
local NameToSpellID = TotemTimers.NameToSpellID
local TextureToSpellID = TotemTimers.TextureToSpellID
local SpellIDs = TotemTimers.SpellIDs
local AvailableSpells = TotemTimers.AvailableSpells
local SpellTextures = TotemTimers.SpellTextures
local AvailableTalents = TotemTimers.AvailableTalents

local Cooldowns = TotemTimers.TotemCooldowns

-- Range dots: the buff of the active totem can be secret, so aura containers in dot mode (see AuraDisplay.lua)
-- show a dot while a party member has it; while the player has it the icon is tinted green or a green dot is
-- shown (option PlayerRangeStyle). The addon never reads the buff. Each display has one slot per totem of the
-- element with a buff, only the slot of the active totem is enabled.
-- A timer can have several sets of dots (timer.rangeDotSets): on its button and on Gamepad UI bar slots.
-- r, g, b, alpha; added to the icon's colors (additive blending), the alpha scales the color
local PlayerTintColor = { 0, 1, 0, 0.3 }
local PlayerDotColor = { 0.1, 0.85, 0.1 }
-- keys of the dots of a set and their units ("player": the tint, "playerDot": the player's dot)
local RangeDotKeys = { "player", "playerDot", "party1", "party2", "party3", "party4" }
local RangeDotUnits = { playerDot = "player" }

local UpdateRangeDots

-- adds a set of range dots to the timer
-- dots: by key (see RangeDotKeys): for "playerDot" and the party the dot textures, they stay hidden and are
--   anchor, size and image of the dots; for "player" the icon region that is tinted green
-- isShown: optional function, the set is only shown while it returns true
-- playerMask: optional { atlas, inset }, mask of the player's tint (round icons)
function TotemTimers.AddRangeDots(timer, parent, dots, isShown, playerMask)
    local set = { displays = {}, isShown = isShown }
    for _, key in ipairs(RangeDotKeys) do
        local unit = RangeDotUnits[key] or key
        local options = { dot = dots[key] }
        if key == "player" then
            options.tint = true
            options.maskAtlas = playerMask and playerMask[1]
            options.maskInset = playerMask and playerMask[2]
        end
        local display = dots[key] and TotemTimers.AuraDisplay:new(parent, unit, options)
        if display then
            for totem, data in pairs(TotemData) do
                if data.element == timer.nr and data.buff then
                    local spellIDs = {}
                    for _, id in ipairs(TotemTimers.TotemBuffAuraSpells[data.buff] or { data.buff }) do
                        spellIDs[id] = true
                    end
                    local key = tostring(totem)
                    display:AddSlot(key, spellIDs, 11, "HELPFUL")
                    display:SetSlotEnabled(key, false)
                end
            end
            if key == "player" then
                display:SetDotColor(unpack(PlayerTintColor))
            elseif key == "playerDot" then
                display:SetDotColor(unpack(PlayerDotColor))
            else
                local color = RAID_CLASS_COLORS[select(2, UnitClass(unit)) or ""]
                if color then display:SetDotColor(color.r, color.g, color.b) end
            end
            set.displays[key] = display
        end
    end
    timer.rangeDotSets = timer.rangeDotSets or {}
    table.insert(timer.rangeDotSets, set)
    UpdateRangeDots(timer)
    return set
end

-- enables the slot of the active totem in the displays of the units the options allow
UpdateRangeDots = function(timer)
    local profile = TotemTimers.ActiveProfile
    if not timer.rangeDotSets or not profile then return end
    local totem = timer.timers[1] and timer.activeTotem
    local activeKey = profile and totem and TotemData[totem] and TotemData[totem].buff and tostring(totem)
    local playerDot = profile and profile.PlayerRangeStyle == "dot"
    for _, set in ipairs(timer.rangeDotSets) do
        local setShown = activeKey and (not set.isShown or set.isShown())
        for key, display in pairs(set.displays) do
            local allowed
            if key == "player" then
                allowed = profile.CheckPlayerRange and not playerDot
            elseif key == "playerDot" then
                allowed = profile.CheckPlayerRange and playerDot
            else
                allowed = profile.CheckRaidRange
            end
            allowed = setShown and allowed
            for _, slot in ipairs(display.slots) do
                display:SetSlotEnabled(slot.key, allowed and slot.key == activeKey or false)
            end
        end
    end
end

function TotemTimers.UpdateRangeDots()
    for e = 1, 4 do
        if XiTimers.timers[e] then UpdateRangeDots(XiTimers.timers[e]) end
    end
end


-- sawtooth curves for the pulse bar of totems with flashInterval, evaluated on the elapsed time of the totem:
-- full bar until flashDelay, then falling from 1 to 0 over flashInterval seconds and refilling at each pulse
local FlashCurveLength = 300

function TotemTimers.CreateFlashCurves()
    for _, data in pairs(TotemData) do
        local interval = data.flashInterval
        if interval then
            local delay = data.flashDelay or 0
            local curve = C_CurveUtil.CreateCurve()
            curve:SetType(Enum.LuaCurveType.Linear)
            curve:AddPoint(0, 1)
            if delay > 0 then curve:AddPoint(delay, 1) end
            local pulse = delay + interval
            while pulse < FlashCurveLength do
                curve:AddPoint(pulse, 0)
                curve:AddPoint(pulse + 0.001, 1)
                pulse = pulse + interval
            end
            curve:AddPoint(FlashCurveLength, 1 - (FlashCurveLength - pulse + interval) / interval)
            data.flashCurve = curve
        end
    end
end

TotemTimers.CreateFlashCurves()


-- Call of the Elements/Ancestors/Spirits (multicast totem bar) exist in Wrath, Cata and WoW Forever
TotemTimers.HasMultiCast = TotemTimers.IsForever

-- multicast action slots: 4 per page (MultiCastActionButton1-12), starting after the 132 regular action slots
local MULTICAST_ACTION_OFFSET = 132

local MultiCastActions = {}
TotemTimers.MultiCastActions = MultiCastActions
if TotemTimers.HasMultiCast then
    -- by totem slot, the action slots of a page are in totem slot order
    for slot = 1, 4 do
        MultiCastActions[slot] =
        { [SpellIDs.CallOfElements] = MULTICAST_ACTION_OFFSET + slot,
          [SpellIDs.CallOfAncestors] = MULTICAST_ACTION_OFFSET + slot + 4,
          [SpellIDs.CallOfSpirits] = MULTICAST_ACTION_OFFSET + slot + 8 }
    end
end



local EXCLUDED_RED = { 0.70, 0.05, 0.04 }
local EXCLUDED_GREEN = { 0.10, 0.65, 0.10 }

-- color of the sign on the exclusion toggles (menu button, gamepad wheel): red while included, green while excluded
function TotemTimers.GetExcludeToggleColor(excluded)
    return unpack(excluded and EXCLUDED_GREEN or EXCLUDED_RED)
end

-- icon marking a totem timer excluded from the active multicast spell (Ctrl-Rightclick on the timer button):
-- a red prohibition sign (textures/excluded, a white sign generated by tools/excluded_texture.py, tinted here); on
-- the timer buttons and on the Gamepad UI bar slots, in their lower left corner
function TotemTimers.CreateExcludedIcon(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    frame.sign = frame:CreateTexture(nil, "OVERLAY")
    frame.sign:SetTexture("Interface\\AddOns\\TotemTimers\\textures\\excluded")
    frame.sign:SetAllPoints(frame)
    frame.sign:SetVertexColor(unpack(EXCLUDED_RED))
    frame:Hide()
    return frame
end

-- the multicast spell the timer's element is excluded from (the active one of the multicast button), nil if none
function TotemTimers.GetExcludedMultiSpell(timer)
    local mspell = timer.button:GetAttribute("mspell")
    if mspell and timer.button:GetAttribute("mspelldisabled" .. mspell) then
        return mspell
    end
end

function TotemTimers.SetExcludedIcon(frame, mspell)
    frame:SetShown(mspell and true or false)
end

 function TotemTimers.SetupTimers()
    for e = 1, 4 do
        local tt = XiTimers:new(#Cooldowns[e] + 1)

        tt.manaCheckMini = true
        tt.button:SetScript("OnEvent", TotemTimers.TotemEvent)
        tt.spacing = TotemTimers.ActiveProfile.timerSpacing
        tt.events[1] = "PLAYER_TOTEM_UPDATE"
        tt.events[2] = "SPELL_UPDATE_COOLDOWN"
        tt.events[3] = "PLAYER_ENTERING_WORLD"
        --tt.events[4] = "UNIT_AURA"
        tt.events[5] = "PLAYER_REGEN_ENABLED"
        tt.playerEvents[1] = "UNIT_SPELLCAST_SUCCEEDED"

        tt.button.anchorframe = TotemTimersFrame
        tt.button:RegisterForClicks("AnyDown")
        --tt.button:SetAttribute("*type2", "macro")
        tt.button:SetAttribute("*type3", "macro")
        tt.button:SetAttribute("*type1", "spell")
        tt.button.bar:SetStatusBarColor(0.7, 1, 0.7, 0.8)
        tt.button.UpdateMiniIconAndProfile = function(self)
            local spell = self:GetAttribute("*spell1")
            if spell and spell ~= 0 then
                local texture = C_Spell.GetSpellTexture(self:GetAttribute("*spell1"))
                local oldTexture = self.miniIcon:GetTexture()
                self.miniIcon:SetTexture(texture)
                if (not self.timer.timers[1] and texture ~= oldTexture) then
                    self.icons[1]:SetTexture(texture)
                end
                TotemTimers.TotemEvent(self, "SPELL_UPDATE_COOLDOWN", self.timer.nr)
                self.timer:SetManaCheck(spell)
                TotemTimers.ActiveProfile.LastTotems[self.timer.nr] = spell
                self:SyncMultiCastSlot(spell)
            end
            TotemTimers.UpdateMacro()
        end

        tt.button.tooltip = TotemTimers.Tooltips.Totem:new(tt.button)

        tt.button:SetAttribute("_onattributechanged", [[ if name == "*spell1" then 
                                                            control:CallMethod("UpdateMiniIconAndProfile")
															local mspell = self:GetAttribute("mspell")															
															if mspell then 
																local mspellDisabled = self:GetAttribute("mspelldisabled"..mspell)
																if not mspellDisabled then
																	self:SetAttribute("mspell"..mspell, self:GetAttribute("*spell1"))
																end
															end
                                                         elseif name == "mspell" then
															local mspell = self:GetAttribute("mspell")
															if mspell then															
																self:ChildUpdate("mspell", self:GetAttribute("action"..mspell))
																self:ChildUpdate("mspelldisabled", self:GetAttribute("mspelldisabled"..mspell))	
																local spell = self:GetAttribute("mspell"..mspell)
																if spell then self:SetAttribute("*spell1", spell) end
															else
																self:ChildUpdate("mspell", nil)
															end
															control:CallMethod("UpdateMultiSpellExcluded")
														 elseif name:sub(1,14) == "mspelldisabled" then
															local mspell = tonumber(name:sub(15))
															local disabled = self:GetAttribute(name)
															local activeMspell = self:GetAttribute("mspell")
															if mspell == activeMspell then
																self:ChildUpdate("mspelldisabled", disabled)
																control:CallMethod("UpdateMultiSpellExcluded")
															end
                                                         elseif name == "state-invehicle" then
                                                            if value == "show" and self:GetAttribute("active") then
                                                                self:Show()
                                                                local s = self:GetAttribute("*spell1")
                                                                if s then self:SetAttribute("*spell1", s) end
                                                            else
                                                                self:Hide()
                                                            end
                                                         end]])
        tt.button:WrapScript(tt.button, "OnClick", [[ if button == "Button4" then
                                                          control:ChildUpdate("toggle")
													  elseif button == "RightButton" and IsControlKeyDown() and not PlayerInCombat() then
													      local mspell = self:GetAttribute("mspell")
														  if mspell then
															  local disabled = not self:GetAttribute("mspelldisabled"..mspell)
													          self:SetAttribute("mspelldisabled"..mspell, disabled)
													          self:CallMethod("DisableMultiSpell", mspell, disabled)
														  end
                                                      end ]])
		
        -- lower left corner: marks the element as excluded from the active multicast spell
        tt.button.excludedIcon = TotemTimers.CreateExcludedIcon(tt.button)
        tt.button.excludedIcon:SetSize(14, 14)
        tt.button.excludedIcon:SetPoint("BOTTOMLEFT", tt.button, "BOTTOMLEFT", 1, -2)
        -- below the frame of the time on the button (button level + 11, XiTimers:new), above the cooldown swipe
        tt.button.excludedIcon:SetFrameLevel(tt.button:GetFrameLevel() + 10)
        tt.button.UpdateMultiSpellExcluded = function(self)
            local excluded = TotemTimers.GetExcludedMultiSpell(self.timer)
            TotemTimers.SetExcludedIcon(self.excludedIcon, excluded)
            -- the toggle at the end of the totem menu (SetupExcludeToggle): the active multicast spell's icon
            local toggle = self.excludeToggle
            if toggle then
                local mspell = self:GetAttribute("mspell")
                if mspell then
                    toggle.icon:SetTexture((C_Spell.GetSpellTexture(mspell)))
                end
                -- always shown on the toggle: red while included, green while excluded
                toggle.excludedSign.sign:SetVertexColor(TotemTimers.GetExcludeToggleColor(excluded))
            end
        end

		--declare empty function here for classic and tbc
		tt.button.DisableMultiSpell = function(self, multispell, disable) end
        tt.button.SyncMultiCastSlot = function(self, spell) end

        tt.Activate = function(self)
            if self.active then return end
            local activeProfile = TotemTimers.ActiveProfile

            XiTimers.Activate(self)

            TotemTimers.TotemEvent(self.button, "PLAYER_TOTEM_UPDATE", self.nr)
            TotemTimers.TotemEvent(self.button, "SPELL_UPDATE_COOLDOWN", self.nr)

            if activeProfile.CheckRaidRange then
                self.button:RegisterEvent("GROUP_ROSTER_UPDATE")
            end
            UpdateRangeDots(self)

            -- totem of the button (saved, from the multicast slot, or the first of the menu when the element was
            -- just learned) and the element's empty multicast slots
            if not self.timers[1] then
                TotemTimers.UpdateTimerTotem(self)
            end
        end

        tt.XiTimersStart = XiTimers.Start
        tt.Start = function(self, timer, ...)
            self.XiTimersStart(self, timer, ...)
            if timer == 1 then
                self.button.playerRange:Hide()
                for i = 1,4 do self.button.partyRange[i]:Hide() end
            end
        end

        tt.XiTimersStop = XiTimers.Stop
        tt.Stop = function(self, timer, ...)
            self.XiTimersStop(self, timer, ...)
            if timer == 1 then
                self.button.playerRange:Hide()
                for i = 1,4 do self.button.partyRange[i]:Hide() end
                UpdateRangeDots(self)
            end
        end

        --[[ tt.Update = function(self, elapsed)
            XiTimers.Update(self, elapsed)
            if self.timers[1] then
                self:SetOutOfRange(not TotemTimers.GetPlayerRange(self.button.element))
                local count = TotemTimers.GetOutOfRange(self.button.element)
                if count > 0 then
                    self.button.rangeCount:SetText(count)
                else
                    self.button.rangeCount:SetText("")
                end
            end
        end ]]

        --tt.button:UpdateMiniIconAndProfile()
        tt.button:SetScript("OnDragStop", function(self)
            XiTimers.StopMoving(self)
            if not InCombatLockdown() then
                TotemTimers.PositionCastButtons()
            end
            --[[]if not InCombatLockdown() then
                self:SetAttribute("hide", true)
            end]]
        end)

        if TotemTimers.IsForever then

			tt.button.DisableMultiSpell = function(self, multispell, disable)
                if not multispell or InCombatLockdown() then return end
                local action = self:GetAttribute("action"..multispell)
                SetMultiCastSpell(action, not disable and self:GetAttribute("*spell1") or nil)
                TotemTimers.ActiveProfile.DisabledMultiSpells[TotemTimers.Specialization..multispell..self.timer.nr] = disable
                TotemTimers_MultiSpell:UpdateTexture()
            end

            -- puts the timer's totem into the multicast slot of the active multicast spell (unless disabled for the
            -- timer), whatever changed the totem (totem sets, gamepad, ...); out of combat only, in combat only the
            -- secure "multispell" action of the menu buttons (rightclick, gamepad wheel assign) can do it
            -- not while the totems are loaded (TotemTimers.UpdateTimerTotem writes only empty slots) and not for
            -- another rank of the same totem (rank updates of the button aren't a change of the totem)
            tt.button.SyncMultiCastSlot = function(self, spell)
                if TotemTimers.LoadingTotems or InCombatLockdown()
                        or not (TotemTimers_MultiSpell and TotemTimers_MultiSpell.active) then return end
                local mspell = self:GetAttribute("mspell")
                if not mspell or self:GetAttribute("mspelldisabled" .. mspell) then return end
                local action = self:GetAttribute("action" .. mspell)
                if not action then return end
                local _, current = GetActionInfo(action)
                if not current or C_Spell.GetSpellName(current) ~= C_Spell.GetSpellName(spell) then
                    SetMultiCastSpell(action, spell)
                end
            end
        end


        local frame = CreateFrame("Frame", nil, tt.button)
        frame:Show()
        frame:SetAllPoints(tt.button)
        frame:SetFrameLevel(frame:GetFrameLevel() + 10)

        local playerRange = frame:CreateTexture(nil, "OVERLAY", nil, 7);
        tt.button.playerRange = playerRange;
        --create player and party range dots
        playerRange:SetTexture("Interface\\AddOns\\TotemTimers\\textures\\dot");
        playerRange:SetSize(7, 7)
        playerRange:SetPoint("TOPLEFT", tt.button, "TOPLEFT", 1, -1);
        playerRange:SetVertexColor(0.68,0.1,0.12)
        playerRange:Hide()

        tt.button.partyRange = {}

        for i = 1, 4 do
            local partyRange = tt.button:CreateTexture(nil, "OVERLAY")
            partyRange:SetTexture("Interface\\AddOns\\TotemTimers\\textures\\dot");
            partyRange:SetSize(7, 7)
            if i == 1 then
                partyRange:SetPoint("TOPRIGHT", tt.button, "TOPLEFT", 0, 0);
            else
                partyRange:SetPoint("TOP", tt.button.partyRange[i - 1], "BOTTOM", 0, -1);
            end
            partyRange:Hide()
            table.insert(tt.button.partyRange, partyRange)
        end

        local dots = { player = tt.button.icons[1], playerDot = tt.button.playerRange }
        for i = 1, 4 do dots["party" .. i] = tt.button.partyRange[i] end
        TotemTimers.AddRangeDots(tt, tt.button, dots)
    end

    XiTimers.timers[1].button:SetAttribute("*type5", "macro")
    XiTimers.timers[1].button:SetAttribute("macrotext5",
            "/click XiTimers_Timer1 close\n"
                    .. "/click XiTimers_Timer2 close\n"
                    .. "/click XiTimers_Timer3 close\n"
                    .. "/click X iTimers_Timer4 close\n"
                    .. "/click XiTimers_Timer8 close\n"
    )
    TotemTimers.CreateCastButtons()
end

table.insert(TotemTimers.Modules, TotemTimers.SetupTimers)

local TotemicRecall = TotemTimers.SpellIDs.TotemicRecall


-- a totem cast is only accepted as the source of a following PLAYER_TOTEM_UPDATE for this long
local PENDING_TOTEM_TIMEOUT = 1

-- GetTotemInfo returns secret values in combat, so there the active totem is taken from the
-- player's last totem cast (UNIT_SPELLCAST_SUCCEEDED spell IDs of the player are not secret)
local function GetActiveTotem(timer, slot)
    local _, totemName, _, _, icon, _, spellID = GetTotemInfo(slot)
    local pending = timer.pendingTotem
    timer.pendingTotem = nil

    if not issecretvalue(totemName) then
        if not totemName or totemName == "" then
            return false
        end
        local totem = spellID and TotemTimers.GetBaseSpellID(spellID)
        if not totem or not TotemData[totem] then
            totem = TextureToSpellID[icon]
        end
        if not totem then
            totem = NameToSpellID[string.gsub(totemName, "%s?[IV]*$", "")] -- strip spell rank from name
        end
        return true, totem, icon
    end

    if pending and GetTime() - timer.pendingTotemTime <= PENDING_TOTEM_TIMEOUT then
        return true, pending, icon
    end
    -- no own cast preceded the update: the totem was destroyed or recalled
    return false
end

local function StartTotem(button, totem, icon)
    local timer = button.timer
    local duration = GetTotemDuration(button.element)
    if not duration then
        return false
    end
    timer:Start(1, duration)
    timer.activeTotem = totem

    local texture = totem and SpellTextures[totem] or icon
    button.icons[1]:SetTexture(texture)
    timer.warningMsgs[1] = "TotemWarning"
    timer.expirationMsgs[1] = "TotemExpiration"
    timer.earlyExpirationMsgs[1] = "TotemDestroyed"
    timer.warningIcons[1] = texture
    timer.warningSpells[1] = totem and SpellNames[totem]

    local data = totem and TotemData[totem]
    UpdateRangeDots(timer)
    if timer.procFlash and data and data.flashCurve then
        timer:StartBarTimer(duration, data.flashCurve)
    else
        timer:StopBarTimer()
    end
    timer.warningPoint = data and data.warningPoint or 10
    return true
end

function TotemTimers:TotemEvent(event, arg1, arg2, arg3, ...)
    local settings = TotemTimers.ActiveProfile
    if event == "PLAYER_TOTEM_UPDATE" then
        if self.element == arg1 then
            local active, totem, icon = GetActiveTotem(self.timer, arg1)
            if not active or not StartTotem(self, totem, icon) then
                if self.timer.timers[1] then
                    -- totems removed by a zone change (before PLAYER_ENTERING_WORLD stops them) give no warning
                    self.timer.stopQuiet = TotemTimers.IsZoning()
                    self.timer:Stop(1)
                end
                self.timer.activeTotem = nil
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- totem data is readable again, correct anything the in-combat cast tracking got wrong
        if issecretvalue((select(2, GetTotemInfo(self.element)))) then
            return
        end
        local active, totem, icon = GetActiveTotem(self.timer, self.element)
        if active then
            if not self.timer.timers[1] or self.timer.activeTotem ~= totem then
                StartTotem(self, totem, icon)
            end
        elseif self.timer.timers[1] then
            self.timer.stopQuiet = true
            self.timer:Stop(1)
            self.timer.activeTotem = nil
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg3 ~= TotemicRecall then
        local totem = TotemTimers.GetBaseSpellID(arg3)
        if TotemData[totem] and TotemData[totem].element == self.element then
            self.timer.pendingTotem = totem
            self.timer.pendingTotemTime = GetTime()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        --[[ -- SPELL_UPDATE_COOLDOWN
        local spell = self:GetAttribute("*spell1")
        if spell and (not self.timer.timerOnButton or self.timer.timers[1] <= 0) then
            local cd = C_Spell.GetSpellCooldown(spell)
            if cd.startTime and cd.duration then
                CooldownFrame_Set(self.cooldown, cd.startTime, cd.duration, cd.enable)
            end
        end
        if settings.ShowCooldowns then
            for key, spell in pairs(Cooldowns[self.timer.nr]) do
                local timerIndex = key + 1
                if AvailableSpells[spell] then
                    local cd = C_Spell.GetSpellCooldown(spell)
                    if not cd.startTime and not cd.duration then
                        self.timer:stop(timerIndex)
                        return
                    end
                    if cd.duration == 0 then
                        self.timer:Stop(timerIndex)
                    elseif cd.duration > 2 then
                        --and self.timer.timers[nr]<=0 then  -- update running cooldown timers for Ele T12-2pc
                        self.timer:Start(timerIndex, cd.startTime + cd.duration - floor(GetTime()), cd.duration)
                        self.timer.timerBars[timerIndex].icon:SetTexture(SpellTextures[spell])
                    end
                elseif self.timer.timers[timerIndex] > 0 then
                    self.timer:Stop(timerIndex)
                end
            end
        else
            for i = 2, self.timer.nrOfTimers do
                self.timer:Stop(i)
            end
        end ]]
    elseif (event == "UNIT_SPELLCAST_SUCCEEDED" and arg3 == TotemicRecall)
            or event == "PLAYER_ENTERING_WORLD" then
        self.timer.stopQuiet = true
        self.timer:Stop(1)
        --self.rangeCount:SetText("")
    --[[elseif event == "UNIT_SPELLCAST_SUCCEEDED" and self.timer.nr == 3 and arg3 == 24854 then
        --SpellIDs.EnamoredWaterSpirit
        self.timer:Start(1, 24, 24)]]
    elseif event == "GROUP_ROSTER_UPDATE" then
        TotemTimers.UpdateParty()
    end
end

local ButtonPositions = {
    ["box"] = { { "CENTER", 0, "CENTER" }, { "LEFT", 1, "RIGHT" }, { "TOP", 2, "BOTTOM" }, { "LEFT", 1, "RIGHT" } },
    ["horizontal"] = { { "CENTER", 0, "CENTER" }, { "LEFT", 1, "RIGHT" }, { "LEFT", 1, "RIGHT" }, { "LEFT", 1, "RIGHT" } },
    ["vertical"] = { { "CENTER", 0, "CENTER" }, { "TOP", 1, "BOTTOM" }, { "TOP", 1, "BOTTOM" }, { "TOP", 1, "BOTTOM" } }
}
local MultiCastButtonPositions = {
    ["box"] = { { "BOTTOMLEFT", 0, "RIGHT" }, { "LEFT", 1, "RIGHT" }, { "TOP", 2, "BOTTOM" }, { "LEFT", 1, "RIGHT" } },
    ["horizontal"] = { { "LEFT", 1, "RIGHT" }, { "LEFT", 1, "RIGHT" }, { "LEFT", 1, "RIGHT" }, { "LEFT", 1, "RIGHT" } },
    ["vertical"] = { { "TOP", 1, "BOTTOM" }, { "TOP", 1, "BOTTOM" }, { "TOP", 1, "BOTTOM" }, { "TOP", 1, "BOTTOM" } }
}
-- box arrangement with two buttons stacked in the center (multicast and Totemic Call): the upper row of the timers
-- starts right of the upper button, so the lower row is right of the lower one
local StackedBoxPositions = {
    ["box"] = { { "LEFT", 0, "RIGHT" }, { "LEFT", 1, "RIGHT" }, { "TOP", 2, "BOTTOM" }, { "LEFT", 1, "RIGHT" } },
}

function TotemTimers.OrderTimers()
    if InCombatLockdown() then
        return
    end
    local Timers = XiTimers.timers
    local Settings = TotemTimers.ActiveProfile
    for e = 1, 4 do
        Timers[e]:ClearAnchors()
        Timers[e].button:ClearAllPoints()
    end
    local c = 0
    local pos = {}

    local parentAnchor = TotemTimersFrame
    local buttonPositions = ButtonPositions
    local arrange = Settings.Arrange

    -- the multicast button (if shown) sits in the center of the totem timers, the Totemic Call button
    -- (TotemicCall.lua) next to it: left of it on horizontal arrangement, on top of it otherwise (switched with option
    -- SwapMultiCastCall); with only one of them that one takes the center; the timers are arranged around the center
    -- button
    local multiCast = TotemTimers_MultiSpell
    local multiCastShown = multiCast and Settings.MultiCast and multiCast.active and not Settings.HideMultiCast
    local call = TotemTimers.TotemicCallTimer
    local callShown = call and call.active
    if multiCastShown or callShown then
        -- the center and the other button: the multicast button (a frame) or the Totemic Call timer (an XiTimers
        -- timer, used itself as anchor so the timers keep their distance to its timer bar: XiTimers:SetPoint adds the
        -- border of a timer it is anchored to); option SwapMultiCastCall puts the Totemic Call button in the center
        local centerObj, otherObj
        if multiCastShown and callShown then
            if Settings.SwapMultiCastCall then
                centerObj, otherObj = call, multiCast
            else
                centerObj, otherObj = multiCast, call
            end
        else
            centerObj = multiCastShown and multiCast or call
        end
        local function FrameOf(obj) return obj == call and call.button or obj end
        -- space taken by the timer bar of the Totemic Call button (time not on the button) on a side
        local function Border(obj, side) return obj == call and call:GetBorder(side) or 0 end

        local centerFrame = FrameOf(centerObj)
        centerFrame:ClearAllPoints()
        centerFrame:SetPoint("CENTER", TotemTimersFrame, "CENTER")
        parentAnchor = centerObj
        buttonPositions = MultiCastButtonPositions
        if otherObj then
            local otherFrame = FrameOf(otherObj)
            local spacing = Settings.TimerSpacing or 0
            otherFrame:ClearAllPoints()
            if arrange == "horizontal" then
                local gap = spacing + Border(otherObj, "RIGHT") + Border(centerObj, "LEFT")
                otherFrame:SetPoint("RIGHT", centerFrame, "LEFT", -gap, 0)
            else
                local gap = spacing + Border(otherObj, "BOTTOM") + Border(centerObj, "TOP")
                otherFrame:SetPoint("BOTTOM", centerFrame, "TOP", 0, gap)
                if arrange == "box" then
                    -- the two buttons line up with the two rows of the timers: the center button moves down by half
                    -- of the stack, the timers start right of the upper button (the rows stay where they are around
                    -- the center)
                    centerFrame:ClearAllPoints()
                    centerFrame:SetPoint("CENTER", TotemTimersFrame, "CENTER", 0, -(centerFrame:GetHeight() + gap) / 2)
                    parentAnchor = otherObj
                    buttonPositions = StackedBoxPositions
                end
            end
        end
    end

    for e = 1, 4 do
        if Timers[e].active then
            c = c + 1
            Timers[e].actnr = c
            if arrange ~= "free" then
                if c == 1 then
                    Timers[e]:SetPoint(buttonPositions[arrange][1][1], parentAnchor, buttonPositions[arrange][1][3])
                else
                    Timers[e]:Anchor(pos[c - buttonPositions[arrange][c][2]], buttonPositions[arrange][c][1])
                end
                Timers[e].savePos = false
            else
                local pos = TotemTimers.ActiveProfile.TimerPositions[Timers[e].nr]
                if not pos or not pos[1] then
                    pos = { "CENTER", "UIParent", "CENTER", 0, 0 }
                end
                Timers[e].button:ClearAllPoints()
                Timers[e].button:SetPoint(pos[1], pos[2], pos[3], pos[4], pos[5])
                Timers[e].savePos = true
            end
            pos[c] = Timers[e]
        end
    end
end

local BarMiniIconPos = {
    ["horizontal"] = { { "BOTTOMLEFT", "TOPLEFT" }, { "BOTTOM", "TOP" }, { "BOTTOMRIGHT", "TOPRIGHT" }, },
    ["vertical"] = { { "TOPRIGHT", "TOPLEFT" }, { "RIGHT", "LEFT" }, { "BOTTOMRIGHT", "BOTTOMLEFT" }, },
}

function TotemTimers.ChangeTotemOrder(self, _, _, totem1)
    if InCombatLockdown() then
        return
    end
    --_, totem1 = GetSpellBookItemInfo(totem1, BOOKTYPE_SPELL)
    totem1 = TotemTimers.GetBaseSpellID(totem1)
    local totem2 = TotemTimers.GetBaseSpellID(self:GetAttribute("*spell1"))
    local nr = self:GetParent().element
    if nr and totem1 and totem2 and TotemData[totem1].element == TotemData[totem2].element then
        local Order = TotemTimers.ActiveProfile.TotemOrder[nr]
        local pos1, pos2 = 0, 0
        for i = 1, #TotemTimers.ActiveProfile.TotemOrder[nr] do
            if Order[i] == totem1 then
                pos1 = i
            end
            if Order[i] == totem2 then
                pos2 = i
            end
        end
        pos1 = pos1 or #TotemTimers.ActiveProfile.TotemOrder + 1
        pos2 = pos2 or #TotemTimers.ActiveProfile.TotemOrder + 1
        if pos1 > 0 and pos2 > 0 then
            Order[pos1] = totem2
            Order[pos2] = totem1
            --Order[pos1],Order[pos2] = Order[pos2],Order[pos1]
            TotemTimers.SetCastButtonSpells()
        end
    end
end


local TotemCount = TotemTimers.TotemCount

-- last button of a totem menu (the menu's extra button, see TTActionBars): toggles the exclusion of the element from
-- the active multicast spell like Ctrl-Rightclick on the timer button, out of combat only. Shows the multicast spell's
-- icon under the prohibition sign, red while included, green while excluded (UpdateMultiSpellExcluded); shown while the multicast button
-- is active (the timer's "mspell" child update)
function TotemTimers.SetupExcludeToggle(timer, toggle)
    timer.button.excludeToggle = toggle
    -- the whole button (icon, sign, border) slightly transparent, set apart from the totems
    toggle:SetAlpha(0.8)
    toggle:SetAttribute("inactive", true)
    toggle:SetAttribute("_childupdate-mspell", [[ self:SetAttribute("inactive", not message) ]])
    toggle.excludedSign = TotemTimers.CreateExcludedIcon(toggle)
    -- 90 % of the icon's size, centered on it (the menu buttons are 36 units wide)
    local inset = toggle:GetWidth() * 0.05
    toggle.excludedSign:SetPoint("TOPLEFT", toggle.icon, "TOPLEFT", inset, -inset)
    toggle.excludedSign:SetPoint("BOTTOMRIGHT", toggle.icon, "BOTTOMRIGHT", -inset, inset)
    toggle.excludedSign:SetFrameLevel(toggle:GetFrameLevel() + 2)
    toggle.excludedSign:Show()
    toggle.tooltip = TotemTimers.Tooltips.MultiSpellExclude:new(toggle)
    timer.button:WrapScript(toggle, "OnClick", [[
        if PlayerInCombat() then return end
        local timerButton = self:GetParent()
        local mspell = timerButton:GetAttribute("mspell")
        if mspell then
            local disabled = not timerButton:GetAttribute("mspelldisabled" .. mspell)
            timerButton:SetAttribute("mspelldisabled" .. mspell, disabled)
            control:CallMethod("DisableMultiSpell", mspell, disabled)
        end
    ]])
end

function TotemTimers.CreateCastButtons()
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        local totemCount = TotemCount[timer.nr]
        local actionBar = TTActionBars:new(totemCount, timer.button, _G["TotemTimers_CastBar" .. i], TotemTimersFrame,
                nil, TotemTimers.HasMultiCast)
        timer.actionBar = actionBar
        if actionBar.extraButton then
            TotemTimers.SetupExcludeToggle(timer, actionBar.extraButton)
        end
        for j = 1, totemCount do
            local button = timer.actionBar.buttons[j]
            button.ChangeTotemOrder = TotemTimers.ChangeTotemOrder

            button:SetAttribute("SpellIDs", TotemTimers.NameToSpellID)

            button:SetAttribute("_ondragstart", [[if IsShiftKeyDown() and self:GetAttribute("*spell1")~=0 then
                                                                            return "spell", self:GetAttribute("*spell1")
                                                                       else control:CallMethod("StartBarDrag") end]])
            button:SetAttribute("_onreceivedrag", [[ if kind == "spell" then
                                                                            control:CallMethod("ChangeTotemOrder", value, ...)
                                                                            return "clear"
                                                                       end]])
            if TotemTimers.HasMultiCast then
                button:SetAttribute("_childupdate-mspell", [[ self:SetAttribute("*action*", message) ]])
                button:SetAttribute("_childupdate-mspelldisabled", [[ if message then self:SetAttribute("*type2", nil) else self:SetAttribute("*type2", "multispell") end]])
                local multispell = TotemTimers.ActiveProfile.LastMultiCastSpell or SpellIDs.CallOfElements
                button:SetAttribute("*action*", MultiCastActions[i][multispell])
                button:SetAttribute("*type2", "multispell")
            end
        end
    end
    TotemTimers.PositionCastButtons()
    TotemTimers.SetCastButtonSpells()
end

local TotemCastPositions = {
    ["LEFT"] = { [1] = "BOTTOMRIGHT", [2] = "TOPRIGHT" },
    ["RIGHT"] = { [1] = "BOTTOMLEFT", [2] = "TOPLEFT" },
    ["TOP"] = { [1] = "BOTTOMRIGHT", [2] = "BOTTOMLEFT" },
    ["BOTTOM"] = { [1] = "TOPRIGHT", [2] = "TOPLEFT" },
}

function TotemTimers.PositionCastButtons()
    local Profile = TotemTimers.ActiveProfile
    for i = 1, 4 do
        TTActionBars.bars[i]:SetDirection(Profile.CastBarDirection, Profile.Arrange)
    end
    if TotemTimers_MultiSpell then
        TotemTimers_MultiSpell.actionBar:SetDirection(Profile.CastBarDirection, Profile.Arrange)
    end

    -- and position totem cast buttons
   --[[ local pos = Profile.CastButtonPosition
    if Profile.Arrange == "horizontal" then
        if pos ~= "TOP" and pos ~= "BOTTOM" then
            local dir = TTActionBars.bars[1]:CalcDirection(Profile.CastBarDirection, Profile.Arrange)
            if dir == "down" then
                pos = "TOP"
            else
                pos = "BOTTOM"
            end
        end
    elseif Profile.Arrange == "vertical" then
        if pos ~= "LEFT" and pos ~= "RIGHT" then
            local dir = TTActionBars.bars[1]:CalcDirection(Profile.CastBarDirection, Profile.Arrange)
            if dir == "left" then
                pos = "RIGHT"
            else
                pos = "LEFT"
            end
        end
    end]]
end

function TotemTimers.SetCastButtonSpells()
    local Profile = TotemTimers.ActiveProfile
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        local totems = {}
        for k, v in pairs(Profile.TotemOrder[timer.nr]) do
            if TotemTimers.AvailableSpells[v] and not Profile.HiddenTotems[v] and not TotemData[v].isOverride then
                table.insert(totems, v)
            end
        end
        TTActionBars.bars[timer.nr]:SetSpells(totems)
    end
end

-- Totems of the timer buttons (and, only where needed, of the multicast slots):
-- * a timer takes the totem of the active multicast spell's slot of its element (the game saves those); if the
--   timer's element is excluded from that multicast spell (slot intentionally empty) or there is no multicast
--   spell, it keeps its totem, after loading the one from the saved settings (LastTotems)
-- * an invalid totem (unknown spell, other element, saved data broken) is replaced: by the timer's own totem, the
--   saved one, or as a last resort the first totem of the menu (also when the first totem of an element is learned)
-- * a multicast slot is only written when it is empty but not supposed to be (not excluded): it gets the timer's
--   totem (new multicast spell learned, element learned after the multicast spell)
-- Out of combat only (the spell and talent events wait for the end of combat, see TotemTimers.lua).

local function IsValidTotem(spell, timer)
    if (type(spell) ~= "number" and type(spell) ~= "string") or (issecretvalue and issecretvalue(spell)) then
        return false
    end
    local base = TotemTimers.GetBaseSpellID(spell)
    local data = base and TotemData[base]
    return data and AvailableSpells[base] and data.element == timer.nr and not data.isOverride and true or false
end

-- totems are stored as spell IDs; the saved settings can hold names (defaults): highest known rank of it
local function ToSpellID(spell)
    if type(spell) == "string" then
        local base = TotemTimers.GetBaseSpellID(spell)
        if type(base) ~= "number" then return nil end
        return C_Spell.GetSpellIDForSpellIdentifier(spell) or base
    end
    return spell
end

-- first totem of the timer's menu (by the menu order of the profile), or any known totem of the element
local function GetFirstMenuTotem(timer)
    local profile = TotemTimers.ActiveProfile
    for _, spell in ipairs(profile.TotemOrder[timer.nr] or {}) do
        if not profile.HiddenTotems[spell] and IsValidTotem(spell, timer) then
            return TotemTimers.UpdateSpellRank(spell) or spell
        end
    end
    for spell in pairs(TotemData) do
        if IsValidTotem(spell, timer) then
            return TotemTimers.UpdateSpellRank(spell) or spell
        end
    end
end

-- true while the totems are loaded: the timer buttons don't put their totem into the multicast slot then
-- (SyncMultiCastSlot), only empty slots are written here
TotemTimers.LoadingTotems = false

-- while zoning (TotemTimers.IsZoning) the multicast slots can read empty: the timers then take their own or the
-- saved totem, no slot is written, and the update is repeated once the zoning is over (after combat if needed)
local zoningRetryPending = false
local zoningRetryFrame = CreateFrame("Frame")
zoningRetryFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    TotemTimers.UpdateTimerTotems()
end)

local function RetryTimerTotemsAfterZoning()
    if zoningRetryPending then return end
    zoningRetryPending = true
    C_Timer.After(1, function()
        zoningRetryPending = false
        if InCombatLockdown() then
            zoningRetryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            TotemTimers.UpdateTimerTotems()
        end
    end)
end

function TotemTimers.UpdateTimerTotem(timer)
    if InCombatLockdown() or not timer.active then return end
    local zoning = TotemTimers.IsZoning()
    if zoning then RetryTimerTotemsAfterZoning() end
    local button = timer.button
    local profile = TotemTimers.ActiveProfile
    local multiSpell = TotemTimers_MultiSpell
    local multiActive = multiSpell and multiSpell.active
    local activeMSpell = multiActive and multiSpell:GetAttribute("*spell1")
    local current = button:GetAttribute("*spell1")
    local saved = ToSpellID(profile.LastTotems[timer.nr])

    -- the multicast slots of the element of each known multicast spell
    local slots = {}
    if multiActive and not zoning then
        for mspell, action in pairs(TotemTimers.MultiCastActions[timer.nr] or {}) do
            if AvailableSpells[mspell] then
                local actionType, id = GetActionInfo(action)
                slots[mspell] = {
                    action = action,
                    spell = actionType == "spell" and id or nil,
                    disabled = profile.DisabledMultiSpells[TotemTimers.Specialization .. mspell .. timer.nr] and true or false,
                }
            end
        end
    end

    local spell
    local active = activeMSpell and slots[activeMSpell]
    if active then
        spell = active.disabled and saved or active.spell
    end
    if not IsValidTotem(spell, timer) then
        spell = (IsValidTotem(current, timer) and current) or (IsValidTotem(saved, timer) and saved)
                or GetFirstMenuTotem(timer)
    end

    -- a fallback for a saved totem that isn't known (yet, e.g. a talent totem while switching specs) keeps the
    -- saved one in the settings
    local savedRaw = profile.LastTotems[timer.nr]
    local keepSaved = spell ~= current and not IsValidTotem(saved, timer) and savedRaw ~= nil
            and not (active and not active.disabled and spell == active.spell)

    TotemTimers.LoadingTotems = true
    for mspell, slot in pairs(slots) do
        button:SetAttribute("action" .. mspell, slot.action)
        button:SetAttribute("mspelldisabled" .. mspell, slot.disabled)
        if slot.disabled then
            -- switching to this multicast spell keeps the timer's totem
            button:SetAttribute("mspell" .. mspell, nil)
        else
            if not slot.spell and spell then
                SetMultiCastSpell(slot.action, spell)
                slot.spell = spell
            end
            button:SetAttribute("mspell" .. mspell, IsValidTotem(slot.spell, timer) and slot.spell or spell)
        end
    end
    if spell and spell ~= current then
        button:SetAttribute("*spell1", spell)
        if keepSaved then profile.LastTotems[timer.nr] = savedRaw end
    end
    TotemTimers.LoadingTotems = false
end

function TotemTimers.UpdateTimerTotems()
    if InCombatLockdown() then return end
    for i = 1, 4 do
        TotemTimers.UpdateTimerTotem(XiTimers.timers[i])
    end
    if TotemTimers_MultiSpell and TotemTimers_MultiSpell.active then
        TotemTimers_MultiSpell:UpdateTexture()
    end
end
table.insert(TotemTimers.SpellUpdaters, TotemTimers.UpdateTimerTotems)

-- party changed: class colors of the party dots
TotemTimers.UpdateParty = function()
    for i = 1,4 do
        local unit = "party"..i
        if UnitExists(unit) then
            local class = select(2, UnitClass(unit))
            if class and RAID_CLASS_COLORS[class] then
                local color = RAID_CLASS_COLORS[class]
                for element = 1,4 do
                    local timer = XiTimers.timers[element]
                    timer.button.partyRange[i]:SetVertexColor(color.r, color.g, color.b)
                    for _, set in ipairs(timer.rangeDotSets or {}) do
                        local display = set.displays[unit]
                        if display then display:SetDotColor(color.r, color.g, color.b) end
                    end
                end
            end
        else
            for element = 1,4 do XiTimers.timers[element].button.partyRange[i]:Hide() end
        end
    end
end