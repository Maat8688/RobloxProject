--!strict
-- Enemy rig construction and attack selection.
--
-- Selection is a fixed rotation for the vertical slice, so tuning sessions are
-- reproducible — you always know whether the next attack is the parryable
-- Overhead or the unparryable GroundSlam. Real behaviour trees arrive at
-- build-order step 3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EnemyDefs = require(ReplicatedStorage.Shared.EnemyDefs)

local EnemyAI = {}

export type Enemy = {
	id: string,
	defId: string,
	def: EnemyDefs.EnemyDef,
	model: Model,
	root: BasePart,
	attackIndex: number,
}

function EnemyAI.spawn(defId: string, position: Vector3, facePosition: Vector3): Enemy
	local def = EnemyDefs[defId]
	assert(def, `Unknown enemy def "{defId}"`)

	local model = Instance.new("Model")
	model.Name = defId

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(4, 6, 4)
	root.Anchored = true
	root.Color = Color3.fromRGB(150, 60, 60)
	root.Material = Enum.Material.Metal
	-- Face the player spawn, flattened so the rig never tips.
	root.CFrame = CFrame.lookAt(position, Vector3.new(facePosition.X, position.Y, facePosition.Z))
	root.Parent = model

	model.PrimaryPart = root

	-- Read by the client for telegraph VFX, so the client never needs its own
	-- registry of which model is which enemy.
	local enemyId = `{defId}_1`
	model:SetAttribute("EnemyId", enemyId)

	model.Parent = Workspace

	return {
		id = enemyId,
		defId = defId,
		def = def,
		model = model,
		root = root,
		attackIndex = 0,
	}
end

function EnemyAI.nextAttack(enemy: Enemy): (string, EnemyDefs.AttackDef)
	local order = enemy.def.attackOrder
	enemy.attackIndex = enemy.attackIndex % #order + 1

	local attackId = order[enemy.attackIndex]
	return attackId, enemy.def.attacks[attackId]
end

return EnemyAI
