--!strict
-- Enemy instances: rig construction, movement, and per-enemy state.
--
-- Decision-making lives in the pure AttackSelector; this module is the Roblox
-- half — spawning parts, moving them, and holding the mutable state the
-- selector is fed. Keeping the split means enemy behaviour stays testable
-- without a running game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AttackSelector = require(Shared.AttackSelector)
local EnemyDefs = require(Shared.EnemyDefs)

local EnemyAI = {}

-- Per-type colours so three enemies in a room are tellable apart at a glance
-- while there are no real models.
local TYPE_COLORS: { [string]: Color3 } = {
	TrainingDummy = Color3.fromRGB(150, 60, 60),
	Shambler = Color3.fromRGB(120, 90, 50),
	Spitter = Color3.fromRGB(80, 130, 70),
}

local DEFAULT_COLOR = Color3.fromRGB(150, 60, 60)

export type EnemyState = "idle" | "telegraph" | "staggered" | "dead"

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
	homePosition: Vector3,
}

local nextInstanceId = 0

function EnemyAI.spawn(defId: string, position: Vector3, facePosition: Vector3): Enemy
	local def = EnemyDefs[defId]
	assert(def, `Unknown enemy def "{defId}"`)

	nextInstanceId += 1
	local enemyId = `{defId}_{nextInstanceId}`

	local model = Instance.new("Model")
	model.Name = enemyId

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(4, 6, 4)
	root.Anchored = true
	root.Color = TYPE_COLORS[defId] or DEFAULT_COLOR
	root.Material = Enum.Material.Metal
	-- Flattened so the rig never tips.
	root.CFrame = CFrame.lookAt(position, Vector3.new(facePosition.X, position.Y, facePosition.Z))
	root.Parent = model

	model.PrimaryPart = root

	-- Read by the client for telegraph VFX, so the client never needs its own
	-- registry of which model is which enemy.
	model:SetAttribute("EnemyId", enemyId)
	model:SetAttribute("EnemyDefId", defId)

	model.Parent = Workspace

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
		homePosition = position,
	}
end

--[[ Movement ]]

-- Anchored parts moved by CFrame rather than a Humanoid: the enemy rigs are
-- single parts, and stepping them directly keeps server-side hit-reg reading
-- the same positions the AI reasoned about. Real pathfinding arrives with the
-- dungeon generator at build-order step 4, when there are walls worth avoiding.
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

-- Returns true if this damage killed the enemy.
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

-- Respawning in place keeps tuning iterative: clear the room, get it back
-- immediately, without restarting the session. Real encounter/spawn rules
-- arrive with the dungeon generator at build-order step 4.
function EnemyAI.revive(enemy: Enemy)
	enemy.health = enemy.def.maxHealth
	enemy.alive = true
	enemy.state = "idle"
	enemy.cooldowns = {}
	enemy.root.Transparency = 0
	enemy.root.Color = TYPE_COLORS[enemy.defId] or DEFAULT_COLOR
	enemy.root.CFrame = CFrame.new(enemy.homePosition)
end

function EnemyAI.markDead(enemy: Enemy)
	enemy.root.Transparency = 0.7
	enemy.root.Color = Color3.fromRGB(60, 60, 60)
end

return EnemyAI
