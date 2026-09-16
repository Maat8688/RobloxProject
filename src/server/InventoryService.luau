-- The only place inventory state lives, mirroring EquipService's shape.
-- In-memory only — resets on rejoin until DataStore persistence lands in
-- build order step 10. Items here are collectible/visible only for now;
-- turning them into spendable upgrade materials is step 7's job.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local inventoryUpdatedRemote = Remotes.Get(Remotes.Names.InventoryUpdated)

local InventoryService = {}

local inventories = {}

function InventoryService.AddItem(player, itemInstance)
	local inventory = inventories[player]
	if inventory == nil then
		inventory = {}
		inventories[player] = inventory
	end

	table.insert(inventory, itemInstance)
	inventoryUpdatedRemote:FireClient(player, inventory)
end

-- Returns the player's current item list (empty table if they have none).
function InventoryService.GetInventory(player)
	return inventories[player] or {}
end

Players.PlayerRemoving:Connect(function(player)
	inventories[player] = nil
end)

return InventoryService
