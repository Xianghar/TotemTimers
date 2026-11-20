if select(2, UnitClass("player")) ~= "SHAMAN" then return end

-- AceGUI widget "TotemTimers-ImageSelect": a select option (AceConfig type "select", dialogControl =
-- "TotemTimers-ImageSelect") shown as a row of large picture buttons instead of a dropdown. The pictures come from
-- the texture markup in the values ("|T<path>:<height>:<width>|t", several per value side by side), drawn PICTURE_SCALE
-- times larger; the selected button has a gold border. (The dropdown's list spaces its entries 16 px apart, too
-- small for pictures.)
-- A value can also be a composed picture (only for this widget, a dropdown can't show it), in units scaled by
-- PICTURE_SCALE, positions from the top left:
--   { width = w, height = h,
--     layers = { { texture = path or fileID, left = x, top = y, width = w, height = h }, ... },  -- drawn in order
--     texts = { { text = "5", left = x, top = y, width = w, height = h }, ... },                  -- centered, outlined
--     tooltip = "text" }  -- own tooltip of the entry instead of the option's description

local AceGUI = LibStub("AceGUI-3.0")

local Type, Version = "TotemTimers-ImageSelect", 4
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local PICTURE_SCALE = 2.5
local PADDING = 6 -- inside a button, around the pictures
local GAP = 4 -- between pictures of a button
local SPACING = 8 -- between buttons
local LABEL_HEIGHT = 18

local SELECTED_COLOR = { 1, 0.82, 0, 1 }
local BORDER_COLOR = { 0.4, 0.4, 0.4, 1 }

-- textures in a value's text: { path, width, height }
local function ParseTextures(text)
    local list = {}
    for path, height, width in tostring(text or ""):gmatch("|T([^:|]+):(%d+):?(%d*)[^|]*|t") do
        height = tonumber(height) or 16
        width = tonumber(width) or 0
        if height == 0 then height = 16 end
        if width == 0 then width = height end
        list[#list + 1] = { path = tonumber(path) or path, width = width, height = height }
    end
    return list
end

local function Button_OnClick(button)
    local self = button.obj
    if self.disabled then return end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    self:SetValue(button.value)
    self:Fire("OnValueChanged", button.value)
end

local function Button_OnEnter(button)
    if button.tooltip then
        GameTooltip:SetOwner(button, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(button.obj.label:GetText() or "", 1, 0.82, 0)
        GameTooltip:AddLine(button.tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    else
        button.obj:Fire("OnEnter")
    end
end

local function Button_OnLeave(button)
    if button.tooltip then
        GameTooltip:Hide()
    else
        button.obj:Fire("OnLeave")
    end
end

local function GetButton(self, index)
    local button = self.buttons[index]
    if button then return button end
    button = CreateFrame("Button", nil, self.frame, "BackdropTemplate")
    button.obj = self
    button:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 2 })
    button:SetBackdropColor(0, 0, 0, 0.5)
    button:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
    button:SetScript("OnClick", Button_OnClick)
    button:SetScript("OnEnter", Button_OnEnter)
    button:SetScript("OnLeave", Button_OnLeave)
    button.pictures = {}
    button.texts = {}
    self.buttons[index] = button
    return button
end

local function UpdateSelection(self)
    for _, button in ipairs(self.buttons) do
        if button:IsShown() then
            local color = button.value == self.value and SELECTED_COLOR or BORDER_COLOR
            button:SetBackdropBorderColor(unpack(color))
        end
    end
end

local function Rebuild(self)
    for _, button in ipairs(self.buttons) do
        button:Hide()
    end
    local list, order = self.list or {}, self.order
    if not order then
        order = {}
        for value in pairs(list) do order[#order + 1] = value end
        table.sort(order, function(a, b) return tostring(a) < tostring(b) end)
    end

    self.count = #order
    for index, value in ipairs(order) do
        local button = GetButton(self, index)
        button.value = value
        for _, picture in ipairs(button.pictures) do picture:Hide() end
        for _, text in ipairs(button.texts) do text:Hide() end
        local entry = list[value]
        button.tooltip = type(entry) == "table" and entry.tooltip or nil
        local width, height = 0, 0
        local textures = type(entry) == "table" and {} or ParseTextures(entry)
        if type(entry) == "table" then
            local scale = PICTURE_SCALE
            for i, layer in ipairs(entry.layers or {}) do
                local picture = button.pictures[i] or button:CreateTexture(nil, "ARTWORK")
                button.pictures[i] = picture
                picture:SetDrawLayer("ARTWORK", math.min(i, 7))
                picture:SetTexture(layer.texture)
                picture:SetTexCoord(0, 1, 0, 1)
                picture:SetSize(layer.width * scale, layer.height * scale)
                picture:ClearAllPoints()
                picture:SetPoint("TOPLEFT", button, "TOPLEFT", PADDING + layer.left * scale, -PADDING - layer.top * scale)
                picture:Show()
            end
            for i, info in ipairs(entry.texts or {}) do
                local text = button.texts[i]
                if not text then
                    text = button:CreateFontString(nil, "OVERLAY")
                    button.texts[i] = text
                end
                local font = GameFontHighlight:GetFont()
                text:SetFont(font, math.max(6, info.height * scale), "OUTLINE")
                text:SetTextColor(1, 1, 1)
                text:SetJustifyH("CENTER")
                text:SetJustifyV("MIDDLE")
                text:SetSize(info.width * scale, info.height * scale)
                text:ClearAllPoints()
                text:SetPoint("TOPLEFT", button, "TOPLEFT", PADDING + info.left * scale, -PADDING - info.top * scale)
                text:SetText(info.text)
                text:Show()
            end
            width = entry.width * scale
            height = entry.height * scale
        end
        for i, tex in ipairs(textures) do
            local picture = button.pictures[i] or button:CreateTexture(nil, "ARTWORK")
            button.pictures[i] = picture
            local w, h = tex.width * PICTURE_SCALE, tex.height * PICTURE_SCALE
            picture:SetTexture(tex.path)
            picture:SetSize(w, h)
            picture:ClearAllPoints()
            picture:SetPoint("LEFT", button, "LEFT", PADDING + width + (i > 1 and GAP * (i - 1) or 0), 0)
            picture:Show()
            width = width + w
            height = math.max(height, h)
        end
        width = width + GAP * math.max(#textures - 1, 0) + PADDING * 2
        height = height + PADDING * 2
        button:SetSize(width, height)
        button:Show()
    end
    self:LayoutButtons()
    UpdateSelection(self)
    self:SetDisabled(self.disabled)
end

-- the buttons in rows, as many per row as fit the widget's width (a new row when the next one doesn't fit); buttons
-- of different heights are centered on their row; the widget's height follows the rows
local function LayoutButtons(self)
    local available = self.frame:GetWidth()
    if not available or available <= 0 then available = math.huge end
    local rows, row = {}, nil
    local x = 0
    for index = 1, self.count or 0 do
        local button = self.buttons[index]
        local width = button:GetWidth()
        if not row or (x > 0 and x + width > available) then
            row = { height = 0 }
            rows[#rows + 1] = row
            x = 0
        end
        button.x = x
        row[#row + 1] = button
        row.height = math.max(row.height, button:GetHeight())
        x = x + width + SPACING
    end
    local y = LABEL_HEIGHT
    for _, r in ipairs(rows) do
        for _, button in ipairs(r) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", button.x, -y - (r.height - button:GetHeight()) / 2)
        end
        y = y + r.height + SPACING
    end
    self:SetHeight(y - (#rows > 0 and SPACING or 0) + 4)
end

local methods = {
    LayoutButtons = LayoutButtons,

    -- AceGUI: the container set a new width (e.g. "fill"), the rows are laid out again
    OnWidthSet = function(self, width)
        if self.count then LayoutButtons(self) end
    end,

    OnAcquire = function(self)
        self:SetWidth(200)
        self.disabled = false
        self.value = nil
        self.list = nil
        self.order = nil
        self.count = nil
        self:SetLabel("")
    end,

    OnRelease = function(self)
        for _, button in ipairs(self.buttons) do
            button:Hide()
        end
    end,

    SetLabel = function(self, text)
        self.label:SetText(text or "")
    end,

    -- AceConfigDialog: SetList(values, sorting, itemType)
    SetList = function(self, list, order)
        self.list = list
        self.order = order
        Rebuild(self)
    end,

    AddItem = function(self, value, text)
        self.list = self.list or {}
        self.list[value] = text
        if self.order then self.order[#self.order + 1] = value end
        Rebuild(self)
    end,

    SetValue = function(self, value)
        self.value = value
        UpdateSelection(self)
    end,

    GetValue = function(self)
        return self.value
    end,

    SetDisabled = function(self, disabled)
        self.disabled = disabled and true or false
        for _, button in ipairs(self.buttons) do
            button:SetEnabled(not self.disabled)
            button:SetAlpha(self.disabled and 0.5 or 1)
        end
        if self.disabled then
            self.label:SetTextColor(0.5, 0.5, 0.5)
        else
            self.label:SetTextColor(1, 0.82, 0)
        end
    end,

    -- dropdown interface, not used here
    SetMultiselect = function() end,
    GetMultiselect = function() return false end,
    SetItemValue = function() end,
    SetItemDisabled = function() end,
    SetText = function() end,
    ClearFocus = function() end,
}

local function Constructor()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
    label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -2)
    label:SetJustifyH("LEFT")
    label:SetHeight(LABEL_HEIGHT - 4)

    local widget = {
        frame = frame,
        label = label,
        buttons = {},
        type = Type,
    }
    for name, method in pairs(methods) do
        widget[name] = method
    end
    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
