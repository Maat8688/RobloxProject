--!strict
-- Rough animations for every rig, as data. Pure — no Roblox API.
--
-- These are first drafts meant to be refined. The game plays them as they are
-- until a refined version is published: see AnimationIds, and the workbench
-- (`lune run animation-workbench`), which turns every one of these into a
-- KeyframeSequence to open in the Animation Editor.
--
-- Reading a pose (all rigs share R15 joints, see RigDefs):
--   rx  arms and legs: + swings forward, - swings back
--       torso and head: + leans back / looks up, - leans or nods forward
--       knees: - bends; elbows: + bends
--   rz  right arm: + raises it out sideways; left arm: - does
--   ry  + turns to the rig's left
--   px/py/pz  studs; only used on LowerTorso, which moves the whole body
--       (py - is down, pz - is forward)
--
-- Enemy attacks and player swings carry `impact`: the moment the hit lands.
-- Playback stretches everything before it over the real windup, so the
-- visible strike always meets the server's impact time. Keep a keyframe at
-- exactly that time; the workbench names it "Impact", and a refined version
-- must keep a keyframe with that name for the timing to survive publishing.
--
-- Player animations never pose LowerTorso or the legs, so the default
-- walk and run keep playing underneath a swing.

local KeyframeMath = require(script.Parent.KeyframeMath)
local RigDefs = require(script.Parent.RigDefs)

type AnimationDef = KeyframeMath.AnimationDef
type Keyframe = KeyframeMath.Keyframe
type PoseSpec = KeyframeMath.PoseSpec
type Poses = { [string]: PoseSpec }

local AnimationDefs = {}

AnimationDefs.ENEMY_BASICS = { "idle", "walk", "stagger", "death" }
AnimationDefs.PARRY = "parry"

function AnimationDefs.attack(attackId: string): string
	return `attack_{attackId}`
end

function AnimationDefs.swing(weaponId: string): string
	return `swing_{weaponId}`
end

--[[ Building blocks ]]

local function kf(time: number, poses: Poses, easing: KeyframeMath.Easing?): Keyframe
	return { time = time, poses = poses, easing = easing or "Smooth" }
end

local function merge(...: Poses): Poses
	local out: Poses = {}
	for _, poses in { ... } do
		for part, pose in poses do
			out[part] = table.clone(pose)
		end
	end
	return out
end

local function mirrorName(name: string): string
	if string.sub(name, 1, 5) == "Right" then
		return "Left" .. string.sub(name, 6)
	elseif string.sub(name, 1, 4) == "Left" then
		return "Right" .. string.sub(name, 5)
	end
	return name
end

-- The same pose on the other side: sides swap, and sideways and twisting
-- motion flips.
local function mirror(poses: Poses): Poses
	local out: Poses = {}
	for part, pose in poses do
		out[mirrorName(part)] = {
			rx = pose.rx,
			ry = if pose.ry then -pose.ry else nil,
			rz = if pose.rz then -pose.rz else nil,
			px = if pose.px then -pose.px else nil,
			py = pose.py,
			pz = pose.pz,
		}
	end
	return out
end

-- Upper and lower leg lengths, from RigDefs' hip, knee and ankle pivots.
local LEG_LENGTH = 2.2

-- Both legs bent by `angle` degrees at the hip, twice that at the knee, and
-- back at the ankle, with the body lowered so the feet stay on the floor.
local function crouch(angle: number): Poses
	local drop = -LEG_LENGTH * (1 - math.cos(math.rad(angle)))
	return {
		LowerTorso = { py = drop },
		RightUpperLeg = { rx = angle },
		LeftUpperLeg = { rx = angle },
		RightLowerLeg = { rx = -2 * angle },
		LeftLowerLeg = { rx = -2 * angle },
		RightFoot = { rx = angle },
		LeftFoot = { rx = angle },
	}
end

type IdleParams = {
	length: number,
	lean: number,
	breathe: number,
	armForward: number,
	armOut: number,
	elbow: number,
	knee: number,
	headTilt: number,
	sway: number,
}

