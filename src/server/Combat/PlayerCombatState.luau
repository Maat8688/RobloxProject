--!strict
-- Per-player combat resources: stamina, the whiff lockout, the riposte window,
-- and swing timing.
--
-- One record per player, shared by PvE (CombatServer) and PvP
-- (PvPCombatServer). PvP reusing the same combat system (DESIGN.md) has to
-- include reusing its costs — a separate duel-only pool would let a player
-- walk into the arena with parry spam back on the table.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConstants = require(Shared.CombatConstants)
local ParryMath = require(Shared.ParryMath)

local PlayerCombatState = {}

export type State = {
	stamina: number,
	lockoutUntil: number,
	staminaUpdatedAt: number,
	-- Set by a successful parry; the Assassin's payoff window.
	riposteUntil: number,
	attackReadyAt: number,
	swinging: boolean,
}

local states: { [Player]: State } = {}

local function getOrCreate(player: Player): State
	local state = states[player]
	if state then
		return state
	end

	local created: State = {
		stamina = CombatConstants.MAX_STAMINA,
		lockoutUntil = 0,
		staminaUpdatedAt = Workspace:GetServerTimeNow(),
		riposteUntil = 0,
		attackReadyAt = 0,
		swinging = false,
	}
	states[player] = created
	return created
end

-- Returns the player's state with stamina regenerated up to `now`.
--
-- Regen is applied lazily on read rather than on a tick, so it stays exact
-- regardless of server framerate and costs nothing while nobody is acting.
function PlayerCombatState.sync(player: Player, now: number): State
	local state = getOrCreate(player)
	local elapsed = math.max(now - state.staminaUpdatedAt, 0)
	state.stamina = ParryMath.regenerateStamina(state.stamina, elapsed)
	state.staminaUpdatedAt = now
	return state
end

-- Read without regenerating, for callers that only need a flag.
function PlayerCombatState.peek(player: Player): State
	return getOrCreate(player)
end

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

return PlayerCombatState
