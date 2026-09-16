-- Economy tuning: what an upgrade costs and what it gives. Per-enemy payout
-- (coinReward/crystalReward) lives in EnemyDefs instead, next to that enemy's
-- hp/attacks — same split as WeaponDefs holding per-weapon numbers while
-- CombatConstants holds the shared combat tunables.
--
-- Shared rather than server-only so the client can show the next upgrade's
-- price at the anvil without a round trip. The server never trusts the client
-- with any of it — BlacksmithService recomputes the cost before charging.

local EconomyDefs = {}

EconomyDefs.MAX_UPGRADE_LEVEL = 5

-- Each level multiplies the weapon's baseDamage by this much (level 5 = +50%).
-- Deliberately smaller than the 2x staggered-hit bonus in CombatConstants:
-- DESIGN.md's "skill must count as much as level/gear" means a fully upgraded
-- weapon must not out-earn landing parries.
EconomyDefs.DAMAGE_BONUS_PER_UPGRADE_LEVEL = 0.10

-- Upgrades past this level also cost crystals, which only tougher enemies drop
-- (see EnemyDefs.crystalReward). This is the mechanism behind DESIGN.md's
-- "trash-mob grinding alone can't reach max gear" — no amount of TrainingDummy
-- farming produces a single crystal.
EconomyDefs.CRYSTAL_TIER_THRESHOLD = 2

local BASE_COIN_COST = 50

-- Cost to go from `currentLevel` to the next one. Coins scale triangularly
-- (50 / 150 / 300 / 500 / 750), crystals only appear past the threshold.
-- `crystalType` is the class id of the weapon being upgraded — crystals are
-- class-specific on purpose, so respeccing means re-earning them (DESIGN.md).
function EconomyDefs.GetUpgradeCost(currentLevel)
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

return EconomyDefs
