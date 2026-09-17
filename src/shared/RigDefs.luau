--!strict
-- What every rig is made of. Pure data — no Roblox API.
--
-- All rigs share one R15-style skeleton: the same 15 part names and the same
-- joint names as a default Roblox R15 avatar. That shared vocabulary is what
-- lets one animation system drive enemies and players alike, and lets any
-- animation refined in the Animation Editor play on any rig.
--
-- A rig's look is a style over that skeleton: colours, materials, how thick
-- each part is, and welded decorations (ribs, eyes, a sword). Only width and
-- depth can change — never a part's length — so the joints always line up.
-- Real meshes can later replace these parts one-for-one under the same names.
--
-- Coordinates are in rig space: the origin is the centre of the enemy's
-- hitbox (HumanoidRootPart, ROOT_SIZE), +Y is up, -Z is forward, +X is the
-- rig's right. The feet touch the bottom of the hitbox.

local RigDefs = {}

export type Vec3 = { number }
export type RGB = { number }

RigDefs.ROOT_SIZE = { 4, 6, 4 }

export type BodyPart = {
	name: string,
	-- The part this one hangs from, and the Motor6D joining them. The joint
	-- lives inside this part, as in a Roblox R15 avatar.
	parent: string,
	joint: string,
	size: Vec3,
	-- Centre of the part, and where it pivots, in rig space.
	center: Vec3,
	pivot: Vec3,
}

-- Parents always come before their children, so building in this order never
-- references a part that doesn't exist yet.
RigDefs.SKELETON = {
	{ name = "LowerTorso", parent = "HumanoidRootPart", joint = "Root", size = { 2, 0.6, 1 }, center = { 0, 0, 0 }, pivot = { 0, 0, 0 } },
	{ name = "UpperTorso", parent = "LowerTorso", joint = "Waist", size = { 2, 1.5, 1 }, center = { 0, 1.05, 0 }, pivot = { 0, 0.3, 0 } },
	{ name = "Head", parent = "UpperTorso", joint = "Neck", size = { 1.2, 1.2, 1.2 }, center = { 0, 2.4, 0 }, pivot = { 0, 1.8, 0 } },

	{ name = "RightUpperArm", parent = "UpperTorso", joint = "RightShoulder", size = { 0.8, 1.2, 0.8 }, center = { 1.4, 1.2, 0 }, pivot = { 1.4, 1.6, 0 } },
	{ name = "RightLowerArm", parent = "RightUpperArm", joint = "RightElbow", size = { 0.7, 1.1, 0.7 }, center = { 1.4, 0.05, 0 }, pivot = { 1.4, 0.6, 0 } },
	{ name = "RightHand", parent = "RightLowerArm", joint = "RightWrist", size = { 0.7, 0.5, 0.7 }, center = { 1.4, -0.75, 0 }, pivot = { 1.4, -0.5, 0 } },

	{ name = "LeftUpperArm", parent = "UpperTorso", joint = "LeftShoulder", size = { 0.8, 1.2, 0.8 }, center = { -1.4, 1.2, 0 }, pivot = { -1.4, 1.6, 0 } },
	{ name = "LeftLowerArm", parent = "LeftUpperArm", joint = "LeftElbow", size = { 0.7, 1.1, 0.7 }, center = { -1.4, 0.05, 0 }, pivot = { -1.4, 0.6, 0 } },
	{ name = "LeftHand", parent = "LeftLowerArm", joint = "LeftWrist", size = { 0.7, 0.5, 0.7 }, center = { -1.4, -0.75, 0 }, pivot = { -1.4, -0.5, 0 } },

	{ name = "RightUpperLeg", parent = "LowerTorso", joint = "RightHip", size = { 0.9, 1.2, 0.9 }, center = { 0.5, -0.9, 0 }, pivot = { 0.5, -0.4, 0 } },
	{ name = "RightLowerLeg", parent = "RightUpperLeg", joint = "RightKnee", size = { 0.8, 1.1, 0.8 }, center = { 0.5, -2.05, 0 }, pivot = { 0.5, -1.5, 0 } },
	{ name = "RightFoot", parent = "RightLowerLeg", joint = "RightAnkle", size = { 0.8, 0.4, 1.2 }, center = { 0.5, -2.8, -0.15 }, pivot = { 0.5, -2.6, 0 } },

	{ name = "LeftUpperLeg", parent = "LowerTorso", joint = "LeftHip", size = { 0.9, 1.2, 0.9 }, center = { -0.5, -0.9, 0 }, pivot = { -0.5, -0.4, 0 } },
	{ name = "LeftLowerLeg", parent = "LeftUpperLeg", joint = "LeftKnee", size = { 0.8, 1.1, 0.8 }, center = { -0.5, -2.05, 0 }, pivot = { -0.5, -1.5, 0 } },
	{ name = "LeftFoot", parent = "LeftLowerLeg", joint = "LeftAnkle", size = { 0.8, 0.4, 1.2 }, center = { -0.5, -2.8, -0.15 }, pivot = { -0.5, -2.6, 0 } },
} :: { BodyPart }

