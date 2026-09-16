-- weaponId -> class, stats, moveset. Class = equipped weapon: there is no
-- separate class stat anywhere else. parryWindow/swingRange live per-weapon
-- so "Tank: wide/forgiving parry" vs. "Assassin: tight parry" (see
-- ARCHITECTURE.md's Classes registry) are real, not just descriptive text.
--
-- Mage isn't here yet — DESIGN.md flags it as the deliberate exception where
-- magic replaces basic combat rather than enhancing it, which needs a
-- different combat model, not just another row in this table.

local WeaponDefs = {
	Tank = {
		class = "Tank",
		baseDamage = 10,
		swingCooldown = 0.5,
		parryWindow = 0.20,
		swingRange = 8,
	},
	Assassin = {
		class = "Assassin",
		baseDamage = 14,
		swingCooldown = 0.35,
		parryWindow = 0.08,
		swingRange = 6,
	},
	Healer = {
		class = "Healer",
		baseDamage = 6,
		swingCooldown = 0.6,
		parryWindow = 0.15,
		swingRange = 8,
	},
}

return WeaponDefs
