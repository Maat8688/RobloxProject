--!strict
-- enemyId -> stats, movement, and attack timelines.
-- Pure data — no Roblox API.
--
-- Behaviour is data, not code. An enemy is defined by its attack band
-- (minRange/maxRange), how it wants to position (preferredRange), and how it
-- weights its options — so a kiting ranged enemy and a charging melee one come
-- out of the same selector with no per-enemy branches. Adding an enemy type
-- should be adding a row here.

export type AttackDef = {
	-- Seconds from the start of the windup to impact. The parry window is
	-- positioned relative to impact by ParryMath.
	telegraphDuration: number,
	-- DESIGN.md requires some attacks to be unparryable, so the answer to
	-- every enemy is never just "parry everything".
	parryable: boolean,
	damage: number,
	-- Server-side hit-reg volume, checked against the character's server
	-- position at the moment of impact.
	range: number,
	arcDegrees: number,
	-- Band in which this attack is a legal choice. An attack whose minRange is
	-- above zero is a spacing tool the enemy won't use point-blank.
	minRange: number,
	maxRange: number,
	-- Relative likelihood among all currently-legal attacks.
	weight: number,
	-- Per-attack cooldown, so a heavy hit can't be chained.
	cooldown: number,
}

export type EnemyDef = {
	displayName: string,
	maxHealth: number,
	-- Idle beat between finishing one action and choosing the next.
	attackInterval: number,
	-- Distance the enemy tries to hold. Above it they close, below it they
	-- back off — which is what makes a ranged type kite without special-casing.
	preferredRange: number,
	-- Studs per second. Zero means stationary.
	moveSpeed: number,
	-- Beyond this the enemy ignores the player entirely.
	aggroRange: number,
	attacks: { [string]: AttackDef },
}

local EnemyDefs: { [string]: EnemyDef } = {
	-- Stationary tuning target. Deliberately kept as the one enemy that never
	-- moves, so parry timing can be measured without chasing anything.
	TrainingDummy = {
		displayName = "Training Dummy",
		maxHealth = 100,
		attackInterval = 1.0,
		preferredRange = 0,
		moveSpeed = 0,
		aggroRange = 60,
		attacks = {
			Overhead = {
				telegraphDuration = 1.2,
				parryable = true,
				damage = 15,
				range = 10,
				arcDegrees = 120,
				minRange = 0,
				maxRange = 10,
				weight = 3,
				cooldown = 0,
			},
			-- Deliberately unparryable: the player has to move out of it.
			GroundSlam = {
				telegraphDuration = 1.8,
				parryable = false,
				damage = 20,
				range = 14,
				arcDegrees = 360,
				minRange = 0,
				maxRange = 14,
				weight = 1,
				cooldown = 6,
			},
		},
	},

	-- Aggressive melee. Closes to touching range and pressures with a fast
	-- parryable swing, punishing players who only ever back away.
	Shambler = {
		displayName = "Shambler",
		maxHealth = 70,
		attackInterval = 0.6,
		preferredRange = 6,
		moveSpeed = 9,
		aggroRange = 70,
		attacks = {
			Claw = {
				telegraphDuration = 0.8,
				parryable = true,
				damage = 10,
				range = 9,
				arcDegrees = 100,
				minRange = 0,
				maxRange = 9,
				weight = 4,
				cooldown = 0,
			},
			-- A gap-closer: only legal from range, so it reads as a lunge
			-- rather than another melee swing.
			Lunge = {
				telegraphDuration = 1.1,
				parryable = true,
				damage = 16,
				range = 18,
				arcDegrees = 60,
				minRange = 9,
				maxRange = 20,
				weight = 3,
				cooldown = 4,
			},
		},
	},

	-- Ranged. Its preferredRange sits outside its own melee, so the shared
	-- movement rule makes it kite without any kiting-specific code.
	Spitter = {
		displayName = "Spitter",
		maxHealth = 45,
		attackInterval = 1.2,
		preferredRange = 28,
		moveSpeed = 7,
		aggroRange = 80,
		attacks = {
			Spit = {
				telegraphDuration = 1.4,
				parryable = true,
				damage = 12,
				range = 34,
				arcDegrees = 25,
				minRange = 12,
				maxRange = 34,
				weight = 4,
				cooldown = 1.5,
			},
			-- Unparryable panic option when something is in its face, so
			-- closing the gap isn't a free win.
			Spray = {
				telegraphDuration = 1.0,
				parryable = false,
				damage = 8,
				range = 12,
				arcDegrees = 360,
				minRange = 0,
				maxRange = 12,
				weight = 5,
				cooldown = 5,
			},
		},
	},
}

return EnemyDefs
