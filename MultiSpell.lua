if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...
local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers", true)

local mb  -- abrev for MulticastButton

local SpellNames = TotemTimers.SpellNames
local AvailableSpells = TotemTimers.AvailableSpells

local SpellIDs = TotemTimers.SpellIDs
local SpellTextures = TotemTimers.SpellTextures

function TotemTimers.CreateMultiCastButtons()
    mb = CreateFrame("Button", "TotemTimers_MultiSpell", UIParent, "ActionButtonTemplate, SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerAttributeTemplate")
    XiTimers.AddSpecialActionBarDriver(mb)
    mb:SetWidth(36)
    mb:SetHeight(36)
    mb:SetScale(32 / 36)
    --mb:SetPoint("CENTER", TotemTimers_MultiSpellFrame, "CENTER")
    mb.actionBar = TTActionBars:new(3, mb, TotemTimers_MultiSpellFrame, TotemTimersFrame)
    mb.icon = _G["TotemTimers_MultiSpellIcon"]
    mb:Hide()

    --for rActionButtonStyler
    mb.action = 0
    mb.SetCheckedTexture = function()
    end

    local regions = {mb:GetRegions()}
    for i, region in ipairs(regions) do
        if not region:GetName() then
            region:SetTexture(nil)
            region:Hide()
        end
    end

    --mb:SetNormalTexture(nil)
    _G["TotemTimers_MultiSpellNormalTexture"]:SetTexture(nil)

    mb.icon:Show()

    for e = 1, 4 do
        mb:SetFrameRef("t" .. e, XiTimers.timers[e].button)
    end

    mb:SetAttribute("*type*", "spell")

    mb.UpdateTexture = function(self)
        local spell = self:GetAttribute("*spell1")
        if spell then
            local texture = C_Spell.GetSpellTexture(spell)
            if texture then
                self.icon:SetTexture(texture)
            end
            TotemTimers.ActiveProfile.LastMultiCastSpell = spell
            -- excluded elements are marked on their timer buttons (UpdateMultiSpellExcluded)
        end
    end

    mb.HideTooltip = function(self)
        GameTooltip:Hide()
    end

    mb:SetAttribute("_onattributechanged", [[ if name == "*spell1" then
                                                  self:CallMethod("UpdateTexture")
                                                  for e=1,4 do
												      self:GetFrameRef("t"..e):SetAttribute("mspell", value)
												  end
                                              elseif name == "state-invehicle" then
                                                 if value == "show" and self:GetAttribute("active") then
                                                    self:Show()
                                                    local s = self:GetAttribute("*spell1")
                                                    if s then self:SetAttribute("*spell1", s) end
                                                else
                                                    self:Hide()
                                                end
											  elseif name:sub(1,8) == "disabled" then
												self:CallMethod("UpdateTexture")
                                             end]])
    mb:WrapScript(mb, "OnClick", [[ if button == "Button4" then
                                                          control:ChildUpdate("toggle")
                                                      end ]])

    -- cooldown swirl of the button's spell, the multicast spells have no cooldown of their own,
    -- so it shows every global cooldown
    mb.cooldown = mb.cooldown or _G["TotemTimers_MultiSpellCooldown"]
    mb.cooldown:SetHideCountdownNumbers(true)
    mb.cooldown.noCooldownCount = true
    mb:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    mb:SetScript("OnEvent", function(self, event)
        if event == "SPELL_UPDATE_COOLDOWN" then
            local spell = self:GetAttribute("*spell1")
            local durObj = spell and C_Spell.GetSpellCooldownDuration(spell)
            if durObj then
                self.cooldown:SetCooldownFromDurationObject(durObj)
            end
        end
    end)

    mb:SetAttribute("OpenMenu", "mouseover")
    mb:SetAttribute("*spell2", SpellIDs.TotemicRecall)
    mb:SetAttribute("*spell1", TotemTimers.ActiveProfile.LastMultiCastSpell or SpellIDs.CallOfElements)
    mb:SetAttribute("*spell3", SpellIDs.TotemicRecall)
    -- mb:RegisterForClicks("LeftButton, RightButton")
    mb:RegisterForClicks("AnyDown")
    mb:SetAttribute("useOnKeyDown", 1)
    TotemTimers.PositionCastButtons()
end

table.insert(TotemTimers.Modules, TotemTimers.CreateMultiCastButtons)

