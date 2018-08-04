-- Copyright © 2008 - 2012 Xianghar  <xian@zron.de>
-- All Rights Reserved.
-- This code is not to be modified or distributed without written permission by the author.
-- Current distribution permissions only include curse.com, wowinterface.com and their respective addon updaters

if select(2,UnitClass("player")) ~= "SHAMAN" then return end

local addonName, TotemTimers = ...

--local Timers = XiTimers.timers

--local SpellIDs = TotemTimers.SpellIDs
--local SpellNames = TotemTimers.SpellNames
--local AvailableSpells = TotemTimers.AvailableSpells


--local LSM = LibStub:GetLibrary("LibSharedMedia-3.0", true)

local TotemColors = {
    [AIR_TOTEM_SLOT] = {0.7,0.7,1.0},
    [WATER_TOTEM_SLOT] = {0.4,0.4,1.0},
    [FIRE_TOTEM_SLOT] = {1.0,0.1,0.1},
    [EARTH_TOTEM_SLOT] = {0.7,0.5,0.3},
}

local SettingsFunctions

local ShowTimersBars = XiTimers.Settings.ShowTimerBars
XiTimers.Settings.ShowTimerBars =
    function(value, Timers)
        ShowTimersBars(value, Timers)
        if TotemTimers.FlameshockBar then
            TotemTimers.FlameshockBar.visibleTimerBars = true
            TotemTimers.FlameshockBar:ShowTimerBar()
        end
    end
		


XiTimers.Settings.TimerTimeHeight =
        function(value, Timers)
			local fsnr = TotemTimers.FlameshockBar.nr
    		for e=1,#Timers do
				if fsnr ~= Timers[e].nr then
					Timers[e]:SetTimeHeight(value)
					Timers[e].button.time:SetFont(Timers[e].button.time:GetFont(),value+5,"OUTLINE")
				end
    		end  
			
        end
        
XiTimers.Settings.HideBlizzTimers =
        function(value)
            if value then
                TotemFrame:UnregisterEvent("PLAYER_TOTEM_UPDATE")
                TotemFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
                TotemFrame:SetScript("OnShow", function() TotemFrame:Hide() end)
                TotemFrame:Hide()
            else
                TotemFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
                TotemFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
                TotemFrame:Show()
                TotemFrame:SetScript("OnShow", TotemFrameScript)
            end
        end
            

    
    --[[ProcFlash =
        function(value, Timers)
            for i=1,#Timers do
                Timers[i].procFlash = value
            end
        end,]]
     


       
    --[[ BarBindings =
        function(value, Timers)
            for i=1,4 do
                for j=1,5 do
                    local key = GetBindingKey("TOTEMTIMERSCAST"..i..j)
                    if TotemTimers.ActiveProfile.BarBindings and not TotemTimers.ActiveProfile.MenusAlwaysVisible then
                        if TotemTimers.ActiveProfile.ReverseBarBindings then
                            getglobal("TT_ActionButton"..i..j.."HotKey"):SetText(key or tostring(10-j))
                            getglobal("TT_ActionButton"..i..j):SetAttribute("binding", tostring(10-j))
                        else
                            getglobal("TT_ActionButton"..i..j.."HotKey"):SetText(key or tostring(j))
                            getglobal("TT_ActionButton"..i..j):SetAttribute("binding", tostring(j))
                        end
                    else
                        getglobal("TT_ActionButton"..i..j.."HotKey"):SetText(key or "")
                        getglobal("TT_ActionButton"..i..j):SetAttribute("binding", nil)
                    end
                end
            end
        end, ]]--
 
        
    --[[ EnhanceCDsMaelstromHeight = 
        function(value, Timers)
			return
            TotemTimers.maelstrom:SetHeight(value)
            TotemTimers.maelstrom.background:SetHeight(value)
            TotemTimers.maelstrombutton:SetHeight(value)
            TotemTimers.maelstrom.icon:SetWidth(value)
            TotemTimers.maelstrom.icon:SetHeight(value)
            Timers[21]:SetScale(value/36)
            Timers[21]:SetTimeHeight(value)
            Timers[21].timerBars[1]:SetScale(36/value)
            local font = TotemTimers.maelstrom.text:GetFont()
            local outline
            if Timers[9].timerOnButton then outline = "OUTLINE" end
    		TotemTimers.maelstrom.text:SetFont(font, value, outline)
            local font, value = _G["XiTimers_TimerBar17_1Time"]:GetFont()
            _G["XiTimers_TimerBar17_1Time"]:SetFont(font, value, outline)
            TotemTimers.LayoutEnhanceCDs()
        end, ]]--

        
   --[[ ShowKeybinds =
        function(value, Timers)
            for _,t in pairs(Timers) do
                if value then
                    t.button.hotkey:Show()
                else
                    t.button.hotkey:Hide()
                end
            end
        end,]]
        

    --[[ ESMainTankMenuDirection =
        function(value, Timers) 
            TTActionBars.bars[5]:SetDirection(value, TotemTimers.ActiveProfile.TrackerArrange)
            --if #TTActionBars.bars > 5 then TotemTimers.ProcessSetting("MultiSpellBarDirection") end
        end,  ]] 
        
    --[[EnhanceCDsOOCAlpha = 
        function(value, Timers)
            for i = 1,#Timers do
                Timers[i].OOCAlpha = value
            end
            --TotemTimers.maelstrom:SetAlpha(value)
            XiTimers.invokeOOCFader()
        end,]]

local TimersOnButtons = XiTimers.Settings.TimersOnButtons
XiTimers.Settings.TimersOnButtons =
        function(value, Timers)
            TimersOnButtons(value, Timers)
			TotemTimers.FlameshockBar.timerOnButton = false
			if TotemTimers.FlameshockBar.timer > 0 then TotemTimers.FlameshockBar:Start(TotemTimers.FlameshockBar.timer, TotemTimers.FlameshockBar.duration) end
        end
    

        
    --[[EarthShieldTargetName =
        function(value, Timers)
            if value then
                Timers[7].nameframe:Show()
            else
                Timers[7].nameframe:Hide()
            end
        end,]]
        


XiTimers.Settings.MaelstromBar =
		function(value, Timers)
			if GetSpecialization() < 3 then
				if value then
					XiTimers.PowerBar.powerName = "MAELSTROM"
					XiTimers.PowerBar.powerIndex = SPELL_POWER_MAELSTROM
					XiTimers.PowerBar:enable()
				else
					XiTimers.PowerBar:disable()
				end
			end
		end
		
XiTimers.Settings.ManaBar =
		function(value, Timers)
			if GetSpecialization() == 3 then
				if value then
					XiTimers.PowerBar.powerName = "MANA"
					XiTimers.PowerBar.powerIndex = SPELL_POWER_MANA
					XiTimers.PowerBar:enable()
				else
					XiTimers.PowerBar:disable()
				end
			end
		end
        
XiTimers.Settings.FlameshockBar =
		function(value, Timers)
			if not TotemTimers.FlameshockBar then return end
			local role = GetSpecialization()
			if value and (role == 1) then
				TotemTimers.FlameshockBar:Activate()
			elseif role == 2 or not value then
				TotemTimers.FlameshockBar:Deactivate()
			end
		end
		
XiTimers.Settings.FlameshockBarRestoration =
		function(value, Timers)
			if not TotemTimers.FlameshockBar then return end
			if GetSpecialization() < 3 then return end
			if value then
				TotemTimers.FlameshockBar:Activate()
			else
				TotemTimers.FlameshockBar:Deactivate()
			end
		end
        
