--!strict
-- Tunable combat values. Pure data — no Roblox API, so it can be required from
-- anywhere including headless tests.
--
-- Per-weapon numbers live in WeaponDefs and per-attack numbers in EnemyDefs;
-- this file holds only what is shared across all of them.
--
-- Nothing here has had a real tuning pass. If a value changes meaningfully,
-- log why in DESIGN.md's decision log.

local CombatConstants = {}

--[[ Parry timestamp authority ]]

-- The client stamps its parry with the synchronised server clock, and the
-- server checks that claim against its own estimate of when the press could
-- have been sent: receipt time minus half the player's round-trip ping.
--
-- A claim is trusted only within this tolerance of that estimate. Without the
-- check, a client that knows impactTime (it must, to draw the telegraph) could
-- send `timestamp = impactTime` at any point in a wide window and collect a
-- perfect parry every time. The tolerance covers honest one-way jitter, which
-- grows with ping, hence the ping-proportional term.
CombatConstants.MIN_TIMESTAMP_TOLERANCE = 0.05
CombatConstants.TIMESTAMP_TOLERANCE_PING_FRACTION = 0.5

-- Hard limits applied regardless of ping, so a spoofed or absurd ping reading
-- can never widen the trusted band without bound.
CombatConstants.MAX_ACCEPTED_LATENCY = 0.4
CombatConstants.FUTURE_TOLERANCE = 0.05

-- Extra reach beyond an attack's own range within which a player may still
-- parry it. A player can only parry an attack that could plausibly hit them —
-- otherwise, with several rooms running, a press could resolve against an
-- enemy swinging at someone else entirely.
CombatConstants.PARRY_RANGE_MARGIN = 4

--[[ Stamina ]]

-- Stamina gates parry spam. Without it, mashing the key beats the timing
-- system outright, which would contradict "skill must count" in DESIGN.md.
CombatConstants.MAX_STAMINA = 100
CombatConstants.STAMINA_REGEN_PER_SECOND = 20
CombatConstants.PARRY_STAMINA_COST = 15

-- Lockout applied after a failed parry, so a whiff has a real cost.
CombatConstants.WHIFF_LOCKOUT = 0.5

--[[ Stagger and punish ]]

-- How long an enemy is stunned after a successful parry, before the parrying
-- class's staggerMultiplier is applied. Shortened from 1.5 when the punish
-- bonus below was introduced: a stagger now carries double damage, and the
-- Tank's 1.5x payoff would otherwise make that window very long.
CombatConstants.STAGGER_DURATION = 1.2

-- Damage bonus for hitting a staggered target. This is the universal parry
-- payoff: every class's parry opens a punish window for the whole group, and
-- the Tank's longer stagger is what makes that window worth the most.
--
-- Deliberately larger than the maximum blacksmith upgrade (EconomyDefs), so a
-- fully upgraded weapon never out-earns landing parries — "skill must count as
-- much as level/gear", expressed as numbers. A test enforces the ordering.
CombatConstants.STAGGER_DAMAGE_MULTIPLIER = 2

-- Enemy recovery after a strike resolves, before it can wind up again.
CombatConstants.RECOVER_DURATION = 0.8

-- How long the server holds a strike open past impact before resolving damage,
-- so a parry pressed inside the late half of the window still has time to
-- arrive over the network.
--
-- A real tradeoff, and one playtesting has to settle: damage feedback lands
-- this many seconds after the visual impact, and a player whose round trip
-- exceeds it loses late-half parries they legitimately earned. The debug HUD
-- reports ping next to the parry delta so the two can be correlated.
CombatConstants.STRIKE_RESOLUTION_GRACE = 0.15

--[[ Encounters ]]

-- How long a killed enemy stays down before respawning in place. Chests stay
-- unlocked through respawns; the guard coming back is for repeat practice.
CombatConstants.ENEMY_RESPAWN_DELAY = 3

--[[ PvP ]]

-- Duel health is a virtual pool, not the real Humanoid — see PvP/Duelist.luau.
CombatConstants.PVP_STARTING_HEALTH = 100

return CombatConstants
