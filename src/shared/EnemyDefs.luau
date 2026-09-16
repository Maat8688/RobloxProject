-- enemyId -> hp, encounterGroupId, rewards, attacks. Each attack carries its
-- own damage/range/telegraphDuration/parryable — the enemy AI (Enemy.luau)
-- picks randomly among an enemy's attacks each cycle, so adding a new enemy
-- here is enough to give it a distinct moveset.
--
-- encounterGroupId stays nil for now: chest-gating (DungeonGenerator +
-- ChestService) currently guards each room's chest with that room's single
-- enemy directly, since every combat room only ever has one enemy. This
-- field is for when a chest needs a real multi-enemy encounter group.
--
-- coinReward/crystalReward are what CurrencyService pays the killer. Only
-- tougher enemies set crystalReward above 0 — that's what keeps trash-mob
-- grinding away from the top blacksmith tiers (DESIGN.md).

local EnemyDefs = {
	TrainingDummy = {
		hp = 60,
		encounterGroupId = nil,
		coinReward = 10,
		crystalReward = 0,
		attacks = {
			Swing = {
				telegraphDuration = 0.6,
				parryable = true,
				damage = 15,
				range = 8,
			},
		},
	},

	-- Tougher, two attacks: an ordinary parryable Slash and an unparryable
	-- GroundSlam AoE. GroundSlam can't be blocked by timing at all — the
	-- only way to avoid it is to not be within its (larger) range when it
	-- resolves, per DESIGN.md's "some attacks are deliberately unparryable"
	-- decision.
	SkeletonWarrior = {
		hp = 80,
		encounterGroupId = nil,
		coinReward = 25,
		crystalReward = 1,
		attacks = {
			Slash = {
				telegraphDuration = 0.5,
				parryable = true,
				damage = 12,
				range = 8,
			},
			GroundSlam = {
				telegraphDuration = 0.9,
				parryable = false,
				damage = 25,
				range = 14,
			},
		},
	},
}

return EnemyDefs
