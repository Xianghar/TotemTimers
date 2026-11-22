if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local _, TotemTimers = ...

-- Debug log for zone changes: which events fire around a loading screen, in which order, what the game's data reads
-- at each of them (specialization, instance type, profile, known totems, multicast slots), and what TotemTimers does
-- (spell/talent updates, timer totem updates, totem changes of the timer buttons, writes to multicast slots).
-- /ttzonelog on | off | clear | status. The log is kept in TotemTimers_GlobalSettings.ZoneLog (SavedVariables,
-- written on logout or /reload), at most MAX_LINES lines; it stays on across reloads until turned off.

local MAX_LINES = 5000

local EVENTS = {
    "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "PLAYER_LEAVING_WORLD", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA", "UPDATE_INSTANCE_INFO",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "CHARACTER_POINTS_CHANGED",
    "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "UPDATE_MULTI_CAST_ACTIONBAR", "ACTIONBAR_SLOT_CHANGED", "PLAYER_TOTEM_UPDATE",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local buffer = {} -- lines before the SavedVariables are loaded
local log
local enabled = false
local loaded = false -- SavedVariables loaded; before that everything is buffered
local startTime = GetTime()
local lastLoadingScreenEnd
local lastSnapshot

local function Settings()
    return TotemTimers_GlobalSettings
end

local function Active()
    return enabled or not loaded
end

local function Add(text)
    if not Active() then return end
    local since = lastLoadingScreenEnd and string.format(" +%.2f", GetTime() - lastLoadingScreenEnd) or ""
    local line = string.format("%.2f%s %s", GetTime() - startTime, since, text)
    local target = log or buffer
    table.insert(target, line)
    if #target > MAX_LINES then table.remove(target, 1) end
end

local function SafeName(spell)
    if not spell then return "nil" end
    local ok, name = pcall(C_Spell.GetSpellName, spell)
    if not ok or not name or (issecretvalue and issecretvalue(name)) then return tostring(spell) end
    return tostring(spell) .. ":" .. name
end

local function RawSpecialization()
    local parts = {}
    local specfunc = GetPrimaryTalentTree or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    if specfunc then
        local ok, spec = pcall(specfunc)
        table.insert(parts, "api=" .. tostring(ok and spec))
    end
    if GetTalentTabInfo then
        local points = {}
        for i = 1, 3 do
            local info = { pcall(GetTalentTabInfo, i) }
            local value
            if info[1] then
                -- the points spent are the 3rd (Wrath and later) or the 5th return value
                value = (LE_EXPANSION_LEVEL_CURRENT or 0) < (LE_EXPANSION_WRATH_OF_THE_LICH_KING or 2) and info[6] or info[4]
            end
            table.insert(points, tostring(value))
        end
        table.insert(parts, "points=" .. table.concat(points, "/"))
    end
    return table.concat(parts, " ")
end

local function ProfileName()
    local active = TotemTimers.ActiveProfile
    if not active or not TotemTimers_Profiles then return "nil" end
    for name, profile in pairs(TotemTimers_Profiles) do
        if profile == active then return tostring(name) end
    end
    return "?"
end

local function IsKnown(spell)
    if not spell then return "-" end
    local base = TotemTimers.GetBaseSpellID and TotemTimers.GetBaseSpellID(spell) or spell
    local avail = TotemTimers.AvailableSpells and TotemTimers.AvailableSpells[base]
    local fresh = type(base) == "number" and IsPlayerSpell(base)
    return string.format("base=%s avail=%s player=%s", tostring(base), tostring(avail), tostring(fresh))
end

local function MultiCastSlots(element)
    local parts = {}
    local actions = TotemTimers.MultiCastActions and TotemTimers.MultiCastActions[element]
    if not actions then return "" end
    local spells = {}
    for mspell in pairs(actions) do table.insert(spells, mspell) end
    table.sort(spells)
    local profile = TotemTimers.ActiveProfile
    for _, mspell in ipairs(spells) do
        local action = actions[mspell]
        local actionType, id = GetActionInfo(action)
        local disabled = profile and profile.DisabledMultiSpells
                and profile.DisabledMultiSpells[tostring(TotemTimers.Specialization) .. mspell .. element]
        table.insert(parts, string.format("m%d[%d]=%s%s", mspell, action,
                actionType == "spell" and SafeName(id) or tostring(actionType), disabled and "(x)" or ""))
    end
    return table.concat(parts, " ")
end

-- the game's and TotemTimers' state, logged when it differs from the last one
local function Snapshot()
    local lines = {}
    local _, instance = IsInInstance()
    table.insert(lines, string.format("  state: zoning=%s spec=%s %s instance=%s profile=%s",
            tostring(TotemTimers.IsZoning and TotemTimers.IsZoning()), tostring(TotemTimers.Specialization),
            RawSpecialization(), tostring(instance), ProfileName()))
    local multi = TotemTimers_MultiSpell
    if multi then
        table.insert(lines, string.format("  multicast: active=%s spell=%s", tostring(multi.active),
                SafeName(multi:GetAttribute("*spell1"))))
    end
    for element = 1, 4 do
        local timer = XiTimers and XiTimers.timers[element]
        if timer then
            local spell = timer.button:GetAttribute("*spell1")
            local saved = TotemTimers.ActiveProfile and TotemTimers.ActiveProfile.LastTotems
                    and TotemTimers.ActiveProfile.LastTotems[element]
            table.insert(lines, string.format("  e%d: timer=%s (%s) saved=%s mspell=%s | %s", element,
                    SafeName(spell), IsKnown(spell), SafeName(saved), tostring(timer.button:GetAttribute("mspell")),
                    MultiCastSlots(element)))
        end
    end
    local text = table.concat(lines, "\n")
    if text ~= lastSnapshot then
        lastSnapshot = text
        for _, line in ipairs(lines) do Add(line) end
    end
end

local function LogState(text)
    if not Active() then return end
    Add(text)
    if TotemTimers_IsSetUp then Snapshot() end
end

-- action slots of the multicast spells, only their slot changes are logged
local function IsMultiCastAction(slot)
    for _, actions in pairs(TotemTimers.MultiCastActions or {}) do
        for _, action in pairs(actions) do
            if action == slot then return true end
        end
    end
    return false
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon ~= "TotemTimers" then return end
        self:UnregisterEvent("ADDON_LOADED")
        loaded = true
        local settings = Settings()
        if settings and settings.ZoneLogEnabled then
            settings.ZoneLog = settings.ZoneLog or {}
            log = settings.ZoneLog
            enabled = true
            table.insert(log, "---- session " .. date("%Y-%m-%d %H:%M:%S"))
            for _, line in ipairs(buffer) do table.insert(log, line) end
        end
        wipe(buffer)
        return
    end
    if event == "LOADING_SCREEN_DISABLED" then lastLoadingScreenEnd = GetTime() end
    if not Active() then return end
    if event == "ACTIONBAR_SLOT_CHANGED" then
        local slot = ...
        if not IsMultiCastAction(slot) then return end
    end
    local args = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        args[i] = (issecretvalue and issecretvalue(value)) and "<secret>" or tostring(value)
    end
    LogState("EVENT " .. event .. (#args > 0 and " " .. table.concat(args, ", ") or ""))
end)
eventFrame:RegisterEvent("ADDON_LOADED")
for _, event in ipairs(EVENTS) do
    if C_EventUtils.IsEventValid(event) then eventFrame:RegisterEvent(event) end
end

-- TotemTimers' own actions (the functions are looked up as fields when called, so hooking the fields logs them)
local function ShortStack()
    local stack = debugstack(3, 3, 0) or ""
    stack = stack:gsub("Interface/AddOns/TotemTimers/", ""):gsub("\n", " < ")
    return stack
end

hooksecurefunc("SetMultiCastSpell", function(action, spell)
    if not Active() then return end
    LogState(string.format("WRITE SetMultiCastSpell(%s, %s) from %s", tostring(action), SafeName(spell), ShortStack()))
end)

local function HookField(name, describe)
    if type(TotemTimers[name]) ~= "function" then return end
    hooksecurefunc(TotemTimers, name, function(...)
        if not Active() then return end
        LogState("CALL " .. name .. (describe and " " .. describe(...) or ""))
    end)
end

-- after the setup: the totem changes of the timer buttons (UpdateMiniIconAndProfile runs on every *spell1 change)
local function HookTimerButtons()
    for element = 1, 4 do
        local timer = XiTimers.timers[element]
        if timer and timer.button.UpdateMiniIconAndProfile then
            hooksecurefunc(timer.button, "UpdateMiniIconAndProfile", function(button)
                if not Active() then return end
                LogState(string.format("TOTEM e%d -> %s (loading=%s) from %s", element,
                        SafeName(button:GetAttribute("*spell1")), tostring(TotemTimers.LoadingTotems), ShortStack()))
            end)
        end
    end
end

if TotemTimers.SetupGlobals then
    hooksecurefunc(TotemTimers, "SetupGlobals", function()
        HookField("ChangedTalents")
        HookField("SelectActiveProfile")
        HookField("UpdateTimerTotems")
        HookField("SetMultiCastConfig")
        HookField("UpdateTimerTotem", function(timer) return "e" .. tostring(timer and timer.nr) end)
        HookTimerButtons()
        LogState("SETUP done")
    end)
end

local function SetEnabled(on)
    local settings = Settings()
    if not settings then return end
    settings.ZoneLogEnabled = on or nil
    enabled = on
    if on then
        settings.ZoneLog = settings.ZoneLog or {}
        log = settings.ZoneLog
        table.insert(log, "---- enabled " .. date("%Y-%m-%d %H:%M:%S"))
        lastSnapshot = nil
        LogState("ENABLED")
    end
end

SLASH_TOTEMTIMERSZONELOG1 = "/ttzonelog"
SlashCmdList["TOTEMTIMERSZONELOG"] = function(msg)
    msg = strlower(strtrim(msg or ""))
    local settings = Settings()
    if msg == "on" then
        SetEnabled(true)
        print("TotemTimers zone log: on (saved on logout or /reload)")
    elseif msg == "off" then
        SetEnabled(false)
        print("TotemTimers zone log: off")
    elseif msg == "clear" then
        if settings then settings.ZoneLog = enabled and {} or nil end
        log = settings and settings.ZoneLog
        lastSnapshot = nil
        print("TotemTimers zone log: cleared")
    else
        print(string.format("TotemTimers zone log: %s, %d lines. /ttzonelog on | off | clear",
                enabled and "on" or "off", settings and settings.ZoneLog and #settings.ZoneLog or 0))
    end
end
