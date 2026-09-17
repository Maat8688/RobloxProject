-- enemyType -> a loot descriptor. What a chest holds reflects which enemy
-- guarded it (DESIGN.md pillar), not a random roll — rarity is fixed per
-- enemy type, not rolled. classTag is nil for both: these are neutral
-- materials/mementos, not class-specific gear (a chest dropping actual
-- class gear would set classTag to match a Classes entry).

local LootTables = {
	TrainingDummy = {
		itemId = "PracticeToken",
		name = "Practice Token",
		flavor = "A worn marker handed out for clearing the training dummy.",
		rarity = "common",
		classTag = nil,
	},
	SkeletonWarrior = {
		itemId = "BoneHiltShard",
		name = "Bone-Hilt Shard",
		flavor = "Salvaged from the warrior's blade after the fight.",
		rarity = "uncommon",
		classTag = nil,
	},
}

return LootTables