export type PartStyle = {
	color: RGB,
	-- An Enum.Material name.
	material: string?,
	-- Multiplies the part's width (X) and depth (Z). Length is fixed.
	width: number?,
	depth: number?,
}

export type Decoration = {
	name: string,
	attachTo: string,
	size: Vec3,
	-- Relative to the centre of the part it's attached to.
	offset: Vec3,
	color: RGB,
	material: string?,
	-- An Enum.PartType name; Block when unset.
	shape: string?,
	transparency: number?,
}

export type RigStyle = {
	displayName: string,
	-- Style for any part not listed in `parts`.
	default: PartStyle,
	parts: { [string]: PartStyle },
	decorations: { Decoration },
}

local BONE = { 232, 226, 206 }
local STEEL = { 160, 165, 175 }
local ZOMBIE_SKIN = { 118, 150, 92 }
local WOOD = { 164, 120, 78 }
local SPITTER_HIDE = { 150, 170, 70 }
local VOID = { 20, 18, 16 }

-- Both sides of a mirrored pair at once.
local function both(parts: { [string]: PartStyle }, suffix: string, style: PartStyle)
	parts[`Right{suffix}`] = style
	parts[`Left{suffix}`] = style
end

local function skeletonStyle(): RigStyle
	local parts: { [string]: PartStyle } = {
		-- The spine: the torso is mostly air, and the ribs are decorations.
		UpperTorso = { color = BONE, width = 0.3, depth = 0.4 },
		LowerTorso = { color = BONE, width = 0.8, depth = 0.6 },
		Head = { color = BONE, width = 0.95, depth = 0.95 },
	}
	for _, suffix in { "UpperArm", "LowerArm", "UpperLeg", "LowerLeg" } do
		both(parts, suffix, { color = BONE, width = 0.45, depth = 0.45 })
	end
	both(parts, "Hand", { color = BONE, width = 0.7, depth = 0.7 })
	both(parts, "Foot", { color = BONE, width = 0.7, depth = 0.9 })

	return {
		displayName = "Skeleton Warrior",
		default = { color = BONE },
		parts = parts,
		decorations = {
			{ name = "RibTop", attachTo = "UpperTorso", size = { 1.8, 0.16, 0.8 }, offset = { 0, 0.45, 0 }, color = BONE },
			{ name = "RibMiddle", attachTo = "UpperTorso", size = { 1.7, 0.16, 0.75 }, offset = { 0, 0.1, 0 }, color = BONE },
			{ name = "RibBottom", attachTo = "UpperTorso", size = { 1.5, 0.16, 0.7 }, offset = { 0, -0.25, 0 }, color = BONE },
			{ name = "EyeRight", attachTo = "Head", size = { 0.3, 0.3, 0.05 }, offset = { 0.27, 0.1, -0.58 }, color = VOID },
			{ name = "EyeLeft", attachTo = "Head", size = { 0.3, 0.3, 0.05 }, offset = { -0.27, 0.1, -0.58 }, color = VOID },
			{ name = "Jaw", attachTo = "Head", size = { 0.7, 0.12, 0.05 }, offset = { 0, -0.35, -0.58 }, color = VOID },
			-- Held forward from the right hand, so swings read at a glance.
			{ name = "Blade", attachTo = "RightHand", size = { 0.12, 0.25, 3.2 }, offset = { 0, -0.05, -1.75 }, color = STEEL, material = "Metal" },
			{ name = "Crossguard", attachTo = "RightHand", size = { 0.9, 0.14, 0.14 }, offset = { 0, -0.05, -0.2 }, color = { 110, 90, 60 }, material = "Metal" },
		},
	}
end

