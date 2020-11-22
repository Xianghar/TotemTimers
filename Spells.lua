-- Copyright © 2008 - 2016 Xianghar
-- All Rights Reserved.
-- This code is not to be modified or distributed without written permission by the author.
-- Current distribution permissions only include curse.com, wowinterface.com and their respective addon updaters


if select(2,UnitClass("player")) ~= "SHAMAN" then return end
local addonName, TotemTimers = ...



TotemTimers.SpellIDs = {
	WindRushTotem  = 192077,
	LightningSurgeTotem = 192058,
	EarthgrabTotem = 51485,
	VoodooTotem = 196932,
    
    Ankh = 20608,
	
	StormElemental = 192249,
	FireElemental = 198067,
	
	Flametongue = 193796,
	FlametongueBuff = 194084,
	Frostbrand = 196834,
	FrostbrandBuff = 147732,
	Rockbiter = 193786,
	Boulderfist = 201897,
	Windsong = 201898,
	
	FeralLunge = 196884,
	Rainfall = 215864,
	Sundering = 197214,
	FuryOfAir = 197211,
	EarthenSpike = 188089,
	LightningShield = 192106,
	LightningShieldBuff = 192109,
	WaterShield = 52127,
	WaterShieldBuff = 52128,
	EarthShield = 974,

	Reincarnation = 20608,
	
	GustOfWind = 192063,
	EarthenShieldTotem = 198838,
	AncestralProtectionTotem = 207399,
	CloudburstTotem = 157153,
	Wellspring = 197995,

    
    StormStrike = 17364,
    EarthShock = 8042,
    FrostShock = 8056,
    FlameShock = 188389,
	FlameShockDebuff = 188389,
    LavaLash = 60103,
    LightningBolt = 403,
    ChainLightning = 421,
    LavaBurst = 51505,
    Maelstrom = 51530,
    WindShear = 57994,
    ShamanisticRage = 30823,
    FeralSpirit = 51533,
    ElementalMastery = 16166,
    Thunderstorm = 51490,
    HealingRain = 73920,
    Riptide = 61295,
    UnleashElements = 73680,
	UnleashLife = 73685,
    SpiritwalkersGrace = 79206,
    Ascendance = 114049,
	AscendanceEnhancement = 114051,
	AscendanceElemental = 114050,
	AscendanceRestoration = 114052,
     
    CallOfElements = 108285,
    SpiritWalk = 58875,
    AstralShift = 108271,
    TotemicProjection = 108287,
    AncestralSwiftness = 16188,
    AncestralGuidance = 108281,
    ElementalBlast = 117014,
    
    LiquidMagmaTotem = 192222,
    LavaSurge = 77762,
    
    Hex = 51514,
    
    UnleashFlame = 73683,
	UnleashFlameEle = 165462,
    Volcano = 99207,
	
	Bloodlust = 2825,
	Heroism = 32182,
	AstralShift = 108271,
	Stormblast = 115356,
	PurifySpirit = 77130,
	
	ChainHeal = 1064,

	WindfuryWeapon = 33757,
	FlametongueWeapon = 318038,

	
}


--[[
1 - Melee
2 - Ranged
3 - Caster
4 - Healer
5 - Hybrid (mostly Enh. Shaman)
]]