local function idle(p: IdleParams): AnimationDef
	local function pose(breath: number): Poses
		return merge(crouch(p.knee), {
			UpperTorso = { rx = p.lean + breath, ry = breath * p.sway },
			Head = { rx = -p.lean * 0.6 - breath * 0.5, rz = p.headTilt },
			RightUpperArm = { rx = p.armForward + breath * 0.5, rz = p.armOut + breath },
			LeftUpperArm = { rx = p.armForward + breath * 0.5, rz = -(p.armOut + breath) },
			RightLowerArm = { rx = p.elbow },
			LeftLowerArm = { rx = p.elbow },
		})
	end

	return {
		length = p.length,
		looped = true,
		priority = "Idle",
		keyframes = {
			kf(0, pose(0)),
			kf(p.length / 2, pose(p.breathe)),
			kf(p.length, pose(0)),
		},
	}
end

type WalkParams = {
	length: number,
	stride: number,
	armSwing: number,
	knee: number,
	lean: number,
	bob: number,
	twist: number,
	rock: number,
	armForward: number,
	armOut: number,
	elbow: number,
	-- 0..1: how much the left leg drags instead of stepping.
	limp: number,
}

-- A four-beat cycle: contact, passing, mirrored contact, mirrored passing.
local function walk(p: WalkParams): AnimationDef
	local contact: Poses = {
		LowerTorso = { py = -p.bob, rz = p.rock },
		UpperTorso = { rx = p.lean, ry = p.twist },
		Head = { rx = -p.lean * 0.6 },
		RightUpperLeg = { rx = p.stride },
		RightLowerLeg = { rx = -5 },
		LeftUpperLeg = { rx = -p.stride },
		LeftLowerLeg = { rx = -p.knee },
		RightUpperArm = { rx = p.armForward - p.armSwing, rz = p.armOut },
		LeftUpperArm = { rx = p.armForward + p.armSwing, rz = -p.armOut },
		RightLowerArm = { rx = p.elbow },
		LeftLowerArm = { rx = p.elbow },
	}

	local passing: Poses = {
		LowerTorso = { py = p.bob },
		UpperTorso = { rx = p.lean },
		Head = { rx = -p.lean * 0.6 },
		RightUpperLeg = { rx = 0 },
		RightLowerLeg = { rx = -5 },
		LeftUpperLeg = { rx = p.stride * 0.2 },
		LeftLowerLeg = { rx = -p.knee * 1.6 },
		RightUpperArm = { rx = p.armForward, rz = p.armOut },
		LeftUpperArm = { rx = p.armForward, rz = -p.armOut },
		RightLowerArm = { rx = p.elbow },
		LeftLowerArm = { rx = p.elbow },
	}

	-- Mirrored before any limp is applied, so the limp stays on one side.
	local contactMirrored = mirror(contact)
	local passingMirrored = mirror(passing)

	-- A limp: the left leg barely comes forward when it steps, and barely
	-- lifts as it swings through.
	if p.limp > 0 then
		local keep = 1 - p.limp
		local leftStep = contactMirrored.LeftUpperLeg
		leftStep.rx = (leftStep.rx :: number) * keep
		local leftSwing = passing.LeftLowerLeg
		leftSwing.rx = (leftSwing.rx :: number) * keep
	end

	local L = p.length
	return {
		length = L,
		looped = true,
		priority = "Movement",
		keyframes = {
			kf(0, contact),
			kf(L * 0.25, passing),
			kf(L * 0.5, contactMirrored),
			kf(L * 0.75, passingMirrored),
			kf(L, contact),
		},
	}
end

-- Knocked back by a parry, then dazed. One second long; playback stretches it
-- over the real stagger duration.
local function stagger(intensity: number): AnimationDef
	local k = intensity
	local recoil: Poses = merge(crouch(12 * k), {
		UpperTorso = { rx = 24 * k },
		Head = { rx = 20 * k, rz = 12 * k },
		RightUpperArm = { rx = -20 * k, rz = 50 * k },
		LeftUpperArm = { rx = -12 * k, rz = -45 * k },
		RightLowerArm = { rx = 30 * k },
		LeftLowerArm = { rx = 25 * k },
	})

	local dazed: Poses = merge(crouch(18 * k), {
		UpperTorso = { rx = -12 * k },
		Head = { rx = -22 * k, rz = 16 * k },
		RightUpperArm = { rx = 8, rz = 14 * k },
		LeftUpperArm = { rx = 5, rz = -12 * k },
		RightLowerArm = { rx = 10 },
		LeftLowerArm = { rx = 12 },
	})

	return {
		length = 1,
		looped = false,
		priority = "Action",
		keyframes = {
			kf(0, {}),
			kf(0.15, recoil),
			kf(0.5, dazed),
			kf(1, dazed),
		},
	}