local function shamblerStyle(): RigStyle
	local shirt = { 92, 58, 46 }
	local trousers = { 58, 64, 82 }

	local parts: { [string]: PartStyle } = {
		UpperTorso = { color = shirt, material = "Fabric" },
		LowerTorso = { color = trousers, material = "Fabric" },
		Head = { color = ZOMBIE_SKIN },
	}
	both(parts, "UpperLeg", { color = trousers, material = "Fabric" })
	both(parts, "LowerLeg", { color = ZOMBIE_SKIN })
	both(parts, "Foot", { color = { 40, 35, 30 } })
	both(parts, "UpperArm", { color = shirt, material = "Fabric" })

	return {
		displayName = "Shambler",
		default = { color = ZOMBIE_SKIN },
		parts = parts,
		decorations = {
			{ name = "EyeRight", attachTo = "Head", size = { 0.22, 0.14, 0.05 }, offset = { 0.26, 0.12, -0.61 }, color = { 255, 60, 40 }, material = "Neon" },
			{ name = "EyeLeft", attachTo = "Head", size = { 0.22, 0.14, 0.05 }, offset = { -0.26, 0.12, -0.61 }, color = { 255, 60, 40 }, material = "Neon" },
			{ name = "Mouth", attachTo = "Head", size = { 0.6, 0.14, 0.05 }, offset = { 0, -0.3, -0.61 }, color = VOID },
			-- A torn flap hanging off the shirt.
			{ name = "ShirtFlap", attachTo = "UpperTorso", size = { 0.7, 0.6, 0.08 }, offset = { 0.45, -0.75, -0.5 }, color = shirt, material = "Fabric" },
		},
	}
end

local function dummyStyle(): RigStyle
	local sack = { 190, 165, 120 }

	return {
		displayName = "Training Dummy",
		default = { color = WOOD, material = "Wood" },
		parts = {
			Head = { color = sack, material = "Fabric" },
		},
		decorations = {
			-- A target painted on the chest.
			{ name = "TargetOuter", attachTo = "UpperTorso", size = { 1.2, 1.2, 0.05 }, offset = { 0, 0, -0.52 }, color = { 200, 40, 40 } },
			{ name = "TargetInner", attachTo = "UpperTorso", size = { 0.6, 0.6, 0.06 }, offset = { 0, 0, -0.53 }, color = { 240, 240, 240 } },
			{ name = "Stitching", attachTo = "Head", size = { 0.8, 0.08, 0.05 }, offset = { 0, -0.2, -0.61 }, color = { 90, 70, 50 } },
		},
	}
end

local function spitterStyle(): RigStyle
	local parts: { [string]: PartStyle } = {
		-- Bloated body on spindly limbs.
		UpperTorso = { color = SPITTER_HIDE, width = 1.2, depth = 1.6 },
		LowerTorso = { color = SPITTER_HIDE, width = 1.1, depth = 1.4 },
		Head = { color = SPITTER_HIDE, width = 0.8, depth = 0.9 },
	}
	for _, suffix in { "UpperArm", "LowerArm", "UpperLeg", "LowerLeg" } do
		both(parts, suffix, { color = SPITTER_HIDE, width = 0.6, depth = 0.6 })
	end

	return {
		displayName = "Spitter",
		default = { color = SPITTER_HIDE },
		parts = parts,
		decorations = {
			{ name = "AcidSac", attachTo = "UpperTorso", size = { 1.6, 1.6, 1.6 }, offset = { 0, 0.2, 1.05 }, color = { 170, 255, 60 }, material = "Neon", shape = "Ball", transparency = 0.35 },
			{ name = "Mouth", attachTo = "Head", size = { 0.5, 0.3, 0.05 }, offset = { 0, -0.2, -0.56 }, color = { 170, 255, 60 }, material = "Neon" },
			{ name = "EyeRight", attachTo = "Head", size = { 0.16, 0.16, 0.05 }, offset = { 0.2, 0.2, -0.56 }, color = VOID },
			{ name = "EyeLeft", attachTo = "Head", size = { 0.16, 0.16, 0.05 }, offset = { -0.2, 0.2, -0.56 }, color = VOID },
		},
	}
end

-- A plain R15 figure standing in for a player's avatar in the animation
-- workbench. Player animations are refined on it; they play on real avatars
-- because the part and joint names match.
local function playerStyle(): RigStyle
	return {
		displayName = "R15 Player",
		default = { color = { 163, 162, 165 } },
		parts = {
			Head = { color = { 245, 205, 48 } },
		},
		decorations = {},
	}
end

RigDefs.PLAYER_RIG = "R15Player"

-- Keyed by rig id. An enemy's rig id is its EnemyDefs id.
RigDefs.STYLES = {
	TrainingDummy = dummyStyle(),
	SkeletonWarrior = skeletonStyle(),
	Shambler = shamblerStyle(),
	Spitter = spitterStyle(),
	R15Player = playerStyle(),
} :: { [string]: RigStyle }

function RigDefs.styleOf(rigId: string): RigStyle
	local style = RigDefs.STYLES[rigId]
	assert(style, `No rig style for "{rigId}"`)
	return style
end

function RigDefs.partStyle(style: RigStyle, partName: string): PartStyle
	return style.parts[partName] or style.default
end

-- The part names of the skeleton, in build order.
function RigDefs.partNames(): { string }
	local names = {}
	for _, part in RigDefs.SKELETON do
		table.insert(names, part.name)
	end
	return names
end

return RigDefs