-- The game's totem bar shows itself again through TotemActionBarMixin:UpdateShownState
-- (edit mode layout, main action bar state changes), also after the hide on login.
-- Hide it after each of these updates while the multicast button is enabled; the bar
-- holds secure buttons, so in combat the hide waits for PLAYER_REGEN_ENABLED.
-- Only Hide() is called on the bar: anything that re-lays out the bottom bars taints them.
-- The bar's own events (PLAYER_ENTERING_WORLD, UPDATE_MULTI_CAST_ACTIONBAR) are unregistered and its
-- EventRegistry callback "ActionBarController.MainActionBarStateOverridden" (vehicle, override and possess
-- bars) is removed, so it isn't shown in combat, where it can't be hidden. Edit mode can't be entered in
-- combat. The callback can't be registered again by TotemTimers: run from addon code, it would show and hide
-- the protected bar tainted (blocked in combat); after the option is turned off it is back with /reload.
local hideBlizzBar = false
local blizzBarHooked = false
local blizzCallbackRemoved = false
local reloadMessageShown = false
local regenFrame

local function EnforceBlizzBarHidden()
    if not hideBlizzBar or not MultiCastActionBarFrame:IsShown() then return end
    if InCombatLockdown() then
        if not regenFrame then
            regenFrame = CreateFrame("Frame")
            regenFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                EnforceBlizzBarHidden()
            end)
        end
        regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    -- no EditModeManager.UpdateBottomActionBarPositions from here: run by addon code it
    -- taints the positions of the main action bar stack, which then breaks in combat
    MultiCastActionBarFrame:Hide()
end

local function SetBlizzBarHidden(hide)
    -- the bar is given back with its callback removed (option turned off, profile without multicast button):
    -- it only follows vehicle and override bars again after a reload (once per session)
    if hideBlizzBar and not hide and blizzCallbackRemoved and not reloadMessageShown then
        reloadMessageShown = true
        print(L["Reload for default totem bar"])
    end
    hideBlizzBar = hide
    if hide and not blizzBarHooked and MultiCastActionBarFrame.UpdateShownState then
        blizzBarHooked = true
        hooksecurefunc(MultiCastActionBarFrame, "UpdateShownState", EnforceBlizzBarHidden)
    end
    -- the dispatch of EventRegistry calls each callback with securecallfunction, removing this one leaves the
    -- others untouched
    if hide and not blizzCallbackRemoved and EventRegistry and EventRegistry.UnregisterCallback then
        blizzCallbackRemoved = true
        EventRegistry:UnregisterCallback("ActionBarController.MainActionBarStateOverridden", MultiCastActionBarFrame)
    end
    EnforceBlizzBarHidden()
end

function TotemTimers.MultiSpellActivate()
    if TotemTimers.ActiveProfile.MultiCast then
        if AvailableSpells[SpellIDs.CallOfElements] then
            if not TotemTimers.ActiveProfile.HideMultiCast then mb:Show() else mb:Hide() end
            TotemTimers.SetMultiCastSpells()
            mb.active = true
            TotemTimers.SetMultiCastConfig()
            mb:SetAttribute("active", true)
        end

        MultiCastActionBarFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        MultiCastActionBarFrame:UnregisterEvent("UPDATE_MULTI_CAST_ACTIONBAR")
        SetBlizzBarHidden(true)
    else
        SetBlizzBarHidden(false)
        if mb.active then
            MultiCastActionBarFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            MultiCastActionBarFrame:RegisterEvent("UPDATE_MULTI_CAST_ACTIONBAR")
            MultiCastActionBarFrame:Show()
            MultiCastActionBarFrame_OnEvent(MultiCastActionBarFrame, "UPDATE_MULTI_CAST_ACTIONBAR")
        end

        for i = 1, 4 do
            XiTimers.timers[i].button:SetAttribute("mspell", nil)
        end
        mb:Hide()
        mb:SetAttribute("active", false)
        mb.active = false

    end
    TotemTimers.ProcessSetting("TimerSize")
    TotemTimers.OrderTimers()
end

function TotemTimers.SetMultiCastSpells()
    mb.actionBar:ResetSpells()
    for _, spellID in pairs({ SpellIDs.CallOfElements, SpellIDs.CallOfAncestors, SpellIDs.CallOfSpirits }) do
        if AvailableSpells[spellID] then
            mb.actionBar:AddSpell(spellID)
        end
    end
end

table.insert(TotemTimers.SpellUpdaters, TotemTimers.SetMultiCastSpells)

-- totems of the timer buttons from the multicast slots of the active multicast spell, empty slots that aren't
-- excluded filled from the timers (TotemTimers.UpdateTimerTotems, SetupTimers.lua; it is a spell updater itself)
function TotemTimers.SetMultiCastConfig()
    if not mb.active then
        return
    end
    TotemTimers.UpdateTimerTotems()
    --trigger Childupdate("mspell"): the timers take the totem of the active multicast spell
    mb:SetAttribute("*spell1", mb:GetAttribute("*spell1"))
end