end

-- Collapse and lie still; a one-shot that holds its last frame.
--
-- LowerTorso rotates the whole body about the hips, so "forward" for a limb
-- turns with it: on a body lying on its back, a limb swung forward points up;
-- on a body lying face down, it points into the floor. Each fall direction
-- therefore gets its own limb poses. The workbench solves every pose against
-- the floor and fails if anything sinks through it.
local function death(backward: boolean): AnimationDef
	local side = if backward then 1 else -1

	local buckle: Poses = merge(crouch(35), {
		UpperTorso = { rx = -20 },
		Head = { rx = -25 },
		RightUpperArm = { rx = 20, rz = 20 },
		LeftUpperArm = { rx = 15, rz = -20 },
	})

	-- Half over with the hips still high. Dropping the hips before the body has
	-- tipped would drive the still-upright legs through the floor.
	local tipping: Poses = merge(crouch(35), {
		LowerTorso = { py = -0.9, rx = 50 * side, pz = 0.2 * side },
		UpperTorso = { rx = -10 * side },
		Head = { rx = 15 * side },
		RightUpperArm = { rx = if backward then 70 else -30, rz = 50 },
		LeftUpperArm = { rx = if backward then 60 else -30, rz = -50 },
	})

	-- Lying flat: the torso's centre about half a stud off the floor.
	local down: Poses = {
		LowerTorso = { py = -2.5, rx = 88 * side, pz = 0.6 * side },
		UpperTorso = { rx = 6 * side },
		Head = { rx = 10 * side, rz = 20 },
		-- Arms out to the sides, lying along the floor.
		RightUpperArm = { rx = if backward then 40 else -10, rz = 70 },
		LeftUpperArm = { rx = if backward then 30 else -10, rz = -65 },
		RightLowerArm = { rx = if backward then 15 else 0 },
		LeftLowerArm = { rx = if backward then 20 else 0 },
		-- On the back, knees rise; face down, the lower legs lift behind.
		RightUpperLeg = { rx = if backward then 10 else -5 },
		LeftUpperLeg = { rx = if backward then 25 else -10 },
		RightLowerLeg = { rx = if backward then -15 else -30 },
		LeftLowerLeg = { rx = if backward then -40 else -50 },
	}

	local settled = merge(down, {
		Head = { rx = 14 * side, rz = 28 },
		RightUpperArm = { rx = if backward then 45 else -10, rz = 80 },
	})

	return {
		length = 1.2,
		looped = false,
		priority = "Action",
		keyframes = {
			kf(0, {}),
			kf(0.35, buckle),
			kf(0.6, tipping, "Linear"),
			kf(0.8, down),
			kf(1.2, settled),
		},
	}
end

-- An attack or swing: rest, the windup peaking at `windupAt`, the strike at
-- `impact`, an optional recovery pose halfway back, and rest by `length`.
local function strike(length: number, impact: number, windupAt: number, windup: Poses, hit: Poses, recovery: Poses?): AnimationDef
	local keyframes = {
		kf(0, {}),
		-- Linear from the windup peak into the strike, so the hit snaps.
		kf(windupAt, windup, "Linear"),
		kf(impact, hit),
	}

	if recovery then
		table.insert(keyframes, kf(impact + (length - impact) * 0.5, recovery))
	end

	table.insert(keyframes, kf(length, {}))

	return {
		length = length,
		looped = false,
		priority = "Action",
		impact = impact,
		keyframes = keyframes,
	}
end

-- The same idle, re-labelled for walking: for a rig that never moves, so
-- every enemy still has the full basic set.
local function standIn(anim: AnimationDef): AnimationDef
	local copy = table.clone(anim)
	copy.priority = "Movement"
	return copy
