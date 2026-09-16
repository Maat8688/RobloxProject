--!strict
-- Tunable combat values. Pure data — no Roblox API, so it can be required from
-- anywhere including headless tests.
--
-- Everything here is expected to move during the vertical-slice tuning pass.
-- If a value changes meaningfully, log why in DESIGN.md's decision log.

local CombatConstants = {}

-- How far past the client's claimed parry timestamp the server is willing to
-- rewind. This IS the latency compensation: an honest player on a bad
-- connection stays inside it, while a cheater can't claim an arbitrary past.
CombatConstants.MAX_ACCEPTED_LATENCY = 0.4

-- Slack for clock jitter between client and server. Anything claiming to be
-- further into the future than this is rejected outright.
CombatConstants.FUTURE_TOLERANCE = 0.05

-- Stamina gates parry spam. Without it, mashing the key beats the timing
-- system outright, which would contradict "skill must count" in DESIGN.md.
CombatConstants.MAX_STAMINA = 100
CombatConstants.STAMINA_REGEN_PER_SECOND = 20
CombatConstants.PARRY_STAMINA_COST = 15

-- Lockout applied after a failed parry, so a whiff has a real cost.
CombatConstants.WHIFF_LOCKOUT = 0.5

-- How long an enemy is stunned after a successful parry.
CombatConstants.STAGGER_DURATION = 1.5

-- Enemy recovery after a strike resolves, before it can wind up again.
CombatConstants.RECOVER_DURATION = 0.8

-- How long the server holds a strike open past impact before resolving damage,
-- so a parry pressed inside the late half of the window still has time to
-- arrive over the network.
--
-- This is a real tradeoff and one the slice exists to measure: damage feedback
-- lands this many seconds after the visual impact, and a player whose round
-- trip exceeds it loses late-half parries they legitimately earned. Raising it
-- buys fairness for high-ping players at the cost of mushier feedback. The
-- debug HUD reports ping next to the parry delta so the two can be correlated
-- before this number is settled.
CombatConstants.STRIKE_RESOLUTION_GRACE = 0.15

return CombatConstants
