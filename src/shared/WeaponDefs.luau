--!strict
-- weaponId -> class, stats, parry profile.
-- Pure data — no Roblox API.
--
-- Class is derived from the equipped weapon (DESIGN.md: "Class = equipped
-- weapon"), so classTag lives here rather than on the player.
--
-- The vertical slice ships one weapon only. Additional weapons land in
-- build-order step 2.

export type ParryProfile = {
	-- Tolerances are measured from the moment of impact, not from the start of
	-- the windup. Early is the wider half on purpose: players anticipate the
	-- hit, so pressing slightly early is the common honest mistake.
	earlyTolerance: number,
	lateTolerance: number,
}

export type WeaponDef = {
	displayName: string,
	classTag: string,
	damage: number,
	parry: ParryProfile,
}

local WeaponDefs: { [string]: WeaponDef } = {
	SwordAndShield = {
		displayName = "Sword & Shield",
		classTag = "Tank",
		damage = 10,
		-- Widest window in the game (ARCHITECTURE.md: Tank is
		-- "wide/forgiving"), which makes it the right baseline to tune the
		-- whole system against before tighter classes exist.
		parry = {
			earlyTolerance = 0.20,
			lateTolerance = 0.10,
		},
	},
}

return WeaponDefs