end

--[[ Training Dummy: a stiff, wobbly wooden mannequin ]]

local dummyIdle = idle({
	length = 3,
	lean = 0,
	breathe = 2,
	armForward = 0,
	armOut = 8,
	elbow = 5,
	knee = 0,
	headTilt = 0,
	sway = 1,
})

local TrainingDummy: { [string]: AnimationDef } = {
	idle = dummyIdle,
	walk = standIn(dummyIdle),
	stagger = stagger(0.8),
	death = death(true),

	[AnimationDefs.attack("Overhead")] = strike(1.0, 0.6, 0.45, {
		UpperTorso = { rx = 12 },
		Head = { rx = 8 },
		RightUpperArm = { rx = 165, rz = 10 },
		LeftUpperArm = { rx = 165, rz = -10 },
		RightLowerArm = { rx = 20 },
		LeftLowerArm = { rx = 20 },
	}, {
		LowerTorso = { py = -0.1 },
		UpperTorso = { rx = -22 },
		Head = { rx = -10 },
		RightUpperArm = { rx = 45, rz = 5 },
		LeftUpperArm = { rx = 45, rz = -5 },
		RightLowerArm = { rx = 10 },
		LeftLowerArm = { rx = 10 },
	}),

	[AnimationDefs.attack("GroundSlam")] = strike(1.2, 0.7, 0.5, {
		LowerTorso = { py = 0.2 },
		UpperTorso = { rx = 15 },
		RightUpperArm = { rx = 170, rz = 25 },
		LeftUpperArm = { rx = 170, rz = -25 },
	}, merge(crouch(35), {
		UpperTorso = { rx = -35 },
		Head = { rx = -15 },
		RightUpperArm = { rx = 70, rz = 15 },
		LeftUpperArm = { rx = 70, rz = -15 },
	})),
}

--[[ Skeleton Warrior: stiff and rattling, sword in the right hand ]]

local SkeletonWarrior: { [string]: AnimationDef } = {
	idle = idle({
		length = 2.4,
		lean = -4,
		breathe = 2,
		armForward = 8,
		armOut = 6,
		elbow = 25,
		knee = 8,
		headTilt = 6,
		sway = 2,
	}),
	walk = walk({
		length = 1.0,
		stride = 22,
		armSwing = 12,
		knee = 25,
		lean = -5,
		bob = 0.06,
		twist = 4,
		rock = 0,
		armForward = 8,
		armOut = 6,
		elbow = 20,
		limp = 0,
	}),
	stagger = stagger(1.1),
	death = death(true),

	-- A right-to-left horizontal slash. Short telegraph (0.5 s), so the windup
	-- is compact.
	[AnimationDefs.attack("Slash")] = strike(0.8, 0.35, 0.25, {
		UpperTorso = { ry = -35 },
		RightUpperArm = { rx = 100, rz = 70 },
		RightLowerArm = { rx = 40 },
		LeftUpperArm = { rx = 30, rz = -20 },
	}, {
		UpperTorso = { rx = -12, ry = 30 },
		RightUpperArm = { rx = 80, rz = -10 },
		RightLowerArm = { rx = 10 },
		LeftUpperArm = { rx = 20, rz = -30 },
	}),

	-- Two-handed, sword driven into the floor.
	[AnimationDefs.attack("GroundSlam")] = strike(1.1, 0.6, 0.45, {
		LowerTorso = { py = 0.15 },
		UpperTorso = { rx = 18 },
		RightUpperArm = { rx = 170, rz = 8 },
		LeftUpperArm = { rx = 170, rz = -8 },
		RightLowerArm = { rx = 15 },
		LeftLowerArm = { rx = 15 },
	}, merge(crouch(40), {
		UpperTorso = { rx = -40 },
		Head = { rx = -20 },
		RightUpperArm = { rx = 95, rz = -5 },
		LeftUpperArm = { rx = 95, rz = 5 },
	}), merge(crouch(25), {
		UpperTorso = { rx = -25 },
		RightUpperArm = { rx = 70 },
		LeftUpperArm = { rx = 70 },
	})),
}

