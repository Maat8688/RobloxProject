--!strict
-- Enemy instances: rig construction, movement, death hooks, and per-enemy
-- state.
--
-- Decision-making lives in the pure AttackSelector; this module is the Roblox
-- half — spawning parts, moving them, and holding the mutable state the
-- selector is fed. Keeping the split means enemy behaviour stays testable
-- without a running game.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AttackSelector = require(Shared.AttackSelector)
local EnemyDefs = require(Shared.EnemyDefs)

local EnemyAI = {}

-- CollectionService tag on every enemy model. Clients look enemies up by it.
EnemyAI.TAG = "Enemy"

-- Per-type colours so enemies are tellable apart at a glance while there are
-- no real models. TelegraphVFX mirrors this table.
local TYPE_COLORS: { [string]: Color3 } = {
	TrainingDummy = Color3.fromRGB(150, 60, 60),
	SkeletonWarrior = Color3.fromRGB(200, 195, 170),
	Shambler = Color3.fromRGB(120, 90, 50),
	Spitter = Color3.fromRGB(80, 130, 70),
}

local DEFAULT_COLOR = Color3.fromRGB(150, 60, 60)

export type EnemyState = "idle" | "telegraph" | "staggered" | "dead"

-- Receives the player who landed the killing blow, or nil.
export type DeathCallback = (killer: Player?) -> ()

export type Enemy = {
	id: string,
	defId: string,
	def: EnemyDefs.EnemyDef,
	model: Model,
	root: BasePart,
	health: number,
	alive: boolean,
	state: EnemyState,
	-- attackId -> server time the attack becomes usable again.
	cooldowns: AttackSelector.CooldownMap,
	homeCFrame: CFrame,
	-- The room this enemy belongs to. nil means unleashed.
	bounds: AttackSelector.Bounds?,
	deathCallbacks: { DeathCallback },
}

local nextInstanceId = 0

function EnemyAI.spawn(
	defId: string,
	position: Vector3,
	facePosition: Vector3,
	bounds: AttackSelector.Bounds?,
	parent: Instance?
): Enemy
	local def = EnemyDefs[defId]
	assert(def, `Unknown enemy def "{defId}"`)

	nextInstanceId += 1
	local enemyId = `{defId}_{nextInstanceId}`

	local model = Instance.new("Model")
	model.Name = enemyId

	-- Flattened so the rig never tips.
	local homeCFrame = CFrame.lookAt(position, Vector3.new(facePosition.X, position.Y, facePosition.Z))

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(4, 6, 4)
	root.Anchored = true
	root.Color = TYPE_COLORS[defId] or DEFAULT_COLOR
	root.Material = Enum.Material.Metal
	root.CFrame = homeCFrame
	root.Parent = model

	model.PrimaryPart = root

	-- Read by the client for telegraph VFX, so the client never needs its own
	-- registry of which model is which enemy. The tag lets clients find enemies
	-- wherever they're parented — the dungeon nests them inside a folder.
	model:SetAttribute("EnemyId", enemyId)
	model:SetAttribute("EnemyDefId", defId)
	CollectionService:AddTag(model, EnemyAI.TAG)

	model.Parent = parent or Workspace

	return {
		id = enemyId,
		defId = defId,
		def = def,
		model = model,
		root = root,
		health = def.maxHealth,
		alive = true,
		state = "idle",
		cooldowns = {},
		homeCFrame = homeCFrame,
		bounds = bounds,
		deathCallbacks = {},
	}
end

--[[ Death hooks ]]

-- Runs on every death, in registration order. A list rather than a single
-- slot because the listeners are genuinely independent: a guarded chest
-- unlocking and a kill payout both care about the same death.
function EnemyAI.onDeath(enemy: Enemy, callback: DeathCallback)
	table.insert(enemy.deathCallbacks, callback)
end

