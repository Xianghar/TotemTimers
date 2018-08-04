local addonName, Addon = ...
if select(2,UnitClass("player")) ~= Addon.Class then return end

local lbf

function MonkTimers.SkinCallback(arg, Group, SkinID, Gloss, Backdrop, Colors, Fonts)
	if SkinID == "Blizzard" then
		for k,v in pairs(XiTimers.timers) do
			v.animation.button.normalTexture:Hide()
			v:HideNormalTexture()
		end
	else
		for k,v in pairs(XiTimers.timers) do
			v.animation.button.normalTexture:Show()
		end
	end
end

function MonkTimers.InitMasque()
	if not LibStub then return end
	lbf = LibStub("Masque", true)
	if lbf then
		local group = lbf:Group("MonkTimers")
		for k,v in pairs(XiTimers.timers) do
            group:AddButton(v.button)
            --group:AddButton(v.animation.button)
        end 
        lbf:Register("MonkTimers", MonkTimers.SkinCallback,nil)
        group:ReSkin()
	end
end

