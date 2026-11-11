if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local _, TotemTimers = ...

-- Tutorial for the Gamepad UI integration (GamePad.lua).
-- On login or UI reload with the Gamepad UI enabled, a prompt asks whether the tutorial should be shown.
-- The tutorial is a dialog with one page per step (STEPS) and Back/Next buttons. While it runs, the layer key is
-- LT + RT (GamePad.SetLayerKeyOverride, not saved in the profile); the setting is in use again when it ends.
--
-- The dialogs are own frames, not StaticPopups: an addon-defined StaticPopup taints the Gamepad UI's frame focus
-- handling when it closes (ADDON_ACTION_FORBIDDEN on SetPreferredGamepadInteractTarget). The pad buttons are bound
-- to the dialog buttons by priority override bindings while a dialog is shown (out of combat only; the dialogs
-- close when combat starts, while the bindings can still be cleared).

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers", true)

local GamePadTutorial = {}
TotemTimers.GamePadTutorial = GamePadTutorial

local WIDTH = 420
local TEXT_WIDTH = 360
local TEXT_TOP = 36
local BUTTON_WIDTH = 180
local BUTTON_HEIGHT = 30
local BUTTON_BOTTOM = 20
local ICON_SIZE = 24 -- 0.8 of the button height, like the Gamepad UI's icons on dialog buttons
local ICON_GAP = 3
-- the newer controller prompt atlases (76x75) have extra padding, Blizzard enlarges them by 5 on each side
local LARGE_ATLAS_WIDTH, LARGE_ATLAS_HEIGHT, LARGE_ATLAS_PADDING = 76, 75, 5

-- pages of the tutorial, in order; text: localization key, optional OnEnter/OnLeave(step) for later steps
-- anchor "bar": the window is placed above the Gamepad UI action bar of the trigger button (LT + RT bar)
-- arrow (only with anchor "bar"): green arrow pointing down, "window" below the window's bottom center,
-- "totems" at the face button slots, "dpad" at the d-pad slots of the bar
local STEPS = {
    { text = "GamePad Tutorial Intro" },
    { text = "GamePad Tutorial Bar", anchor = "bar", arrow = "window" },
    { text = "GamePad Tutorial Totem Buttons", anchor = "bar", arrow = "totems" },
    { text = "GamePad Tutorial DPad Buttons", anchor = "bar", arrow = "dpad" },
    { text = "GamePad Tutorial Totem Wheel", anchor = "bar", arrow = "totems",
      OnEnter = function() GamePadTutorial.ShowEarthWheel() end,
      OnLeave = function() TotemTimers.GamePad.HideDemoWheel() end },
    -- the wheel left open after a release without a selected totem
    { text = "GamePad Tutorial Sticky Wheel", anchor = "bar",
      OnEnter = function() GamePadTutorial.ShowEarthWheel(true) end,
      OnLeave = function() TotemTimers.GamePad.HideDemoWheel() end },
    { text = "GamePad Tutorial Multicast Wheel", anchor = "bar", arrow = "dpadright",
      OnEnter = function() GamePadTutorial.ShowMulticastWheel() end,
      OnLeave = function() TotemTimers.GamePad.HideDemoWheel() end },
}