function EnemyAI.fireDeath(enemy: Enemy, killer: Player?)
	for _, callback in enemy.deathCallbacks do
		-- One misbehaving listener must not stop the others (a chest failing to
		-- unlock shouldn't also cost the killer their coins).
		local ok, err = pcall(callback, killer)
		if not ok then
			warn(`Death callback for {enemy.id} failed: {err}`)
		end
	end
end

--[[ Targeting ]]

-- Whether this enemy may act on something standing at `position`. A leashed
-- enemy only ever considers its own room.
function EnemyAI.canReach(enemy: Enemy, position: Vector3): boolean
	local bounds = enemy.bounds
	if not bounds then
		return true
	end

	return AttackSelector.isWithinBounds(bounds, position.X, position.Z)
end

--[[ Movement ]]

-- Anchored parts moved by CFrame rather than a Humanoid: the rigs are single
-- parts, and stepping them directly keeps server-side hit-reg reading the same
-- positions the AI reasoned about. Because that ignores walls, movement is
-- clamped to the enemy's room.
function EnemyAI.step(enemy: Enemy, targetPosition: Vector3, deltaTime: number)
	if not enemy.alive then
		return
	end

	local currentPosition = enemy.root.Position
	local toTarget = Vector3.new(
		targetPosition.X - currentPosition.X,
		0,
		targetPosition.Z - currentPosition.Z
	)

	local distance = toTarget.Magnitude
	-- Always face the player, even while stationary or staggered, so the
	-- telegraph is readable and hit-reg arcs mean what they look like.
	if distance > 1e-3 then
		enemy.root.CFrame = CFrame.lookAt(currentPosition, currentPosition + toTarget.Unit)
	end

	-- An enemy mid-windup is committed: letting it reposition during the
	-- telegraph would make the parry beat unreadable.
	if enemy.state ~= "idle" then
		return
	end

	local intent = AttackSelector.movementIntent(enemy.def, distance)
	if intent == "hold" or intent == "idle" then
		return
	end

	local direction = if intent == "approach" then toTarget.Unit else -toTarget.Unit
	local travel = enemy.def.moveSpeed * deltaTime
	-- Never overshoot past the player on a long frame.
	travel = math.min(travel, math.max(distance - 1, 0))
	if travel <= 0 then
		return
	end

	local moved = currentPosition + direction * travel

	local bounds = enemy.bounds
	if bounds then
		local x, z = AttackSelector.clampToBounds(bounds, moved.X, moved.Z)
		moved = Vector3.new(x, moved.Y, z)
	end

	enemy.root.CFrame = CFrame.lookAt(moved, moved + toTarget.Unit)
end

--[[ Combat state ]]

function EnemyAI.chooseAttack(enemy: Enemy, distance: number, now: number): string?
	return AttackSelector.chooseAttack(enemy.def, distance, enemy.cooldowns, now)
end

function EnemyAI.markAttackUsed(enemy: Enemy, attackId: string, now: number)
	local attack = enemy.def.attacks[attackId]
	enemy.cooldowns[attackId] = now + attack.cooldown
end

-- Returns true if this damage killed the enemy. Death hooks are fired by the
-- caller, which knows who landed the blow.
function EnemyAI.applyDamage(enemy: Enemy, amount: number): boolean
	if not enemy.alive then
		return false
	end

	enemy.health = math.max(enemy.health - amount, 0)
	if enemy.health > 0 then
		return false
	end

	enemy.alive = false
	enemy.state = "dead"
	return true
end

-- Respawning in place keeps the dungeon practicable: a guard comes back for
-- another go, though its chest stays unlocked.
function EnemyAI.revive(enemy: Enemy)
	enemy.health = enemy.def.maxHealth
	enemy.alive = true
	enemy.state = "idle"
	enemy.cooldowns = {}
	enemy.root.Transparency = 0
	enemy.root.Color = TYPE_COLORS[enemy.defId] or DEFAULT_COLOR
	enemy.root.CFrame = enemy.homeCFrame
end

function EnemyAI.markDead(enemy: Enemy)
	enemy.root.Transparency = 0.7
	enemy.root.Color = Color3.fromRGB(60, 60, 60)
end

return EnemyAI
