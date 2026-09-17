-- Per-player combat state for one side of a duel: mirrors Combat/Enemy.luau's
-- own Idle -> Telegraph -> (Staggered | Recover) state machine, but the
-- telegraph is started by that player's own AttackAttempt (via
-- PvPCombatServer) instead of an autonomous loop, and the opposing player is
-- the one who tries to parry it — exactly the same attacker/defender split
-- Enemy.luau already has with a real player, just with a Duelist standing in
-- for "the enemy" on both sides at once (build order step 9).
--
-- Health is a virtual pool, not the character's real Humanoid: a duel never
-- actually damages or kills the player, so there's no respawn/ragdoll flow
-- to fight — see DESIGN.md's decision log for why this was chosen over
-- letting real Humanoid damage apply.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConstants = require(Shared:WaitForChild("CombatConstants"))

local Duelist = {}
Duelist.__index = Duelist

function Duelist.new(player)
	return setmetatable({
		player = player,
		state = "Idle",
		health = CombatConstants.PVP_STARTING_HEALTH,
		pendingWeaponDef = nil,
		telegraphResolveTime = nil,
		parriedThisAttack = false,
	}, Duelist)
end

-- Called when this duelist swings — `weaponDef` is the attacker's own
-- equipped weapon, read at swing time (mirrors Enemy:_beginTelegraph).
function Duelist:BeginTelegraph(weaponDef)
	self.state = "Telegraph"
	self.pendingWeaponDef = weaponDef
	self.parriedThisAttack = false
	self.telegraphResolveTime = os.clock() + weaponDef.pvpTelegraphDuration
end

-- Called by the opposing player's ParryAttempt. `defenderPlayer` supplies the
-- ping used to compensate the timing check, exactly like Enemy:TryParry —
-- the defender's clock, not the attacker's, is what's out of sync with the
-- server here.
function Duelist:TryParry(defenderPlayer, parryWindow)
	if self.state ~= "Telegraph" or self.telegraphResolveTime == nil then
		return false
	end

	local halfPing = defenderPlayer:GetNetworkPing() / 2
	local perceivedTime = os.clock() - halfPing
	local delta = math.abs(perceivedTime - self.telegraphResolveTime)

	if delta <= parryWindow then
		self.parriedThisAttack = true
		return true
	end

	return false
end

-- Returns true if this damage brought the duelist to 0 (duel over).
function Duelist:ApplyDamage(amount)
	self.health = math.max(0, self.health - amount)
	return self.health <= 0
end

return Duelist
