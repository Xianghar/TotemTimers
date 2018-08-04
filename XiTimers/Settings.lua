-- Copyright © 2008 - 2016 Xianghar  <xian@zron.de>
-- All Rights Reserved.
-- This code is not to be modified or distributed without written permission by the author.
-- Current distribution permissions only include curse.com, wowinterface.com and their respective addon updaters

local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

local Timers = XiTimers.timers

local LSM = LibStub:GetLibrary("LibSharedMedia-3.0", true)
local libmov = LibStub:GetLibrary("LibMovable-1.0")

local SettingsFunctions



function XiTimers.ProcessSetting(setting)
    if SettingsFunctions[setting] then
        SettingsFunctions[setting](XiTimers.ActiveProfile[setting], XiTimers.timers)
    end
end


function XiTimers.ProcessAllSettings()
    for k,v in pairs(XiTimers.ActiveProfile) do
        XiTimers.ProcessSetting(k)
    end
end


SettingsFunctions = {

    ShowTimerBars = 
        function(value, Timers) 
            for _,timer in pairs(Timers) do
				timer.visibleTimerBars = value
				if timer.timer>0 and value and not timer.timerOnButton then
					timer:ShowTimerBar()
				else
					timer.timerBar.background:Hide()
					timer.timerBar:SetValue(0)			
				end
            end
        end,
		

    FlashRed = 
        function(value, Timers)
        	for _,timer in pairs(Timers) do
                timer.flashRed = value
            end
        end,
        
    TimerSize = 
        function(value, Timers)
            local v = value
    		for e=1,#Timers do
    			Timers[e]:SetScale(v/36)
    		end
        end,
        
    TimerTimeHeight =
        function(value, Timers)
    		for e=1,#Timers do
				Timers[e]:SetTimeHeight(value)
				Timers[e].button.time:SetFont(Timers[e].button.time:GetFont(),value+5,"OUTLINE")
			end
        end,
        
       
    TimerSpacing = 
        function(value, Timers)
    		for e=1,#Timers do
    			Timers[e]:SetSpacing(value)
    		end
        end,
        
        
    TimerTimeSpacing = 
        function(value, Timers)
    		for e=1,#Timers do
				Timers[e]:SetTimeSpacing(value)
    		end
        end,
        
    TimerTimePos = 
        function(value, Timers)
    		for e=1,#Timers do
				Timers[e]:SetTimerBarPos(value)
    		end  
        end,
		
	TimeStyle =
		function(value, Timers)
			for i=1,#Timers do
				Timers[i].timeStyle = value
			end
		end,
       

		
	ActionBarButtonPosition =
		function(value, Timers)
			for i=1,#XiTimers.actionBars do
				XiTimers.actionBars[i].position = value[i]
			end
		end,
        
     
    TimeFont =
        function(value, Timers)
            local font = LSM:Fetch("font", value)
            if font then
                for _,timer in pairs(Timers) do
                    timer:SetFont(font)
                end
            end
        end,
        
    TimerBarTexture =
        function(value, Timers) 
            local texture = LSM:Fetch("statusbar", value)
            if texture then
                for _,timer in pairs(Timers) do
                    timer:SetBarTexture(texture)
                end
            end
        end,
		
	TimerBarColor =
        function(value, Timers)
            for i=1,#Timers do
               Timers[i]:SetBarColor(value.r,value.g,value.b,value.a)
            end
        end,
		
	BuffBarColor = 
        function(value, Timers)
            for i=1,#Timers do
               Timers[i].button.bar:SetStatusBarColor(value.r,value.g,value.b,value.a)
            end
        end,	
        
       
    Tooltips =  
        function(value, Timers)
            for i=1,#Timers do
				if value then
					Timers[i].button:SetAttribute("_onenter", [[ control:CallMethod("ShowTooltip")]])
					Timers[i].button:SetAttribute("_onleave", [[ control:CallMethod("HideTooltip")]])
				else
					Timers[i].button:SetAttribute("_onenter", nil)
					Timers[i].button:SetAttribute("_onleave", nil)
				end
            end
        end,
		
	TooltipsAtButtons = 
		function(value, Timers)
			XiTimers.TooltipsAtButtons = value
		end,

        
    --[[ShowKeybinds =
        function(value, Timers)
            for _,t in pairs(Timers) do
                if value then
                    t.button.hotkey:Show()
                else
                    t.button.hotkey:Hide()
                end
            end
        end,]]
        
        
    TimersOnButtons = 
        function(value, Timers)
            for i=1,#Timers do
                Timers[i].timerOnButton = value
                if Timers[i].timer > 0 then Timers[i]:Start(Timers[i].timer, Timers[i].duration) end
            end
       end,
    
    TimeColor = 
        function(value, Timers)
            for i=1,#Timers do
                Timers[i].button.time:SetTextColor(value.r, value.g, value.b, 1)
				Timers[i].timerBar.time:SetTextColor(value.r,value.g,value.b,1)
            end
        end,
        
   
    HideInVehicle = 
        function(value, Timers)
            if value then
                for k,v in pairs(Timers) do
                    RegisterStateDriver(v.button,"invehicle","[bonusbar:5]hide;show")
                end
            else
                for k,v in pairs(Timers) do
                    UnregisterStateDriver(v.button,"invehicle")
                end
            end
        end,
   
    StopPulse =
        function(value, Timers)
            for i = 1,#Timers do
                Timers[i].StopPulse = value
            end
        end,
        
    HideOOC =
        function(value, Timers)
            for i = 1,#Timers do
                Timers[i].HideOOC = value
				Timers[i].button:SetAttribute("HideOOC", value)
				if not InCombatLockdown() then
					if value then
						for i=1,#Timers do
							Timers[i].button:Hide()
						end
					else
						for i=1,#Timers do
							Timers[i].button:Show()
						end
					end
				end
            end
        end,
        
    Clickthrough = 
        function(value, Timers)
            for i = 1,#Timers do
				Timers[i]:Clickthrough(value)
            end
        end,
		
	PowerBarSize = 
		function(value)	
			if XiTimers.PowerBar then
				local scale = XiTimers.ActiveProfile.Anchors.XiTimers_PowerBar.scale
				if not scale then scale = 1 end
				XiTimers.ActiveProfile.Anchors.XiTimers_PowerBar.scale = value
				if XiTimers.ActiveProfile.Anchors.XiTimers_PowerBar.xOffset then 
					XiTimers.ActiveProfile.Anchors.XiTimers_PowerBar.xOffset = 
						XiTimers.ActiveProfile.Anchors.XiTimers_PowerBar.xOffset * scale / value
				end
				if XiTimers.ActiveProfile.Anchors.XiTimers_PowerBar.yOffset then
					XiTimers.ActiveProfile.Anchors.XiTimers_PowerBar.yOffset = 
						XiTimers.ActiveProfile.Anchors.XiTimers_PowerBar.yOffset * scale / value
				end
				libmov.UpdateMovableLayout("XiTimers")
			end
		end,
		
	PowerBarWidth =
		function(value)
			if XiTimers.PowerBar then
				XiTimers.PowerBar:SetWidth(value)
			end
		end,
		
	PowerBarFontSize =
		function(value)
			if XiTimers.PowerBar then
				XiTimers.PowerBar.text:SetTextHeight(value)
			end
		end,
		
	PowerBarFontColor = 
		function(value)
			if XiTimers.PowerBar then
				XiTimers.PowerBar.text:SetTextColor(value.r, value.g, value.b, 1)
			end
		end,
		
	PowerBarTexture =
		function(value)
			if XiTimers.PowerBar then
				local texture = LSM:Fetch("statusbar", value)
				if texture then
					XiTimers.PowerBar:SetStatusBarTexture(texture)
					--XiTimers.PowerBar.background:SetStatusBarTexture(texture)
				end
			end
		end,
		
	PowerBarFont = 
		function(value)
			if XiTimers.PowerBar then
				local font = LSM:Fetch("font", value)
				if font then
					XiTimers.PowerBar.text:SetFont(font, XiTimers.ActiveProfile.PowerBarFontSize)                
				end
			end
		end,
		
	PowerBarOOCAlpha =
		function(value)
			if XiTimers.PowerBar then
				XiTimers.PowerBar.OOCAlpha = value
				XiTimers.invokeOOCFader()
			end
		end,
		
	ActiveCooldownAlpha =
		function(value, Timers)			
			for i=1,#Timers do
				XiTimers.activeCooldownAlpha = value
			end
		end,
	
}

XiTimers.Settings = SettingsFunctions


