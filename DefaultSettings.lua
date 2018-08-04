-- Copyright © 2008 - 2012 Xianghar  <xian@zron.de>
-- All Rights Reserved.
-- This code is not to be modified or distributed without written permission by the author.
-- Current distribution permissions only include curse.com, wowinterface.com and their respective addon updaters

if select(2,UnitClass("player")) ~= "SHAMAN" then return end

local addonName, TotemTimers = ...

local Version = 12.01

TotemTimers_Profiles = {
    ["default"] = {}
}
TotemTimers_GlobalSettings = {}

local DefaultProfile = XiTimers.DefaultProfile


DefaultProfile.HideBlizzTimers = true

DefaultProfile.LavaSurgeAura = true
DefaultProfile.LavaSurgeGlow = true
DefaultProfile.FulminationAura = true
DefaultProfile.FulminationGlow = true

DefaultProfile.EarthShieldLeftButton = "recast"
DefaultProfile.EarthShieldRightButton = "target"
DefaultProfile.EarthShieldMiddleButton = "targettarget"
DefaultProfile.EarthShieldButton4 = "player"
DefaultProfile.EarthShieldTargetName = true
DefaultProfile.ESMainTankMenu = true
DefaultProfile.ESMainTankMenuDirection = "auto"
DefaultProfile.ESChargesOnly = false

DefaultProfile.ActivateHiddenTimers = false

DefaultProfile.Warnings = {
		TotemWarning = {
			r = 1,
			g = 0,
			b = 0,
			a = 1,
			sound = "",
			text = "Totem Expiring",
			enabled = true,
		},
		TotemExpiration = {
			r = 1,
			g = 0,
			b = 0,
			a = 1,
			sound = "",
			text = "Totem Expired",
			enabled = true,
		},
		TotemDestroyed = {
			r = 1,
			g = 0,
			b = 0,
			a = 1,
			sound = "",
			text = "Totem Destroyed",
			enabled = true,
		},
		Shield = {
			r = 1,
			g = 0,
			b = 0,
			a = 1,
			sound = "",
			text = "Shield removed",
			enabled = true,
		},
		EarthShield = {
			r = 1,
			g = 0,
			b = 0,
			a = 1,
			sound = "",
			text = "Shield removed",
			enabled = true,
		},
		Maelstrom = {
			r = 1,
			g = 0,
			b = 0,
			a = 1,
			sound = "",
			text = "Maelstrom Notifier",
			enabled = true,
		},
	}



DefaultProfile.FlameshockBar = true
DefaultProfile.FlameshockBarRestoration = true

DefaultProfile.MaelstromBar = true
DefaultProfile.ManaBar = true


