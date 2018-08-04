local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

local frame = CreateFrame("Frame", "XiTimersFrame", UIParent)
frame:Show()

function XiTimers.OnEvent(self, event, ...) 
    if zoning and event ~= "PLAYER_ENTERING_WORLD" then return
	elseif event == "UNIT_AURA" and select(1, ...) == "player" then
		XiTimers.updateAuras = true
	elseif event == "PLAYER_ENTERING_WORLD" then 
        if zoning then
            XiTimersFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            zoning = false
            return
        end
		XiTimers.Init()
    elseif event == "LEARNED_SPELL_IN_TAB" then 
        if InCombatLockdown() then
			updateAfterCombat = true
		else
			XiTimers.LearnedSpell(...)
		end
    elseif event == "PLAYER_REGEN_ENABLED" then
		if updateAfterCombat then
			XiTimers.ChangedTalents()
			updateAfterCombat = false
		end
	elseif event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then 
		if InCombatLockdown() then
			updateAfterCombat = true
		else
			XiTimers.ChangedTalents()        
		end
    elseif event == "PLAYER_LEAVING_WORLD" then
        zoning = true
        XiTimersFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	elseif event == "SPELL_PUSH_TO_ACTIONBAR" then
		XiTimers.IntroAnimation(...)
	end   
end

frame:SetScript("OnEvent", XiTimers.OnEvent)
frame:RegisterEvent("PLAYER_ENTERING_WORLD")


function XiTimers.Init()
	if XiTimers.IsSetUp then
		return
	end
	
	if XiTimers.CustomInit then XiTimers.CustomInit() end

	XiTimers.UpdateProfiles()
	XiTimers.SelectActiveProfile()
        
		
	
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_ALIVE")
    frame:RegisterEvent("LEARNED_SPELL_IN_TAB")
    frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
	frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    frame:RegisterEvent("PLAYER_LEAVING_WORLD")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	frame:RegisterEvent("SPELLS_CHANGED")
	frame:RegisterEvent("UNIT_AURA")
	frame:RegisterEvent("SPELL_PUSHED_TO_ACTIONBAR")

    XiTimers.invokeOOCFader()
    frame:SetScript("OnUpdate", XiTimers.UpdateTimers)
	frame:EnableMouse(false)

	XiTimers.IsSetUp = true
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
end


function XiTimers.Slash(msg)
	if InCombatLockdown() then
		DEFAULT_CHAT_FRAME:AddMessage("Can't open options in combat.")
		return
	end
    if XiTimers.LastGUIPanel then
        InterfaceOptionsFrame_OpenToCategory(XiTimers.LastGUIPanel)
    else
        InterfaceOptionsFrame_OpenToCategory(addonName)
		InterfaceOptionsFrame_OpenToCategory(addonName)
    end
end



function XiTimers.ChangedTalents()
    XiTimers.SelectActiveProfile()
    XiTimers.ExecuteProfile()
end

function XiTimers.LearnedSpell() end


function XiTimers.IntroAnimation(...)

	local spellID, slotIndex, slotPos = ...;
	
	local _, _, icon = GetSpellInfo(spellID);
	local freeIcon;
	
	-- find timer
	local timer = nil
	for i=1,#XiTimers.timers do
		if XiTimers.timers[i].spellID == spellID or XiTimers.timers[i].button:GetAttribute("spell1") == spellID then
			timer = XiTimers.timers[i]
		end
	end
	if not timer then return end

	for a,b in pairs(self.iconList) do
		if b.isFree then
			freeIcon = b;
		end
	end
	
	if not freeIcon then -- Make a new one
		freeIcon = CreateFrame("FRAME", "XiTimersIntroIcon"..(#self.iconList+1), UIParent, "IconIntroTemplate");
		self.iconList[#self.iconList+1] = freeIcon;
	end

	freeIcon.icon.icon:SetTexture(icon);
	freeIcon.icon.slot = 0;
	--freeIcon.icon.pos = slotPos;
	freeIcon:ClearAllPoints();
	
	freeIcon:SetPoint("CENTER", timer.button)
	
	freeIcon.icon.flyin:Play(1);
	freeIcon.isFree = false;
end