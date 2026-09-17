--!strict
-- weaponId -> class, parry profile, attack profile, parry payoff.
-- Pure data — no Roblox API.
--
-- Class is derived from the equipped weapon (DESIGN.md: "Class = equipped
-- weapon"), so classTag lives here and there is deliberately no ClassDefs
-- module. Keying by weapon rather than by class also leaves room for a class
-- to have more than one weapon (ARCHITECTURE.md lists "Staff / Mace" for the
-- Healer) without restructuring.
--
-- Everything that differentiates a class is data in this file. Adding a class
-- is adding a row, not writing code — there should never be an
-- `if classTag == "..."` branch anywhere in combat.
--
-- Mage isn't here yet: DESIGN.md flags it as the deliberate exception where
-- magic replaces basic combat, which needs its own combat model rather than
-- another row.

export type ParryProfile = {
	-- Tolerances are measured from the moment of impact, not from the start of
	-- the windup. Early is the wider half on purpose: players anticipate the
	-- hit, so pressing slightly early is the common honest mistake.
	earlyTolerance: number,
	lateTolerance: number,
}

-- What a successful parry buys you, on top of the universal stagger punish
-- bonus in CombatConstants. This is where "skill must count as much as
-- level/gear" is expressed per class: every class can parry, but each converts
-- a parry into a different advantage.
export type ParryPayoff = {
	-- Scales CombatConstants.STAGGER_DURATION — a longer punish window for
	-- everyone attacking that enemy.
	staggerMultiplier: number,
	-- Health restored to the parrying player AND every other player within
	-- burstHealRadius. Tied to the parry rather than a passive heal-over-time,
	-- per DESIGN.md's healer pillar.
	burstHeal: number,
	burstHealRadius: number,
	-- Seconds of amplified outgoing damage after a successful parry.
	riposteDuration: number,
	riposteMultiplier: number,
}

export type AttackProfile = {
	-- Player-side windup before a PvE swing lands. Long enough to be
	-- committal, so attacking into a telegraph is a real decision.
	windup: number,
	-- How long this weapon's swing telegraphs to a duel opponent before it
	-- resolves. Players have no EnemyDefs entry to read this from, so it lives
	-- here. Tracks each class's parry identity: the Tank is slowest and easiest
	-- to punish, the Assassin fastest and hardest to react to.
	pvpTelegraph: number,
	-- Base damage before blacksmith upgrades (EconomyDefs.upgradedDamage).
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
	-- Converts a parry into control rather than damage: the longer stagger is a
	-- longer double-damage window for the whole group.
	SwordAndShield = {
		displayName = "Sword & Shield",
		classTag = "Tank",
		parry = {
			earlyTolerance = 0.20,
			lateTolerance = 0.10,
		},
		payoff = {
			staggerMultiplier = 1.5,
			burstHeal = 0,
			burstHealRadius = 0,
			riposteDuration = 0,
			riposteMultiplier = 1,
		},
		attack = {
			windup = 0.45,
			pvpTelegraph = 0.5,
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
			burstHeal = 0,
			burstHealRadius = 0,
			riposteDuration = 2.5,
			riposteMultiplier = 2.5,
		},
		attack = {
			windup = 0.2,
			pvpTelegraph = 0.3,
			damage = 6,
			range = 8,
			arcDegrees = 70,
			cooldown = 0.4,
			staminaCost = 7,
		},
	},

	-- The parry-triggered burst heal is what makes the Healer near-
	-- indispensable (DESIGN.md): healing lives in the skill loop, and it reaches
	-- allies, so a group without a Healer can't undo the chip damage and bleeds
	-- that dungeons are tuned around.
	Staff = {
		displayName = "Staff",
		classTag = "Healer",
		parry = {
			earlyTolerance = 0.14,
			lateTolerance = 0.08,
		},
		payoff = {
			staggerMultiplier = 1.0,
			burstHeal = 25,
			burstHealRadius = 20,
			riposteDuration = 0,
			riposteMultiplier = 1,
		},
		attack = {
			windup = 0.35,
			pvpTelegraph = 0.45,
			damage = 8,
			range = 12,
			arcDegrees = 90,
			cooldown = 0.7,
			staminaCost = 9,
		},
	},
}

return WeaponDefs
