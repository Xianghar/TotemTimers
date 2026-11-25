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

-- the macro TotemTimers writes (TotemTimers.UpdateMacro): a /castsequence of the timers' totems; option
-- MultiCastMacroButton adds it to the multicast menu, selected (rightclick, gamepad wheel assign) the multicast button
-- casts it instead of a multicast spell (attribute ttmacro, *type1 "macro"; *spell1 is nil then, so the timers have no
-- multicast spell; saved as profile.MultiCastMacro)
local CAST_MACRO = "TT Cast"
TotemTimers.CastMacroName = CAST_MACRO

-- the spell the TT Cast macro casts next, nil without the macro
function TotemTimers.GetCastMacroSpell()
    local index = GetMacroIndexByName(CAST_MACRO)
    if not index or index == 0 then return end
    return GetMacroSpell(index)
end

-- icon of the macro like the game shows it (question mark icon: the spell it casts next), from the spell it casts
-- next without one, the question mark without the macro
function TotemTimers.GetCastMacroTexture()
    local index = GetMacroIndexByName(CAST_MACRO)
    if not index or index == 0 then return 134400 end
    local _, icon = GetMacroInfo(index)
    if (issecretvalue and issecretvalue(icon)) or icon then return icon end
    local spell = GetMacroSpell(index)
    return spell and C_Spell.GetSpellTexture(spell) or 134400
end

-- the castsequence moves on after a cast (the game's macro buttons follow ACTIONBAR_SLOT_CHANGED) and starts over
-- after its reset (MacroReset seconds without a cast, combat end): the icons are read again a frame later
local macroIconFrame = CreateFrame("Frame")
local macroIconPending = false
local function RefreshMacroIcons()
    macroIconPending = false
    if TotemTimers.UpdateCastMacroIcons then TotemTimers.UpdateCastMacroIcons() end
end
local function QueueMacroIconRefresh(delay)
    if delay then
        C_Timer.After(delay, RefreshMacroIcons)
    elseif not macroIconPending then
        macroIconPending = true
        C_Timer.After(0, RefreshMacroIcons)
    end
end
macroIconFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
macroIconFrame:RegisterEvent("UPDATE_MACROS")
macroIconFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
macroIconFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
macroIconFrame:SetScript("OnEvent", function(self, event)
    if not mb then return end
    QueueMacroIconRefresh()
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- the reset of the sequence has no event
        local reset = TotemTimers.ActiveProfile and TotemTimers.ActiveProfile.MacroReset
        if reset then QueueMacroIconRefresh(reset + 0.2) end
    end
end)

function TotemTimers.CreateMultiCastButtons()
    mb = CreateFrame("Button", "TotemTimers_MultiSpell", UIParent, "ActionButtonTemplate, SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate, SecureHandlerAttributeTemplate")
    XiTimers.AddSpecialActionBarDriver(mb)
    mb:SetWidth(36)
    mb:SetHeight(36)
    mb:SetScale(32 / 36)
    --mb:SetPoint("CENTER", TotemTimers_MultiSpellFrame, "CENTER")
    -- the multicast spells and the TT Cast macro
    mb.actionBar = TTActionBars:new(4, mb, TotemTimers_MultiSpellFrame, TotemTimersFrame)
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
        if self:GetAttribute("ttmacro") then
            self.icon:SetTexture(TotemTimers.GetCastMacroTexture())
            return
        end
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

    -- the macro was selected or deselected (secure, also in combat)
    mb.MacroModeChanged = function(self, macro)
        TotemTimers.ActiveProfile.MultiCastMacro = macro and true or nil
        self:UpdateTexture()
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
											  elseif name == "ttmacro" then
												  self:CallMethod("MacroModeChanged", value)
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
            if self:GetAttribute("ttmacro") then
                -- the macro's sequence moves on with each cast
                spell = TotemTimers.GetCastMacroSpell()
                TotemTimers.UpdateCastMacroIcons()
            end
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
            TotemTimers.SetMultiCastMacro(TotemTimers.ActiveProfile.MultiCastMacro)
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
    if TotemTimers.ActiveProfile.MultiCastMacroButton then
        mb.actionBar:AddMacro(CAST_MACRO, TotemTimers.GetCastMacroTexture())
    end
end

-- the multicast button casts the TT Cast macro (on, with option MultiCastMacroButton) or its multicast spell; out of
-- combat
function TotemTimers.SetMultiCastMacro(on)
    if InCombatLockdown() then return end
    on = on and TotemTimers.ActiveProfile.MultiCastMacroButton
    if on then
        mb:SetAttribute("*type1", "macro")
        mb:SetAttribute("*macro1", CAST_MACRO)
        mb:SetAttribute("ttmacro", CAST_MACRO)
        mb:SetAttribute("*spell1", nil)
    elseif mb:GetAttribute("ttmacro") then
        mb:SetAttribute("ttmacro", nil)
        mb:SetAttribute("*macro1", nil)
        mb:SetAttribute("*type1", "spell")
        mb:SetAttribute("*spell1", TotemTimers.ActiveProfile.LastMultiCastSpell or SpellIDs.CallOfElements)
    end
end

-- icons of the macro (menu entry, multicast button in macro mode): the spell it casts next
local lastMacroTexture
function TotemTimers.UpdateCastMacroIcons()
    if not mb then return end
    local texture = TotemTimers.GetCastMacroTexture()
    -- a secret texture (in combat) is set every time
    if issecretvalue and issecretvalue(texture) then
        lastMacroTexture = nil
    elseif texture == lastMacroTexture then
        return
    else
        lastMacroTexture = texture
    end
    for _, button in ipairs(mb.actionBar.buttons) do
        if button:GetAttribute("ttmacro") then button.icon:SetTexture(texture) end
    end
    -- hooked by the gamepad bar slot (GamePadSlots.lua)
    if mb:GetAttribute("ttmacro") then mb:UpdateTexture() end
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