--[[ TotemData = {
    [TotemTimers.SpellIDs.EarthBind] = {
		element = EARTH_TOTEM_SLOT,
        noRangeCheck = true,
        flashInterval = 3,
        flashDelay = 1,
		warningPoint = 5,
	},
	[TotemTimers.SpellIDs.Tremor] = {
		element = EARTH_TOTEM_SLOT,
        range = 900,
		warningPoint = 2,
	},
	[TotemTimers.SpellIDs.EarthGrab] = {
		element = EARTH_TOTEM_SLOT,
		flashInterval = 2,
		flashDelay = 1,
        noRangeCheck = true,
	},
	[TotemTimers.SpellIDs.EarthElemental] = {
		element = EARTH_TOTEM_SLOT,
        noRangeCheck = true,
	},
    [TotemTimers.SpellIDs.StoneBulwark] = {
		element = EARTH_TOTEM_SLOT,
        noRangeCheck = true,
        flashInterval = 5,
        flashDelay = 1,
		warningPoint = 5,
	},
	[TotemTimers.SpellIDs.Searing] = {
		element = FIRE_TOTEM_SLOT,
        noRangeCheck = true,
	},
	[TotemTimers.SpellIDs.Magma] = {
		element = FIRE_TOTEM_SLOT,
        noRangeCheck = true,
	},
	[TotemTimers.SpellIDs.FireElemental] = {
		element = FIRE_TOTEM_SLOT,
        noRangeCheck = true,
	},	
	[TotemTimers.SpellIDs.HealingStream] = {
		element = WATER_TOTEM_SLOT,
        range = 1600,
		warningPoint = 4,
	},
	[TotemTimers.SpellIDs.HealingTide] = {
		element = WATER_TOTEM_SLOT,
        range = 1600,
		warningPoint = 4,
	},
	[TotemTimers.SpellIDs.Cloudburst] = {
		element = WATER_TOTEM_SLOT,
		range = 1600,
		warningPoint = 5,
	},
	[TotemTimers.SpellIDs.Grounding] = {
		element = AIR_TOTEM_SLOT,
        partyOnly = true,
        range = 100,
		warningPoint = 5,
	},
    [TotemTimers.SpellIDs.SpiritLink] = {
        element = AIR_TOTEM_SLOT,
        range = 100,
    },
    [TotemTimers.SpellIDs.Capacitor] = {
        element = AIR_TOTEM_SLOT,
		warningPoint = 2,
        noRangeCheck = true,
    },
    [TotemTimers.SpellIDs.WindWalk] = {
        element = AIR_TOTEM_SLOT,
        range = 1600,
		warningPoint = 2,
    },
	[TotemTimers.SpellIDs.StormElemental] = {
		element = AIR_TOTEM_SLOT,
		noRangeCheck = true,
		warningPoit = 5,
	},
}]]



local SpellIDs = TotemTimers.SpellIDs