-- the radial menu of d-pad right: the three multicast spells (also if the player doesn't know them yet)
local MULTICAST_WHEEL_SPELLS = { "CallOfElements", "CallOfAncestors", "CallOfSpirits" }

function GamePadTutorial.ShowMulticastWheel()
    local spells = {}
    for _, key in ipairs(MULTICAST_WHEEL_SPELLS) do
        table.insert(spells, TotemTimers.SpellIDs[key] or false)
    end
    TotemTimers.GamePad.ShowDemoWheel(spells, "PADDRIGHT", _G.TotemTimers_GamePadTutorial, false, true)
end

-- the radial menu of the earth totems as an example: always these five totems (also if the player doesn't know
-- them yet) and the destroy segment
local EARTH_WHEEL_TOTEMS = { "Stoneskin", "EarthBind", "Stoneclaw", "StrengthOfEarth", "Tremor" }

-- sticky: as left open after the release
function GamePadTutorial.ShowEarthWheel(sticky)
    local spells = {}
    for _, key in ipairs(EARTH_WHEEL_TOTEMS) do
        table.insert(spells, TotemTimers.SpellIDs[key] or false)
    end
    -- beside the tutorial window (created later in this file)
    TotemTimers.GamePad.ShowDemoWheel(spells, "PAD1", _G.TotemTimers_GamePadTutorial, sticky)
end
local BAR_GAP = 56 -- between the action bar and the window, room for the arrow and the slots' overlays
local ARROW_SIZE = 48
local ARROW_BOUNCE = 8

----------------------------------------------------------------------------------------------------------------
-- dialog frames

-- atlas of a pad button's icon in the active controller's icon set
local function GetPadIconAtlas(key)
    local util = InputIconTextureSetUtility
    if not (util and util.GetNormalActiveInputIconButtonTexture and InputDeviceIconVariant) then return end
    local ok, atlas = pcall(util.GetNormalActiveInputIconButtonTexture, key, InputDeviceIconVariant.Standard)
    return ok and atlas or nil
end

-- texts name pad buttons as {KEY} (binding key, e.g. {PADLTRIGGER}), shown as the icon of the active controller
local TEXT_ICON_SIZE = 20
local TEXT_ICON_OFFSET_Y = -4

local function GetPadIconText(key)
    local atlas = GetPadIconAtlas(key)
    local info = atlas and C_Texture.GetAtlasInfo(atlas)
    if info then
        local size = TEXT_ICON_SIZE
        if info.width == LARGE_ATLAS_WIDTH and info.height == LARGE_ATLAS_HEIGHT then
            size = math.floor(size * (1 + 2 * LARGE_ATLAS_PADDING / ICON_SIZE) + 0.5)
        end
        -- inline textures sit above the text's center, moved down to line up with it
        return CreateAtlasMarkup(atlas, size, size, 0, TEXT_ICON_OFFSET_Y)
    end
    return TotemTimers.GamePad.GetPadIconMarkup(key) or GetBindingText(key)
end

-- {spell:Name}: name of TotemTimers.SpellIDs.Name in the client's language
local function GetSpellText(key)
    local spellID = TotemTimers.SpellIDs[key]
    return spellID and C_Spell.GetSpellName(spellID) or key
end

local function FormatPadText(text)
    text = text:gsub("{(PAD[%w]+)}", GetPadIconText)
    return (text:gsub("{spell:(%w+)}", GetSpellText))
end

-- icon of the active controller's icon set (set on each show, the controller can change)
local function UpdateButtonIcon(button)
    local fontString = button:GetFontString()
    local atlas = GetPadIconAtlas(button.key)
    local info = atlas and C_Texture.GetAtlasInfo(atlas)
    fontString:ClearAllPoints()
    if info then
        button:SetText(button.label)
        local size = ICON_SIZE
        if info.width == LARGE_ATLAS_WIDTH and info.height == LARGE_ATLAS_HEIGHT then
            size = size + 2 * LARGE_ATLAS_PADDING
        end
        button.icon:SetAtlas(atlas)
        button.icon:SetSize(size, size)
        button.icon:ClearAllPoints()
        button.icon:SetPoint("CENTER", fontString, "LEFT", -ICON_GAP - ICON_SIZE / 2, 0)
        button.icon:SetDesaturated(not button:IsEnabled())
        button.icon:Show()
        fontString:SetPoint("CENTER", button, "CENTER", (ICON_SIZE + ICON_GAP) / 2, 1)
    else
        -- fallback: inline icon of the binding string
        button.icon:Hide()
        local markup = TotemTimers.GamePad.GetPadIconMarkup(button.key)
        button:SetText(markup and (markup .. " " .. button.label) or button.label)
        fontString:SetPoint("CENTER", button, "CENTER", 0, 1)
    end
end

local function SetButtonLabel(button, label)
    button.label = label
    UpdateButtonIcon(button)
end

local function SetButtonEnabled(button, enabled)
    button:SetEnabled(enabled)
    button.icon:SetDesaturated(not enabled)
end

-- dialog button in the style of the game's dialogs (StaticPopupButtonTemplate): red button, gold text and
-- the icon of its pad button (key) left of the text. Built from plain textures, the template isn't used to keep
-- its mixins out of addon code. The pad button clicks it while the dialog is shown.
local function CreateDialogButton(dialog, name, key, label, onClick)
    local button = CreateFrame("Button", name, dialog)
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:RegisterForClicks("LeftButtonUp")
    button:SetNormalTexture("Interface\\Buttons\\UI-DialogBox-Button-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-DialogBox-Button-Down")
    button:SetDisabledTexture("Interface\\Buttons\\UI-DialogBox-Button-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-DialogBox-Button-Highlight", "ADD")
    for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetDisabledTexture(),
                               button:GetHighlightTexture() }) do
        texture:SetTexCoord(0, 1, 0, 0.71875)
    end
    button:SetNormalFontObject(GameFontNormalLarge)
    button:SetHighlightFontObject(GameFontHighlightLarge)
    button:SetDisabledFontObject(GameFontDisableLarge)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    button.key = key
    button.label = label
    button.icon = button:CreateTexture(nil, "OVERLAY")
    dialog.buttons[key] = button
    return button
