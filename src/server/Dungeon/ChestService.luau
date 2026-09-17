-- One chest per combat room, barrier-locked to that room's single enemy
-- (its guard). Unlocks permanently the first time the guard dies, even
-- though the guard itself keeps respawning for repeat practice — the
-- unlock is a one-time latch, not tied to the guard's current state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LootTables = require(Shared:WaitForChild("LootTables"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local InventoryService = require(script.Parent.Parent.InventoryService)

local chestOpenedRemote = Remotes.Get(Remotes.Names.ChestOpened)

local LOCKED_COLOR = BrickColor.new("Dark stone grey")
local UNLOCKED_COLOR = BrickColor.new("New Yeller")

local ChestService = {}

function ChestService.CreateChest(cframe, guardEnemy, enemyType, parent)
	local chestId = guardEnemy.id .. "_Chest"

	local chest = Instance.new("Part")
	chest.Name = chestId
	chest.Anchored = true
	chest.CanCollide = true
	chest.Size = Vector3.new(3, 3, 3)
	chest.CFrame = cframe
	chest.BrickColor = LOCKED_COLOR
	chest.Parent = parent

	local barrier = Instance.new("Part")
	barrier.Name = "Barrier"
	barrier.Anchored = true
	barrier.CanCollide = false
	barrier.CanTouch = false
	barrier.Size = Vector3.new(4, 4, 4)
	barrier.CFrame = cframe
	barrier.BrickColor = BrickColor.new("Really red")
	barrier.Material = Enum.Material.ForceField
	barrier.Transparency = 0.5
	barrier.Parent = chest

	local opened = false

	guardEnemy:OnDeath(function()
		if barrier.Parent == nil then
			return
		end

		barrier:Destroy()
		chest.BrickColor = UNLOCKED_COLOR

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

			local loot = LootTables[enemyType]
			chestOpenedRemote:FireClient(player, chestId, { loot })

			InventoryService.AddItem(player, {
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
