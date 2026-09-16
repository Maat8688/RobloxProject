--!strict
-- enemyId -> stats and attack timelines.
-- Pure data — no Roblox API.
--
-- The vertical slice ships one enemy. Generalising this across enemy types is
-- build-order step 3.

export type AttackDef = {
	-- Seconds from the start of the windup to impact. The parry window is
	-- positioned relative to impact by ParryMath.
	telegraphDuration: number,
	-- DESIGN.md requires some attacks to be unparryable, so the answer to
	-- every enemy is never just "parry everything". Present from the start
	-- because retrofitting it later means re-tuning every encounter.
	parryable: boolean,
	damage: number,
	-- Server-side hit-reg volume, checked against the character's server
	-- position at the moment of impact.
	range: number,
	arcDegrees: number,
}

export type EnemyDef = {
	displayName: string,
	maxHealth: number,
	-- Idle time between recovering and winding up the next attack.
	attackInterval: number,
	attacks: { [string]: AttackDef },
	attackOrder: { string },
}

local EnemyDefs: { [string]: EnemyDef } = {
	TrainingDummy = {
		displayName = "Training Dummy",
		maxHealth = 100,
		attackInterval = 1.0,
		attacks = {
			Overhead = {
				telegraphDuration = 1.2,
				parryable = true,
				damage = 15,
				range = 10,
				arcDegrees = 120,
			},
			-- Deliberately unparryable: the player has to move out of it.
			GroundSlam = {
				telegraphDuration = 1.8,
				parryable = false,
				damage = 20,
				range = 14,
				arcDegrees = 360,
			},
		},
		-- Fixed rotation rather than random, so tuning sessions are
		-- reproducible. Real selection logic arrives with EnemyAI in step 3.
		attackOrder = { "Overhead", "Overhead", "GroundSlam" },
	},
}

return EnemyDefs