--[[ Shambler: a hunched zombie dragging its left leg, arms reaching out ]]

local Shambler: { [string]: AnimationDef } = {
	idle = idle({
		length = 2.8,
		lean = -18,
		breathe = 3,
		armForward = 70,
		armOut = 8,
		elbow = 15,
		knee = 15,
		headTilt = -12,
		sway = 5,
	}),
	walk = walk({
		length = 1.4,
		stride = 18,
		armSwing = 6,
		knee = 30,
		lean = -20,
		bob = 0.12,
		twist = 8,
		rock = 3,
		armForward = 75,
		armOut = 6,
		elbow = 12,
		limp = 0.6,
	}),
	stagger = stagger(1.0),
	death = death(false),

	-- Both arms rear up and rake down.
	[AnimationDefs.attack("Claw")] = strike(0.9, 0.5, 0.35, {
		UpperTorso = { rx = 10 },
		Head = { rx = 15 },
		RightUpperArm = { rx = 150, rz = 30 },
		LeftUpperArm = { rx = 150, rz = -30 },
		RightLowerArm = { rx = 60 },
		LeftLowerArm = { rx = 60 },
	}, {
		LowerTorso = { pz = -0.3 },
		UpperTorso = { rx = -35 },
		Head = { rx = -10 },
		RightUpperArm = { rx = 60, rz = 10 },
		LeftUpperArm = { rx = 60, rz = -10 },
		RightLowerArm = { rx = 5 },
		LeftLowerArm = { rx = 5 },
	}, {
		UpperTorso = { rx = -18 },
		RightUpperArm = { rx = 70 },
		LeftUpperArm = { rx = 70 },
	}),

	-- Coils low, then springs forward — the body visibly lurches ahead, though
	-- the hitbox itself stays put.
	[AnimationDefs.attack("Lunge")] = strike(1.3, 0.7, 0.55, merge(crouch(40), {
		UpperTorso = { rx = -30 },
		Head = { rx = 20 },
		RightUpperArm = { rx = -40, rz = 20 },
		LeftUpperArm = { rx = -40, rz = -20 },
	}), {
		LowerTorso = { pz = -1.4, py = 0.1 },
		UpperTorso = { rx = -50 },
		Head = { rx = 15 },
		RightUpperArm = { rx = 95, rz = 5 },
		LeftUpperArm = { rx = 95, rz = -5 },
		RightUpperLeg = { rx = -25 },
		LeftUpperLeg = { rx = 30 },
		LeftLowerLeg = { rx = -30 },
	}, {
		LowerTorso = { pz = -0.7 },
		UpperTorso = { rx = -30 },
		RightUpperArm = { rx = 60 },
		LeftUpperArm = { rx = 60 },
	}),
}

--[[ Spitter: bloated, heaving, waddling side to side ]]

local Spitter: { [string]: AnimationDef } = {
	idle = idle({
		length = 2.0,
		lean = 6,
		breathe = 5,
		armForward = 10,
		armOut = 20,
		elbow = 30,
		knee = 12,
		headTilt = 0,
		sway = 0,
	}),
	walk = walk({
		length = 1.0,
		stride = 14,
		armSwing = 8,
		knee = 20,
		lean = 6,
		bob = 0.08,
		twist = 0,
		rock = 10,
		armForward = 10,
		armOut = 25,
		elbow = 30,
		limp = 0,
	}),
	stagger = stagger(0.9),
	death = death(true),

	-- Rears back gathering acid, then snaps forward.
	[AnimationDefs.attack("Spit")] = strike(1.2, 0.75, 0.6, merge(crouch(10), {
		UpperTorso = { rx = 25 },
		Head = { rx = 35 },
		RightUpperArm = { rz = 35 },
		LeftUpperArm = { rz = -35 },
	}), {
		UpperTorso = { rx = -25 },
		Head = { rx = -30 },
		RightUpperArm = { rx = -30, rz = 30 },
		LeftUpperArm = { rx = -30, rz = -30 },
	}),

	-- Swells, then bursts outward in every direction.
	[AnimationDefs.attack("Spray")] = strike(1.1, 0.6, 0.45, merge(crouch(25), {
		UpperTorso = { rx = -10 },
		RightUpperArm = { rx = 40, rz = -20 },
		LeftUpperArm = { rx = 40, rz = 20 },
		RightLowerArm = { rx = 60 },
		LeftLowerArm = { rx = 60 },
	}), {
		LowerTorso = { py = 0.25 },
		UpperTorso = { rx = 20 },
		Head = { rx = 30 },
		RightUpperArm = { rz = 100 },
		LeftUpperArm = { rz = -100 },
	}),
}

