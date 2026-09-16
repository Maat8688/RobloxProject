--!strict
-- weaponId -> class, parry profile, attack profile, parry payoff.
-- Pure data — no Roblox API.
--
-- Class is derived from the equipped weapon (DESIGN.md: "Class = equipped
-- weapon"), so classTag lives here and there is deliberately no ClassDefs
-- module. Switching weapon switches class because there is nowhere else for
-- class to be stored.
--
-- Everything that differentiates a class is data in this file. Adding a class
-- is adding a row, not writing code — which is why DESIGN.md's open question
-- about a fixed roster doesn't need answering before step 2.

export type ParryProfile = {
	-- Tolerances are measured from the moment of impact, not from the start of
	-- the windup. Early is the wider half on purpose: players anticipate the
	-- hit, so pressing slightly early is the common honest mistake.
	earlyTolerance: number,
	lateTolerance: number,
}

-- What a successful parry buys you. This is where "skill must count as much as
-- level/gear" is expressed per class: every class can parry, but each converts
-- a parry into a different advantage.
export type ParryPayoff = {
	-- Scales CombatConstants.STAGGER_DURATION.
	staggerMultiplier: number,
	-- Health restored to the parrying player.
	selfHeal: number,
	-- Seconds of amplified outgoing damage after a successful parry.
	riposteDuration: number,
	riposteMultiplier: number,
}

export type AttackProfile = {
	-- Player-side windup before the swing lands. Long enough to be committal,
	-- so attacking into a telegraph is a real decision.
	windup: number,
	damage: number,
	range: number,
	arcDegrees: number,
	cooldown: number,
	staminaCost: number,
}

export type WeaponDef = {
	displayName: string,
	classTag: string,
	parry: ParryProfile,
	payoff: ParryPayoff,
	attack: AttackProfile,
}

local WeaponDefs: { [string]: WeaponDef } = {
	-- Widest window in the game (ARCHITECTURE.md: Tank is "wide/forgiving").
	-- Converts a parry into control rather than damage — the shield-bash
	-- counter in ARCHITECTURE.md is the long stagger, giving allies a window.
	SwordAndShield = {
		displayName = "Sword & Shield",
		classTag = "Tank",
		parry = {
			earlyTolerance = 0.20,
			lateTolerance = 0.10,
		},
		payoff = {
			staggerMultiplier = 1.5,
			selfHeal = 0,
			riposteDuration = 0,
			riposteMultiplier = 1,
		},
		attack = {
			windup = 0.45,
			damage = 12,
			range = 11,
			arcDegrees = 110,
			cooldown = 0.9,
			staminaCost = 12,
		},
	},

	-- Tight window, high payoff (ARCHITECTURE.md: "tight parry window, high
	-- backstab payoff"). The riposte is where that payoff lives until
	-- positional backstabs exist.
	Daggers = {
		displayName = "Daggers",
		classTag = "Assassin",
		parry = {
			earlyTolerance = 0.08,
			lateTolerance = 0.05,
		},
		payoff = {
			staggerMultiplier = 0.8,
			selfHeal = 0,
			riposteDuration = 2.5,
			riposteMultiplier = 2.5,
		},
		attack = {
			windup = 0.2,
			damage = 6,
			range = 8,
			arcDegrees = 70,
			cooldown = 0.4,
			staminaCost = 7,
		},
	},

	-- Healing is tied to the skill loop rather than a passive HoT (DESIGN.md).
	-- Self-heal is the solo-testable half of that; the "parry near allies
	-- triggers burst heal" half needs allies and lands at build-order step 8.
	Staff = {
		displayName = "Staff",
		classTag = "Healer",
		parry = {
			earlyTolerance = 0.14,
			lateTolerance = 0.08,
		},
		payoff = {
			staggerMultiplier = 1.0,
			selfHeal = 14,
			riposteDuration = 0,
			riposteMultiplier = 1,
		},
		attack = {
			windup = 0.35,
			damage = 8,
			range = 12,
			arcDegrees = 90,
			cooldown = 0.7,
			staminaCost = 9,
		},
	},
}

return WeaponDefs