end

-- dialog with the tutorial's caption, a text and two buttons at the bottom (added by CreateDialogButton)
local function CreateDialog(name)
    local dialog = CreateFrame("Frame", name, UIParent)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:EnableMouse(true)
    dialog:SetClampedToScreen(true)
    dialog:SetWidth(WIDTH)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    dialog:Hide()
    dialog.buttons = {}

    local border = CreateFrame("Frame", nil, dialog, "DialogBorderTemplate")
    border:SetAllPoints()

    local header = CreateFrame("Frame", nil, dialog, "DialogHeaderTemplate")
    header:Setup(L["GamePad Tutorial Title"])

    dialog.text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    dialog.text:SetWidth(TEXT_WIDTH)
    dialog.text:SetPoint("TOP", 0, -TEXT_TOP)

    dialog:SetScript("OnShow", function(self)
        for key, button in pairs(self.buttons) do
            UpdateButtonIcon(button)
            SetOverrideBindingClick(self, true, key, button:GetName(), "LeftButton")
        end
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
    end)
    dialog:SetScript("OnHide", function(self)
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        if not InCombatLockdown() then
            ClearOverrideBindings(self)
        end
        if self.OnClose then self:OnClose() end
    end)
    -- PLAYER_REGEN_DISABLED fires before the combat lockdown starts, the bindings can still be cleared
    dialog:SetScript("OnEvent", function(self)
        self:Hide()
    end)
    return dialog
end

-- height for the text, extra: space between the text and the buttons
local function FitHeight(dialog, extra)
    dialog:SetHeight(TEXT_TOP + dialog.text:GetStringHeight() + (extra or 24) + BUTTON_HEIGHT + BUTTON_BOTTOM)
end

----------------------------------------------------------------------------------------------------------------
-- tutorial

local tutorial, backButton, nextButton
local currentStep

local function LeaveStep()
    local step = currentStep and STEPS[currentStep]
    if step and step.OnLeave then step.OnLeave(step) end
end

-- slot of the bar the arrow points at (top button of the face button or d-pad cluster)
local function GetArrowSlot(bar, arrow)
    local GamePad = TotemTimers.GamePad
    local index = (arrow == "totems" and GamePad.FaceButtonIndices.PAD4)
            or (arrow == "dpad" and GamePad.OPEN_BUTTON_INDEX)
            or (arrow == "dpadright" and GamePad.DPAD_RIGHT_INDEX)
    return index and bar:GetActionButtonByIndex(index)
end

local function PositionTutorial(step)
    tutorial:ClearAllPoints()
    local bar = step.anchor == "bar" and TotemTimers.GamePad.GetLayerKeyBar()
    if bar then
        tutorial:SetPoint("BOTTOM", bar, "TOP", 0, BAR_GAP)
    else
        tutorial:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end

    local arrow = tutorial.arrow
    arrow:ClearAllPoints()
    local slot = bar and GetArrowSlot(bar, step.arrow)
    if bar and step.arrow == "window" then
        arrow:SetPoint("TOP", tutorial, "BOTTOM", 0, 0)
    elseif slot then
        arrow:SetPoint("BOTTOM", slot, "TOP", 0, ARROW_BOUNCE)
    else
        arrow:Hide()
        return
    end
    arrow:Show()
end

