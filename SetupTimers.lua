if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...

local GetSpellInfo = TotemTimers.GetSpellInfo
local GetSpellCooldown = TotemTimers.GetSpellCooldown
local GetSpellTexture = TotemTimers.GetSpellTexture



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

local UpdatePartyRange
local TotemUpdate


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


local MultiCastActions = {}
TotemTimers.MultiCastActions = MultiCastActions
if LE_EXPANSION_LEVEL_CURRENT > LE_EXPANSION_BURNING_CRUSADE and LE_EXPANSION_LEVEL_CURRENT < LE_EXPANSION_MISTS_OF_PANDARIA then
    for i=1,4 do
        local index = SHAMAN_TOTEM_PRIORITIES[i];
        MultiCastActions[index] =
        { [SpellIDs.CallOfElements] = ActionButton_CalculateAction(_G["MultiCastActionButton"..index]),
          [SpellIDs.CallOfAncestors] = ActionButton_CalculateAction(_G["MultiCastActionButton"..(index + 4)]),
          [SpellIDs.CallOfSpirits] = ActionButton_CalculateAction(_G["MultiCastActionButton"..(index + 8)]) }
    end
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
                local texture = GetSpellInfo(self:GetAttribute("*spell1")).iconID
                local oldTexture = self.miniIcon:GetTexture()
                self.miniIcon:SetTexture(texture)
                if (not self.timer.timersRunning[1] and texture ~= oldTexture) then
                    self.icons[1]:SetTexture(texture)
                end
                TotemTimers.TotemEvent(self, "SPELL_UPDATE_COOLDOWN", self.timer.nr)
                self.timer.manaCheck = spell
                TotemTimers.ActiveProfile.LastTotems[self.timer.nr] = spell
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
														 elseif name:sub(1,14) == "mspelldisabled" then	
															local mspell = tonumber(name:sub(15))
															local disabled = self:GetAttribute(name)
															local activeMspell = self:GetAttribute("mspell")
															if mspell == activeMspell then
																self:ChildUpdate("mspelldisabled", disabled)
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
		
		--declare empty function here for classic and tbc
		tt.button.DisableMultiSpell = function(self, multispell, disable) end		

        tt.Activate = function(self)
            if self.active then return end
            local activeProfile = TotemTimers.ActiveProfile

            XiTimers.Activate(self)

            TotemTimers.TotemEvent(self.button, "PLAYER_TOTEM_UPDATE", self.nr)
            TotemTimers.TotemEvent(self.button, "SPELL_UPDATE_COOLDOWN", self.nr)

            if activeProfile.CheckPlayerRange or activeProfile.CheckRaidRange then
                self.button:RegisterEvent("UNIT_AURA")
                if activeProfile.CheckRaidRange then
                    self.button:RegisterEvent("GROUP_ROSTER_UPDATE")
                    if self.nr == AIR_TOTEM_SLOT or self.nr == FIRE_TOTEM_SLOT then
                        self.button:RegisterEvent("CHAT_MSG_ADDON")
                    end
                end

                --show range dots on ui reload
                if (self.totemBuff or self.totemRange) and self.timers[1] > 0 then
                    if activeProfile.CheckPlayerRange then UpdatePartyRange(self, "player") end
                    if activeProfile.CheckRaidRange then
                        for i = 1,4 do UpdatePartyRange(self, "party"..i) end
                    end
                end
            end

            local lastTotem = TotemTimers.GetBaseSpellID(activeProfile.LastTotems[self.nr])

            if not self.timersRunning[1] then
                if not lastTotem or not AvailableSpells[lastTotem] then
                    --[[when switching specs this part gets executed several times, once for switching and then for each talent (because of events fired)
                        so totems from talents are sometimes not available at this point.
                        lasttotem is saved and restored if not nil so that talent totems aren't replaced when switching specs ]]
                    for k, v in pairs(TotemData) do
                        if AvailableSpells[k] and v.element == self.nr then
                            self.button:SetAttribute("*spell1", k)
                            self.button.icon:SetTexture(GetSpellTexture(k))
                            break
                        end
                    end
                    -- restore saved totem if not nil
                    activeProfile.LastTotems[self.nr] = lastTotem or activeProfile.LastTotems[self.nr]
                else
                    self.button:SetAttribute("*spell1", lastTotem)
                    self.button.icon:SetTexture(GetSpellTexture(lastTotem))
                end
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
            end
        end

        tt.Update = TotemUpdate

        --[[ tt.Update = function(self, elapsed)
            XiTimers.Update(self, elapsed)
            if self.timers[1] > 0 then
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

        if LE_EXPANSION_LEVEL_CURRENT > LE_EXPANSION_BURNING_CRUSADE then

			tt.button.DisableMultiSpell = function(self, multispell, disable)
                if not multispell or InCombatLockdown() then return end
                local action = self:GetAttribute("action"..multispell)
                SetMultiCastSpell(action, not disable and self:GetAttribute("*spell1") or nil)
                TotemTimers.ActiveProfile.DisabledMultiSpells[TotemTimers.Specialization..multispell..self.timer.nr] = disable
                TotemTimers_MultiSpell:UpdateTexture()
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

local TotemicCall = TotemTimers.SpellIDs.TotemicCall

TotemUpdate = function(self, ...)
    XiTimers.Update(self, ...)
    if self.timers[1] > 0 and self.totemRange then
        UpdatePartyRange(self, "player")
        for i = 1,4 do
            UpdatePartyRange(self, "party"..i)
        end
    end
end

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
    timer.totemBuff = data and data.buffName
    timer.totemRange = data and data.rangeCheck and data.rangeCheck + AvailableTalents.TotemicMastery
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
                if self.timer.timersRunning[1] then
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
            if not self.timer.timersRunning[1] or self.timer.activeTotem ~= totem then
                StartTotem(self, totem, icon)
            end
        elseif self.timer.timersRunning[1] then
            self.timer.stopQuiet = true
            self.timer:Stop(1)
            self.timer.activeTotem = nil
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg3 ~= TotemicCall then
        local totem = TotemTimers.GetBaseSpellID(arg3)
        if TotemData[totem] and TotemData[totem].element == self.element then
            self.timer.pendingTotem = totem
            self.timer.pendingTotemTime = GetTime()
        end
    elseif event == "UNIT_AURA" and self.timer.totemBuff and self.timer.timers[1] > 0 then
        if (settings.CheckPlayerRange and arg1 == "player") or settings.CheckRaidRange then
            UpdatePartyRange(self.timer, arg1)
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        --[[ -- SPELL_UPDATE_COOLDOWN
        local spell = self:GetAttribute("*spell1")
        if spell and (not self.timer.timerOnButton or self.timer.timers[1] <= 0) then
            local cd = GetSpellCooldown(spell)
            if cd.startTime and cd.duration then
                CooldownFrame_Set(self.cooldown, cd.startTime, cd.duration, cd.enable)
            end
        end
        if settings.ShowCooldowns then
            for key, spell in pairs(Cooldowns[self.timer.nr]) do
                local timerIndex = key + 1
                if AvailableSpells[spell] then
                    local cd = GetSpellCooldown(spell)
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
    elseif (event == "UNIT_SPELLCAST_SUCCEEDED" and arg3 == TotemicCall)
            or event == "PLAYER_ENTERING_WORLD" then
        self.timer.stopQuiet = true
        self.timer:Stop(1)
        --self.rangeCount:SetText("")
    --[[elseif event == "UNIT_SPELLCAST_SUCCEEDED" and self.timer.nr == 3 and arg3 == 24854 then
        --SpellIDs.EnamoredWaterSpirit
        self.timer:Start(1, 24, 24)]]
    elseif event == "GROUP_ROSTER_UPDATE" then
        TotemTimers.UpdateParty()
    elseif event == "CHAT_MSG_ADDON" and self.timer.timers[1] > 0 and arg1 == "WF_STATUS" then
        local guid, enchantID, duration, lag = strsplit(':', arg2)
        if self.timer.twisting and duration then
            duration = tonumber(duration)
            if duration and duration > 0 then
                local playerLag = select(3, GetNetStats())
                duration = (duration - lag - playerLag) / 1000
            else
                duration = 0
            end
        else
            duration = 0
        end
        UpdatePartyRange(self.timer, nil, guid, tonumber(enchantID), duration)
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

    if TotemTimers_MultiSpell and Settings.MultiCast then
        parentAnchor = TotemTimers_MultiSpell
        buttonPositions = MultiCastButtonPositions
        TotemTimers_MultiSpell:SetPoint("CENTER", TotemTimersFrame, "CENTER")
    end

    local arrange = Settings.Arrange

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

function TotemTimers.CreateCastButtons()
    for i = 1, 4 do
        local timer = XiTimers.timers[i]
        local totemCount = TotemCount[timer.nr]
        local actionBar = TTActionBars:new(totemCount, timer.button, _G["TotemTimers_CastBar" .. i], TotemTimersFrame)
        timer.actionBar = actionBar
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
            if LE_EXPANSION_LEVEL_CURRENT > LE_EXPANSION_BURNING_CRUSADE and LE_EXPANSION_LEVEL_CURRENT < LE_EXPANSION_MISTS_OF_PANDARIA then
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

-- makes sure, totems assigned to timer buttons are available spells
-- replaces totem with first in menu in necessary
local function SanitizeTotem(spellID, timer)
    if not spellID then
        return timer.actionBar.buttons[1]:GetAttribute("*spell1")
    else
        local baseSpellID = TotemTimers.GetBaseSpellID(spellID)
        if not AvailableSpells[baseSpellID] or not TotemData[baseSpellID] then
            TotemTimers.AddDebug("Replace "..(spellID or "").." - "..(baseSpellID or "") .. " - "..(timer.actionBar.buttons[1]:GetAttribute("*spell1") or ""))
            return timer.actionBar.buttons[1]:GetAttribute("*spell1")
        end
        return TotemTimers.UpdateSpellRank(spellID)
    end
end
TotemTimers.SanitizeTotem = SanitizeTotem

local function SanitizeActiveTotems()
    for i = 1,4 do
        local timer = XiTimers.timers[i]
        local spellID = timer.button:GetAttribute("*spell1")
        local newSpellID = SanitizeTotem(spellID, timer)
        if spellID ~= newSpellID then
            timer.button:SetAttribute("*spell1", newSpellID)
        end
    end
end
table.insert(TotemTimers.SpellUpdaters, SanitizeActiveTotems)

local partyGUIDs = {}

local TotemWeaponEnchants = TotemTimers.TotemWeaponEnchants

UpdatePartyRange = function(timer, unit, unitGUID, enchantID, wfDuration)
    if unit and unit ~= "player" and (not strmatch(unit, "^party%d$") or not UnitExists(unit)) or not UnitBuff then
        return
    end

    local rangeDot

    if unitGUID then
        unit = partyGUIDs[unitGUID]
        if not unit then return end
    end
    if unit == "player" then
        rangeDot = timer.button.playerRange
    else
        rangeDot = timer.button.partyRange[tonumber(strsub(unit, -1))]
    end

    local inRange = false

    if unitGUID then
        if enchantID and TotemWeaponEnchants[enchantID] == timer.activeTotem then
            inRange = true
            if timer.twisting and wfDuration and wfDuration > 0
              and timer.barTimer > 0 and math.abs(wfDuration - timer.barTimer) > 0.5 then
                timer.barTimer = wfDuration
            end
        end
    else
        local totemBuff = timer.totemBuff

        local found = false

        for i = 1, 32 do
            local name = UnitBuff(unit, i)
            if not name then break end
            if name == totemBuff then
                inRange = true
                break
            end
        end
    end
    if unit == "player" then
        if inRange then
            rangeDot:Hide()
        else
            rangeDot:Show()
        end
    else
        if inRange then
            rangeDot:Show()
        else
            rangeDot:Hide()
        end
    end
end

TotemTimers.UpdateParty = function()
    wipe(partyGUIDs)
    for i = 1,4 do
        local unit = "party"..i
        if UnitExists(unit) then
            partyGUIDs[UnitGUID(unit)] = unit
            local class = select(2, UnitClass(unit))
            if class and RAID_CLASS_COLORS[class] then

                for element = 1,4 do
                    XiTimers.timers[element].button.partyRange[i]:SetVertexColor(
                RAID_CLASS_COLORS[class].r,
                RAID_CLASS_COLORS[class].g,
                    RAID_CLASS_COLORS[class].b
                    )
                    end
                end
        else
            for element = 1,4 do XiTimers.timers[element].button.partyRange[i]:Hide() end
        end
    end
end