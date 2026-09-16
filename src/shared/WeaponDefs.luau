-- weaponId -> class, stats, moveset. Only Tank exists until the class
-- framework (build order step 2) adds equip/switch and the rest of the roster.

local WeaponDefs = {
	Tank = {
		class = "Tank",
		baseDamage = 10,
		swingCooldown = 0.5,
	},
}

return WeaponDefs
