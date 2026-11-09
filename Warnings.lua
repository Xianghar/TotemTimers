if select(2,UnitClass("player")) ~= "SHAMAN" then return end

local L = LibStub("AceLocale-3.0"):GetLocale("TotemTimers", true)
local LSM = LibStub:GetLibrary("LibSharedMedia-3.0", true)

local Warnings = TotemTimers.DefaultProfile.Warnings

local lastWarning = nil
local lastWarningTime = nil

function XiTimers.InitWarnings(newwarnings)
    Warnings = newwarnings
end

local noTextWarnings = { "Maelstrom", "PowerSurge"}


function XiTimers.PlayWarning(self, warning, spell, icon)
    if not Warnings[warning] or not Warnings[warning].enabled or (warning == lastWarning and GetTime()-lastWarningTime < 1) then return end
    lastWarning = warning
    lastWarningTime = GetTime()
    if not noTextWarnings[warning] then
        local text = L[Warnings[warning].text]
        if spell then text = string.format(text,spell) end
        TotemTimers.Pour(text, Warnings[warning].r, Warnings[warning].g, Warnings[warning].b, icon)
    end
    local sound = LSM:Fetch("sound", Warnings[warning].sound)
    if sound then PlaySoundFile(sound, "Master") end
end