local function ShowStep(index)
    LeaveStep()
    currentStep = index
    local step = STEPS[index]
    PositionTutorial(step)
    tutorial.text:SetText(FormatPadText(L[step.text]))
    tutorial.counter:SetFormattedText("%d / %d", index, #STEPS)
    SetButtonEnabled(backButton, index > 1)
    SetButtonLabel(nextButton, index < #STEPS and NEXT or DONE)
    FitHeight(tutorial, 36)
    if step.OnEnter then step.OnEnter(step) end
end

local function CreateTutorial()
    tutorial = CreateDialog("TotemTimers_GamePadTutorial")
    -- the steps have lists of buttons
    tutorial.text:SetJustifyH("LEFT")
    tutorial.text:SetSpacing(4)

    -- green arrow pointing down, bouncing; a frame of its own above the window (it can overlap it)
    local arrow = CreateFrame("Frame", nil, tutorial)
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetFrameLevel(tutorial:GetFrameLevel() + 20)
    local texture = arrow:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetAtlas("NPE_ArrowDown")
    texture:SetDesaturated(true)
    texture:SetVertexColor(0.2, 1, 0.2)
    local bounce = arrow:CreateAnimationGroup()
    bounce:SetLooping("BOUNCE")
    local move = bounce:CreateAnimation("Translation")
    move:SetOffset(0, -ARROW_BOUNCE)
    move:SetDuration(0.5)
    move:SetSmoothing("IN_OUT")
    arrow:SetScript("OnShow", function() bounce:Play() end)
    arrow:SetScript("OnHide", function() bounce:Stop() end)
    arrow:Hide()
    tutorial.arrow = arrow

    tutorial.counter = tutorial:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tutorial.counter:SetPoint("BOTTOM", 0, BUTTON_BOTTOM + BUTTON_HEIGHT + 10)

    backButton = CreateDialogButton(tutorial, "TotemTimers_GamePadTutorialBack", "PAD2", BACK, function()
        if currentStep > 1 then ShowStep(currentStep - 1) end
    end)
    backButton:SetPoint("BOTTOMRIGHT", tutorial, "BOTTOM", -8, BUTTON_BOTTOM)

    nextButton = CreateDialogButton(tutorial, "TotemTimers_GamePadTutorialNext", "PAD1", NEXT, function()
        if currentStep < #STEPS then
            ShowStep(currentStep + 1)
        else
            tutorial:Hide()
        end
    end)
    nextButton:SetPoint("BOTTOMLEFT", tutorial, "BOTTOM", 8, BUTTON_BOTTOM)

    -- also closed by entering combat; the layer key setting is in use again
    tutorial.OnClose = function()
        LeaveStep()
        currentStep = nil
        TotemTimers.GamePad.SetLayerKeyOverride(nil)
    end
end

function GamePadTutorial.Start()
    -- the bindings and the layer key can't be changed in combat
    if InCombatLockdown() then return end
    if not tutorial then CreateTutorial() end
    if GamePadTutorial.prompt then GamePadTutorial.prompt:Hide() end

    -- the options would cover the tutorial
    LibStub("AceConfigDialog-3.0"):Close("TotemTimers")
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end

    TotemTimers.GamePad.SetLayerKeyOverride(TotemTimers.GamePad.BOTH_TRIGGERS)
    tutorial:Hide()
    tutorial:Show()
    ShowStep(1)
end

----------------------------------------------------------------------------------------------------------------
-- prompt on login

local function CreatePrompt()
    local prompt = CreateDialog("TotemTimers_GamePadTutorialPrompt")

    local yes = CreateDialogButton(prompt, "TotemTimers_GamePadTutorialPromptYes", "PAD1", YES, function()
        prompt:Hide()
        GamePadTutorial.Start()
    end)
    yes:SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -8, BUTTON_BOTTOM)

    local no = CreateDialogButton(prompt, "TotemTimers_GamePadTutorialPromptNo", "PAD2", NO, function()
        prompt:Hide()
    end)
    no:SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 8, BUTTON_BOTTOM)

    prompt:HookScript("OnShow", function(self)
        self.text:SetText(FormatPadText(L["GamePad Tutorial Prompt"]))
        FitHeight(self)
    end)
    GamePadTutorial.prompt = prompt
end

local eventFrame = CreateFrame("Frame")

function GamePadTutorial.ShowPrompt()
    if InCombatLockdown() then
        -- the override bindings can't be set in combat
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if tutorial and tutorial:IsShown() then return end
    if not GamePadTutorial.prompt then CreatePrompt() end
    GamePadTutorial.prompt:Hide()
    GamePadTutorial.prompt:Show()
end

local function ShowPromptIfGamepadUI()
    if TotemTimers.GamePad and TotemTimers.GamePad.IsGamepadUI() then
        GamePadTutorial.ShowPrompt()
    end
end

-- also on a UI reload: enabling the Gamepad UI reloads the UI
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, isLogin, isReload)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        ShowPromptIfGamepadUI()
        return
    end
    if not (isLogin or isReload) then return end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- wait until the loading screen and the login popups have settled
    C_Timer.After(2, ShowPromptIfGamepadUI)
end)
