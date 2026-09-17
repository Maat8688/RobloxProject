--!strict
-- One chest per combat room, barrier-locked to that room's enemy (its guard).
--
-- Unlocks permanently the first time the guard dies, even though the guard
-- keeps respawning for repeat practice — the unlock is a one-time latch, not
-- tied to the guard's current state. The first player to open it takes the
-- loot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local LootTables = require(Shared.LootTables)
local Remotes = require(Shared.Remotes)

local EnemyAI = require(script.Parent.Parent.Combat.EnemyAI)
local InventoryService = require(script.Parent.Parent.InventoryService)

local LOCKED_COLOR = Color3.fromRGB(99, 95, 98)
local UNLOCKED_COLOR = Color3.fromRGB(255, 255, 0)

local ChestService = {}

function ChestService.createChest(cframe: CFrame, guard: EnemyAI.Enemy, parent: Instance): Part
	local chestId = `{guard.id}_Chest`

	-- Resolved now rather than when the chest opens, so a guard with no loot
	-- row fails at dungeon generation instead of in a player's hands.
	local loot = LootTables[guard.defId]
	assert(loot, `No LootTables entry for "{guard.defId}"`)

	local chest = Instance.new("Part")
	chest.Name = chestId
	chest.Anchored = true
	chest.CanCollide = true
	chest.Size = Vector3.new(3, 3, 3)
	chest.CFrame = cframe
	chest.Color = LOCKED_COLOR
	chest.Parent = parent

	local barrier = Instance.new("Part")
	barrier.Name = "Barrier"
	barrier.Anchored = true
	barrier.CanCollide = false
	barrier.CanTouch = false
	barrier.Size = Vector3.new(4, 4, 4)
	barrier.CFrame = cframe
	barrier.Color = Color3.fromRGB(255, 0, 0)
	barrier.Material = Enum.Material.ForceField
	barrier.Transparency = 0.5
	barrier.Parent = chest

	local opened = false

	EnemyAI.onDeath(guard, function()
		-- Already unlocked by an earlier kill.
		if barrier.Parent == nil then
			return
		end

		barrier:Destroy()
		chest.Color = UNLOCKED_COLOR

		-- No prompt exists until the guard falls, so a locked chest simply
		-- cannot be interacted with.
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "Chest"
		prompt.ActionText = "Open"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.Parent = chest

		prompt.Triggered:Connect(function(player)
			if opened then
				return
			end
			opened = true
			prompt.Enabled = false

			Remotes.get("ChestOpened"):FireClient(player, {
				chestId = chestId,
				loot = { loot },
			})

			InventoryService.addItem(player, {
				itemId = loot.itemId,
				rarity = loot.rarity,
				upgradeLevel = 0,
				classTag = loot.classTag,
			})
		end)
	end)

	return chest
end

return ChestService
