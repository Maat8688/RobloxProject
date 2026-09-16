-- Tunable combat numbers, shared by server (authority) and client (feedback timing).
-- Change balance here, not inline in CombatServer/CombatClient/Enemy.

local CombatConstants = {}

-- Basic attack
CombatConstants.SWING_RANGE = 8
CombatConstants.STAGGER_DAMAGE_MULTIPLIER = 2 -- punish window bonus while an enemy is Staggered

-- Parry
CombatConstants.PARRY_WINDOW = 0.15 -- seconds of tolerance around the attack's resolve time
CombatConstants.TELEGRAPH_POLL_INTERVAL = 0.05 -- how finely the enemy loop checks for an early parry

-- Enemy state durations
CombatConstants.IDLE_DURATION = 1.0
CombatConstants.STAGGER_DURATION = 1.2
CombatConstants.RECOVER_DURATION = 0.8
CombatConstants.ENEMY_ENGAGE_RANGE = 10 -- how close a player must be to take a resolved hit
CombatConstants.ENEMY_RESPAWN_DELAY = 3

return CombatConstants