XiTimers.SpellData = {
	[SpellIDs.Bloodlust] = {
		buff = SpellIDs.Bloodlust,
		alt = {
			SpellIDs.Heroism,
		}
	},
	[SpellIDs.Heroism] = {
		buff = SpellIDs.Heroism,
		alt = {
			SpellIDs.Bloodlust
		}
	},
	[SpellIDs.AstralShift] = {
		buff = SpellIDs.AstralShift,
	},
	[SpellIDs.AncestralGuidance] = {
		roles = {
			[1] = {
				buff = SpellIDs.AncestralGuidance,
				alt = {
					SpellIDs.GustOfWind,
					SpellIDs.WindRushTotem,
				},
			},
			[2] = {},
			[3] = {
				buff = SpellIDs.AncestralGuidance,
			},
		},
	},
	[SpellIDs.WindRushTotem] = {
		roles = {
			[1] = {
				alt = {
					SpellIDs.GustOfWind,
					SpellIDs.AncestralGuidance,
				},
			},
			[2] = {
				alt = {
					SpellIDs.FeralLunge,
					SpellIDs.Rainfall,
				},
			},
			[3] = {
				SpellIDs.GustOfWind,
			},
		}
	},
	[SpellIDs.GustOfWind] = {
		roles = {
			[1] = {
				alt = {
					SpellIDs.AncestralGuidance,
					SpellIDs.WindRushTotem,
				},
			},
			[2] = {},
			[3] = {
				SpellIDs.WindRushTotem,
			},
		},
	},
	[SpellIDs.Rainfall] = {
		alt = {
			SpellIDs.FeralLunge,
			SpellIDs.WindRushTotem,
		},
	},
	[SpellIDs.FeralLunge] = {
		alt = {
			SpellIDs.WindRushTotem,
			SpellIDs.Rainfall,
		}
	},
	[SpellIDs.LightningSurgeTotem] = {
		alt = {
			SpellIDs.EarthgrabTotem,
		},
	},
	[SpellIDs.EarthgrabTotem] = {
		alt = {
			SpellIDs.LightningSurgeTotem,
		},
	},
	[SpellIDs.Hex] = {
		alt = {
			SpellIDs.VoodooTotem,
		}
	},
	[SpellIDs.VoodooTotem] = {
		alt = {
			SpellIDs.Hex,
		}
	},
	[SpellIDs.ElementalBlast] = {
		buff = SpellIDs.ElementalBlast,
	},
	[SpellIDs.FireElemental] = {
		alt = {
			SpellIDs.StormElemental,
		},
	},
	[SpellIDs.StormElemental] = {
		alt = {
			SpellIDs.FireElemental,
		},
	},
	[SpellIDs.ElementalMastery] = {
		buff = SpellIDs.ElementalMastery,
	},
	[SpellIDs.LiquidMagmaTotem] = {
		alt = {
			SpellIDs.AscendanceElemental,
			SpellIDs.Ascendance,
			SpellIDs.AscendanceEnhancement,
			SpellIDs.AscendanceRestoration,
		},
	},
	[SpellIDs.Ascendance] = {
		alt = {
			SpellIDs.LiquidMagmaTotem,
			SpellIDs.AscendanceElemental,
			SpellIDs.AscendanceEnhancement,
			SpellIDs.AscendanceRestoration,
		},
	},
	[SpellIDs.AscendanceElemental] = {
		buff = SpellIDs.AscendanceElemental,
		alt = {
			SpellIDs.LiquidMagmaTotem,
			SpellIDs.Ascendance,
			SpellIDs.AscendanceEnhancement,
			SpellIDs.AscendanceRestoration,
		},
	},
	[SpellIDs.AscendanceRestoration] = {
		alt = {
			SpellIDs.LiquidMagmaTotem,
			SpellIDs.AscendanceElemental,
			SpellIDs.AscendanceEnhancement,
			SpellIDs.Ascendance,
		},
	},
	[SpellIDs.Flametongue] = {
		buff = SpellIDs.FlametongueBuff,
	},
	[SpellIDs.Frostbrand] = {
		buff = SpellIDs.Frostbrand,
	},
	[SpellIDs.Rockbiter] = {
		alt = {
			SpellIDs.Boulderfist,
		}
	},
	[SpellIDs.Boulderfist] = {
		alt = {
			SpellIDs.Rockbiter,
		}
	},
	[SpellIDs.Windsong] = {
		buff = SpellIDs.Windsong,
	},
	[SpellIDs.Sundering] = {
		alt = {
			SpellIDs.FuryOfAir,
		},
	},
	[SpellIDs.FuryOfAir] = {
		alt = {
			SpellIDs.Sundering,
		},
	},
	[SpellIDs.EarthenSpike] = {
		alt = {
			SpellIDs.AscendanceEnhancement,
		},
	},
	[SpellIDs.AscendanceEnhancement] = {
		buff = SpellIDs.AscendanceEnhancement,
		alt = {
			SpellIDs.EarthenSpike,
		},
	},
	[SpellIDs.LightningShield] = {
		buff = SpellIDs.LightningShield,
	},
	[SpellIDs.WaterShield] = {
		buff = SpellIDs.WaterShield,
		showBuffCounter = true,
	},
	[SpellIDs.EarthShield] = {
		buff = SpellIDs.EarthShield,
	},
	[SpellIDs.SpiritwalkersGrace] = {
		buff = SpellIDs.SpiritwalkersGrace,
	},
	[SpellIDs.AncestralProtectionTotem] = {
		alt = {
			SpellIDs.EarthenShieldTotem,
		},
	},
	[SpellIDs.EarthenShieldTotem] = {
		alt = {
			SpellIDs.AncestralProtectionTotem,
		},
	},
	[SpellIDs.Wellspring] = {
		alt = {
			SpellIDs.AscendanceRestoration,
		},
	},
	[SpellIDs.AscendanceRestoration] = {
		buff = SpellIDs.AscendanceRestoration,
		alt = {
			SpellIDs.Wellspring,
		},
	},
	[SpellIDs.WindfuryWeapon] = {
		playerEvents = {
			"UNIT_INVENTORY_CHANGED",
		},
		customOnEvent = function(self, event, ...)
			if event == "UNIT_INVENTORY_CHANGED" then
				local timer = self.timer
				local hasEnchant, expires, _, spell = GetWeaponEnchantInfo()
				local now = GetTime()
				if (hasEnchant and spell == 5401) then
					timer:Start(now - (3600 - expires / 1000), now + expires / 1000, true)
				elseif timer.isRunning then
					timer:Stop()
				end
			end
		end,
		startEvents = {"UNIT_INVENTORY_CHANGED"},
	},
	[SpellIDs.FlametongueWeapon] = {
		playerEvents = {
			"UNIT_INVENTORY_CHANGED",
		},
		customOnEvent = function(self, event, ...)
			if event == "UNIT_INVENTORY_CHANGED" then
				local timer = self.timer
				local _,_,_,_, hasEnchant, expires, _, spell = GetWeaponEnchantInfo()
				local now = GetTime()
				if (hasEnchant and spell == 5400) then
					timer:Start(now - (3600 - expires / 1000), now + expires / 1000, true)
				elseif timer.isRunning then
					timer:Stop()
				end
			end
		end,
		startEvents = {"UNIT_INVENTORY_CHANGED"},
	},
}




