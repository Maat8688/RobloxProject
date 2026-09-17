--!strict
-- Economy tuning: what an upgrade costs and what it gives. Pure — no Roblox API.
--
-- Per-enemy payout (coinReward/crystalReward) lives in EnemyDefs instead, next
-- to that enemy's stats — the same split as WeaponDefs holding per-weapon
-- numbers while CombatConstants holds the shared ones.
--
-- Shared rather than server-only so the client can show the next upgrade's
-- price without a round trip. The server never trusts the client with any of
-- it: BlacksmithService recomputes the cost before charging.

local EconomyDefs = {}

EconomyDefs.MAX_UPGRADE_LEVEL = 5

-- Each level adds this fraction of the weapon's base damage (level 5 = +50%).
-- Deliberately smaller than CombatConstants.STAGGER_DAMAGE_MULTIPLIER's +100%:
-- DESIGN.md's "skill must count as much as level/gear" means a fully upgraded
-- weapon must never out-earn landing parries. A test enforces the ordering.
EconomyDefs.DAMAGE_BONUS_PER_UPGRADE_LEVEL = 0.10

-- Upgrades past this level also cost crystals, which only tougher enemies drop
-- (EnemyDefs.crystalReward). This is the mechanism behind DESIGN.md's
-- "trash-mob grinding alone can't reach max gear" — no amount of TrainingDummy
-- farming produces a single crystal.
EconomyDefs.CRYSTAL_TIER_THRESHOLD = 2

local BASE_COIN_COST = 50

export type UpgradeCost = {
	coins: number,
	crystals: number,
}

-- Cost to go from `currentLevel` to the next one. Coins scale triangularly
-- (50 / 150 / 300 / 500 / 750); crystals only appear past the threshold.
-- Crystals are keyed by the class of the weapon being upgraded — class-specific
-- on purpose, so respeccing means re-earning them (DESIGN.md).
function EconomyDefs.getUpgradeCost(currentLevel: number): UpgradeCost
	local nextLevel = currentLevel + 1

	local crystals = 0
	if nextLevel > EconomyDefs.CRYSTAL_TIER_THRESHOLD then
		crystals = nextLevel - EconomyDefs.CRYSTAL_TIER_THRESHOLD
	end

	return {
		coins = BASE_COIN_COST * nextLevel * (nextLevel + 1) / 2,
		crystals = crystals,
	}
end

-- A weapon's damage at a given upgrade level.
--
-- Computed on demand rather than by storing a scaled copy of the weapon def:
-- WeaponDefs entries are shared by every player and their attack profile is a
-- nested table, so scaling a shallow copy would silently upgrade that weapon
-- for the whole server, permanently.
function EconomyDefs.upgradedDamage(baseDamage: number, level: number): number
	return baseDamage * (1 + EconomyDefs.DAMAGE_BONUS_PER_UPGRADE_LEVEL * level)
end

return EconomyDefs
