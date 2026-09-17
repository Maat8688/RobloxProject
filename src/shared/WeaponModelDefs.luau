--!strict
-- What each weapon looks like in a player's hands and on its stand, built from
-- plain parts. Pure data — no Roblox API. The server builds the models
-- (WeaponVisuals), so every player sees what everyone else is holding.
--
-- Like RigDefs, these are gray-box stand-ins for real meshes: a mesh can later
-- replace a piece one-for-one under the same name without touching the code.
--
-- Coordinates are in the space of the body part a piece hangs from, with the
-- same axes as RigDefs: +Y up, -Z forward, +X the rig's right. A piece on a
-- hand is placed relative to that hand's grip point when the avatar has one
-- (RightGripAttachment / LeftGripAttachment), otherwise the hand's centre. A
-- blade along -Z therefore points forward while the arm hangs, and swings
-- with the arm.

export type RGB = { number }
export type Vec3 = { number }

export type PieceDef = {
	name: string,
	-- An R15 body part name.
	attachTo: string,
	size: Vec3,
	offset: Vec3,
	-- Degrees, applied after the offset.
	rotation: Vec3?,
	color: RGB,
	-- An Enum.Material name; SmoothPlastic when unset.
	material: string?,
	-- An Enum.PartType name; Block when unset.
	shape: string?,
	transparency: number?,
	-- Lights up and sparkles as the weapon is upgraded.
	glow: boolean?,
}

export type WeaponModelDef = {
	pieces: { PieceDef },
	-- Upgrade glow colour on the `glow` pieces.
	glowColor: RGB,
}

export type UpgradeLook = {
	-- PointLight brightness on each glow piece; 0 means no light.
	lightBrightness: number,
	-- Sparkle particles per second on each glow piece; 0 means none.
	sparkleRate: number,
	-- Whether glow pieces turn to Neon in the glow colour.
	neon: boolean,
}

local WeaponModelDefs = {}

-- The model's name inside a character.
WeaponModelDefs.MODEL_NAME = "EquippedWeapon"
-- The attribute a character carries naming its equipped weapon, so every
-- client can pick that weapon's stance for it.
WeaponModelDefs.WEAPON_ATTRIBUTE = "WeaponId"

local STEEL = { 196, 202, 212 }
local DARK_STEEL = { 90, 94, 104 }
local GOLD = { 212, 170, 70 }
local LEATHER = { 86, 56, 38 }
local OAK = { 120, 82, 50 }

local function dagger(side: "Right" | "Left"): { PieceDef }
	local hand = `{side}Hand`
	return {
		{ name = `{side}DaggerGrip`, attachTo = hand, size = { 0.18, 0.18, 0.5 }, offset = { 0, 0, 0 }, color = LEATHER, material = "Fabric" },
		{ name = `{side}DaggerGuard`, attachTo = hand, size = { 0.6, 0.12, 0.12 }, offset = { 0, 0, -0.3 }, color = GOLD, material = "Metal" },
		{ name = `{side}DaggerBlade`, attachTo = hand, size = { 0.08, 0.22, 1.3 }, offset = { 0, 0, -1.0 }, color = STEEL, material = "Metal", glow = true },
	}
end

local function concat(...: { PieceDef }): { PieceDef }
	local out = {}
	for _, list in { ... } do
		for _, piece in list do
			table.insert(out, piece)
		end
	end
	return out
end

-- Keyed by WeaponDefs id.
WeaponModelDefs.MODELS = {
	SwordAndShield = {
		glowColor = { 120, 190, 255 },
		pieces = {
			{ name = "SwordGrip", attachTo = "RightHand", size = { 0.2, 0.2, 0.9 }, offset = { 0, 0, 0 }, color = LEATHER, material = "Fabric" },
			{ name = "SwordPommel", attachTo = "RightHand", size = { 0.32, 0.32, 0.32 }, offset = { 0, 0, 0.5 }, color = GOLD, material = "Metal", shape = "Ball" },
			{ name = "SwordGuard", attachTo = "RightHand", size = { 1.1, 0.2, 0.2 }, offset = { 0, 0, -0.5 }, color = GOLD, material = "Metal" },
			{ name = "SwordBlade", attachTo = "RightHand", size = { 0.12, 0.32, 3.2 }, offset = { 0, 0, -2.2 }, color = STEEL, material = "Metal", glow = true },
			-- Strapped to the outside of the left forearm.
			{ name = "ShieldFace", attachTo = "LeftLowerArm", size = { 0.25, 2.2, 1.9 }, offset = { -0.55, 0, 0 }, color = { 128, 36, 36 }, material = "Wood" },
			{ name = "ShieldRimTop", attachTo = "LeftLowerArm", size = { 0.3, 0.16, 1.95 }, offset = { -0.56, 1.1, 0 }, color = DARK_STEEL, material = "Metal" },
			{ name = "ShieldRimBottom", attachTo = "LeftLowerArm", size = { 0.3, 0.16, 1.95 }, offset = { -0.56, -1.1, 0 }, color = DARK_STEEL, material = "Metal" },
			{ name = "ShieldBoss", attachTo = "LeftLowerArm", size = { 0.6, 0.6, 0.6 }, offset = { -0.7, 0, 0 }, color = GOLD, material = "Metal", shape = "Ball", glow = true },
		},
	},

	Daggers = {
		glowColor = { 200, 110, 255 },
		pieces = concat(dagger("Right"), dagger("Left")),
	},

	-- Gripped below the middle, so it stands upright at rest with the orb above
	-- the head, and swings through level like a quarterstaff when the arm
	-- comes forward. (A hand's +Y runs up the forearm, so a staff reaching only
	-- upward from the grip would point back through the body mid-swing.)
	Staff = {
		glowColor = { 110, 255, 170 },
		pieces = {
			{ name = "StaffShaft", attachTo = "RightHand", size = { 0.22, 6, 0.22 }, offset = { 0, 0.8, -0.5 }, color = OAK, material = "Wood" },
			{ name = "StaffCollar", attachTo = "RightHand", size = { 0.4, 0.25, 0.4 }, offset = { 0, 3.7, -0.5 }, color = GOLD, material = "Metal" },
			{ name = "StaffOrb", attachTo = "RightHand", size = { 0.8, 0.8, 0.8 }, offset = { 0, 4.25, -0.5 }, color = { 150, 255, 200 }, material = "Glass", shape = "Ball", transparency = 0.2, glow = true },
			{ name = "StaffProngRight", attachTo = "RightHand", size = { 0.1, 0.7, 0.1 }, offset = { 0.35, 4.15, -0.5 }, rotation = { 0, 0, -20 }, color = GOLD, material = "Metal" },
			{ name = "StaffProngLeft", attachTo = "RightHand", size = { 0.1, 0.7, 0.1 }, offset = { -0.35, 4.15, -0.5 }, rotation = { 0, 0, 20 }, color = GOLD, material = "Metal" },
		},
	},
} :: { [string]: WeaponModelDef }

-- How an upgraded weapon shows its level. Upgrades are progress you paid for,
-- so they should be visible to everyone standing next to you.
function WeaponModelDefs.upgradeLook(level: number): UpgradeLook
	local l = math.max(math.floor(level), 0)
	return {
		lightBrightness = if l >= 1 then 0.4 * l else 0,
		sparkleRate = if l >= 3 then 4 * (l - 2) else 0,
		neon = l >= 5,
	}
end

return WeaponModelDefs
