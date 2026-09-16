-- Tunable combat numbers, shared by server (authority) and client (feedback timing).
-- Change balance here, not inline in CombatServer/CombatClient/Enemy.

local CombatConstants = {}

-- Basic attack
-- (parryWindow and swingRange moved onto WeaponDefs per-weapon — see there)
CombatConstants.STAGGER_DAMAGE_MULTIPLIER = 2 -- punish window bonus while an enemy is Staggered

-- Parry
CombatConstants.TELEGRAPH_POLL_INTERVAL = 0.05 -- how finely the enemy loop checks for an early parry
CombatConstants.PARRY_DETECTION_RANGE = 15 -- how far away a telegraphing enemy can still be parried from

-- Enemy state durations
-- (per-hit engage range moved onto each attack in EnemyDefs — see there)
CombatConstants.IDLE_DURATION = 1.0
CombatConstants.STAGGER_DURATION = 1.2
CombatConstants.RECOVER_DURATION = 0.8
CombatConstants.ENEMY_RESPAWN_DELAY = 3

return CombatConstants