--[[ Players: combat overlays on a real R15 avatar ]]

local R15Player: { [string]: AnimationDef } = {
	-- An overhead chop, shield held forward.
	[AnimationDefs.swing("SwordAndShield")] = strike(0.9, 0.45, 0.3, {
		UpperTorso = { rx = 8, ry = -15 },
		RightUpperArm = { rx = 160, rz = 15 },
		RightLowerArm = { rx = 35 },
		LeftUpperArm = { rx = 55, rz = -15 },
		LeftLowerArm = { rx = 60 },
	}, {
		UpperTorso = { rx = -15, ry = 10 },
		RightUpperArm = { rx = 40, rz = 5 },
		RightLowerArm = { rx = 10 },
		LeftUpperArm = { rx = 55, rz = -15 },
		LeftLowerArm = { rx = 60 },
	}),

	-- A quick stab from a guard.
	[AnimationDefs.swing("Daggers")] = strike(0.5, 0.2, 0.12, {
		UpperTorso = { ry = -20 },
		RightUpperArm = { rx = 30, rz = 20 },
		RightLowerArm = { rx = 100 },
		LeftUpperArm = { rx = 50, rz = -25 },
		LeftLowerArm = { rx = 80 },
	}, {
		UpperTorso = { rx = -8, ry = 18 },
		RightUpperArm = { rx = 95 },
		RightLowerArm = { rx = 0 },
		LeftUpperArm = { rx = 50, rz = -25 },
		LeftLowerArm = { rx = 80 },
	}),

	-- A two-handed sweep across the body.
	[AnimationDefs.swing("Staff")] = strike(0.8, 0.35, 0.22, {
		UpperTorso = { ry = -40 },
		RightUpperArm = { rx = 70, rz = 40 },
		LeftUpperArm = { rx = 80, rz = 10 },
		RightLowerArm = { rx = 40 },
		LeftLowerArm = { rx = 60 },
	}, {
		UpperTorso = { ry = 40 },
		RightUpperArm = { rx = 85, rz = -15 },
		LeftUpperArm = { rx = 70, rz = -40 },
		RightLowerArm = { rx = 20 },
		LeftLowerArm = { rx = 20 },
	}),

	-- Forearms snap up in front of the face and hold through the window.
	[AnimationDefs.PARRY] = {
		length = 0.55,
		looped = false,
		priority = "Action",
		keyframes = {
			kf(0, {}, "Linear"),
			kf(0.08, {
				UpperTorso = { rx = -6 },
				Head = { rx = -5 },
				RightUpperArm = { rx = 85, rz = -30 },
				LeftUpperArm = { rx = 85, rz = 30 },
				RightLowerArm = { rx = 75 },
				LeftLowerArm = { rx = 75 },
			}),
			kf(0.4, {
				UpperTorso = { rx = -6 },
				Head = { rx = -5 },
				RightUpperArm = { rx = 85, rz = -30 },
				LeftUpperArm = { rx = 85, rz = 30 },
				RightLowerArm = { rx = 75 },
				LeftLowerArm = { rx = 75 },
			}),
			kf(0.55, {}),
		},
	},
}

-- rigId -> animation name -> animation.
AnimationDefs.BY_RIG = {
	TrainingDummy = TrainingDummy,
	SkeletonWarrior = SkeletonWarrior,
	Shambler = Shambler,
	Spitter = Spitter,
	[RigDefs.PLAYER_RIG] = R15Player,
}

function AnimationDefs.get(rigId: string, name: string): AnimationDef?
	local rig = AnimationDefs.BY_RIG[rigId]
	return rig and rig[name]
end

return AnimationDefs