XiTimers.DefaultProfile.buttons = {
	["buttons"] = {
		["SHAMAN"] = {
			{
				nil, -- [1]
				nil, -- [2]
				{
					["id"] = 117014,
					["type"] = "spell",
				}, -- [3]
				{
					["id"] = 51505,
					["type"] = "spell",
				}, -- [4]
				{
					["id"] = 188389,
					["type"] = "spell",
				}, -- [5]
				{
					["id"] = 196840,
					["type"] = "spell",
				}, -- [6]
				{
					["id"] = 8042,
					["type"] = "spell",
				}, -- [7]
				{
					["id"] = 57994,
					["type"] = "spell",
				}, -- [8]
				[13] = {
					["id"] = 108271,
					["type"] = "spell",
				},
				[35] = {
					["id"] = 192058,
					["type"] = "spell",
				},
				[14] = {
					["id"] = 51490,
					["type"] = "spell",
				},
				[39] = {
					["id"] = 2825,
					["type"] = "spell",
				},
				[15] = {
					["id"] = 198103,
					["type"] = "spell",
				},
				[16] = {
					["id"] = 192249,
					["type"] = "spell",
				},
				[17] = {
					["id"] = 210714,
					["type"] = "spell",
				},
				[18] = {
					["id"] = 20608,
					["type"] = "spell",
				},
				[36] = {
					["id"] = 108281,
					["type"] = "spell",
				},
				[38] = {
					["id"] = 61882,
					["type"] = "spell",
				},
				[40] = {
					["id"] = 51514,
					["type"] = "spell",
				},
				[34] = {
					["id"] = 192222,
					["type"] = "spell",
				},
				[37] = {
					["id"] = 210643,
					["type"] = "spell",
				},
			}, -- [1]
			{
				nil, -- [1]
				nil, -- [2]
				{
					["id"] = 193786,
					["type"] = "spell",
				}, -- [3]
				{
					["id"] = 17364,
					["type"] = "spell",
				}, -- [4]
				{
					["id"] = 60103,
					["type"] = "spell",
				}, -- [5]
				{
					["id"] = 187874,
					["type"] = "spell",
				}, -- [6]
				{
					["id"] = 193796,
					["type"] = "spell",
				}, -- [7]
				{
					["id"] = 201898,
					["type"] = "spell",
				}, -- [8]
				[13] = {
					["id"] = 192077,
					["type"] = "spell",
				},
				[14] = {
					["id"] = 108271,
					["type"] = "spell",
				},
				[39] = {
					["id"] = 2825,
					["type"] = "spell",
				},
				[15] = {
					["id"] = 58875,
					["type"] = "spell",
				},
				[16] = {
					["id"] = 51533,
					["type"] = "spell",
				},
				[17] = {
					["id"] = 57994,
					["type"] = "spell",
				},
				[18] = {
					["id"] = 196834,
					["type"] = "spell",
				},
				[36] = {
					["id"] = 188089,
					["type"] = "spell",
				},
				[38] = {
					["id"] = 51485,
					["type"] = "spell",
				},
				[40] = {
					["id"] = 51514,
					["type"] = "spell",
				},
				[37] = {
					["id"] = 192106,
					["type"] = "spell",
				},
				[12] = {
					["id"] = 197214,
					["type"] = "spell",
				},
				[19] = {
					["id"] = 20608,
					["type"] = "spell",
				},
			}, -- [2]
			{
				nil, -- [1]
				nil, -- [2]
				{
					["id"] = 61295,
					["type"] = "spell",
				}, -- [3]
				{
					["id"] = 73920,
					["type"] = "spell",
				}, -- [4]
				{
					["id"] = 5394,
					["type"] = "spell",
				}, -- [5]
				{
					["id"] = 108280,
					["type"] = "spell",
				}, -- [6]
				{
					["id"] = 98008,
					["type"] = "spell",
				}, -- [7]
				{
					["id"] = 73685,
					["type"] = "spell",
				}, -- [8]
				[13] = {
					["id"] = 108271,
					["type"] = "spell",
				},
				[35] = {
					["id"] = 157153,
					["type"] = "spell",
				},
				[14] = {
					["id"] = 188838,
					["type"] = "spell",
				},
				[39] = {
					["id"] = 2825,
					["type"] = "spell",
				},
				[15] = {
					["id"] = 51505,
					["type"] = "spell",
				},
				[16] = {
					["id"] = 57994,
					["type"] = "spell",
				},
				[17] = {
					["id"] = 77130,
					["type"] = "spell",
				},
				[18] = {
					["id"] = 79206,
					["type"] = "spell",
				},
				[19] = {
					["id"] = 20608,
					["type"] = "spell",
				},
				[38] = {
					["id"] = 192077,
					["type"] = "spell",
				},
				[40] = {
					["id"] = 51514,
					["type"] = "spell",
				},
				[37] = {
					["id"] = 192058,
					["type"] = "spell",
				},
				[12] = {
					["id"] = 197995,
					["type"] = "spell",
				},
				[36] = {
					["id"] = 108281,
					["type"] = "spell",
				},
			}, -- [3]
		},
	},
}

