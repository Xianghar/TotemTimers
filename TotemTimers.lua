-- Copyright © 2008 - 2014 Xianghar
-- All Rights Reserved.


--[[ Credits for localization go to
        Sayclub (koKR), StingerSoft (ruRU), a9012456 (zhTW),
        Sabre (zhCN), vanilla_snow (zhCN), tnt2ray (zhCN),
        Vante (esES), DonSlonik (ruRU), Оригинал (ruRU),
        natural_leaf (zhTW), ckeurk (frFR), oXid_FoX (frFR),
        Hemathio (ruRU), wowuicn (zhCN), laincat (zhTW),
        provirus111 (ruRU), lsjyzjl (zhCN), Rubapowa (esES),
        BNSSNB (zhTW), cebolaassassina (ptBR)
]]


if select(2,UnitClass("player")) ~= "SHAMAN" then return end

local _, TotemTimers = ...

local TotemSlotTimers = {}

local TotemTimersOnEvent = function(self, event, slot, ...)
	if (event == "PLAYER_TOTEM_UPDATE") then
		local _,_,startTime, duration, icon = GetTotemInfo(slot)
		if startTime then
			local timer = XiTimers.TextureToTimer[icon]
			if (timer and timer.active) then
				TotemSlotTimers[slot] = timer
				timer:Start(startTime, startTime + duration, true)
			end
		else
			if (timer and timer.active and timer.running and timer.buffIsActive) then
				timer:stop()
			end
			TotemSlotTimers[slot] = nil
		end
	else
		XiTimers.OnEvent(self, event, slot, ...)
	end
end

function XiTimers.CustomInit()
    XiTimers_Profiles = TotemTimers_Profiles
    XiTimers_GlobalSettings = TotemTimers_GlobalSettings

    --set the slashcommand
	SLASH_TOTEMTIMERS1 = "/totemtimers";
	SLASH_TOTEMTIMERS2 = "/tt";
	SlashCmdList["TOTEMTIMERS"] = XiTimers.Slash


	XiTimersFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
	XiTimersFrame:SetScript("OnEvent", TotemTimersOnEvent)
end
