--!strict
-- enemyType -> a loot descriptor. Pure data — no Roblox API.
--
-- What a chest holds reflects which enemy guarded it (DESIGN.md pillar), not a
-- random roll — rarity is fixed per enemy type. classTag is nil throughout:
-- these are neutral materials and mementos, not class-specific gear (a chest
-- dropping real class gear would set classTag to match a Classes entry).
--
-- Every EnemyDefs entry needs a row here. The dungeon can put any enemy type
-- in charge of a chest, and a missing row would fail at the moment a player
-- opens it. A test enforces the pairing.

export type LootDescriptor = {
	itemId: string,
	name: string,
	flavor: string,
	rarity: string,
	classTag: string?,
}

local LootTables: { [string]: LootDescriptor } = {
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
	Shambler = {
		itemId = "RottedClaw",
		name = "Rotted Claw",
		flavor = "Still twitching. It kept coming right up until it didn't.",
		rarity = "common",
		classTag = nil,
	},
	Spitter = {
		itemId = "AcidGland",
		name = "Acid Gland",
		flavor = "Handle with gloves. It was aiming for your face.",
		rarity = "common",
		classTag = nil,
	},
	HollowKing = {
		itemId = "HollowCrownShard",
		name = "Hollow Crown Shard",
		flavor = "Still cold. The king is gone; the crown remembers.",
		rarity = "epic",
		classTag = nil,
	},
}

return LootTables
