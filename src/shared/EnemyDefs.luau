-- enemyId -> hp, encounterGroupId (nil until chest-gating exists), attacks.
-- Only TrainingDummy exists for the vertical slice; unparryable/must-dodge
-- attacks come with the generalized enemy AI (build order step 3).

local EnemyDefs = {
	TrainingDummy = {
		hp = 60,
		encounterGroupId = nil,
		attacks = {
			Swing = {
				telegraphDuration = 0.6,
				parryable = true,
				damage = 15,
			},
		},
	},
}

return EnemyDefs
