--!strict
-- The only place inventory state lives, mirroring EquipService's shape.
-- In-memory only — resets on rejoin until DataStore persistence lands in
-- build-order step 10.
--
-- A plain list rather than a map keyed by itemId: a map can't hold two copies
-- of the same item, and each copy can carry its own upgradeLevel. Items are
-- collectible only for now — they aren't consumed by the blacksmith.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local InventoryService = {}

-- Matches ARCHITECTURE.md's ItemInstance schema.
export type ItemInstance = {
	itemId: string,
	rarity: string,
	upgradeLevel: number,
	-- nil for class-neutral materials; set only for real class gear.
	classTag: string?,
}

local inventories: { [Player]: { ItemInstance } } = {}

function InventoryService.addItem(player: Player, item: ItemInstance)
	local inventory = inventories[player]
	if not inventory then
		inventory = {}
		inventories[player] = inventory
	end

	table.insert(inventory, item)
	Remotes.get("InventoryUpdated"):FireClient(player, { items = inventory })
end

-- The player's current item list (empty if they have none).
function InventoryService.getInventory(player: Player): { ItemInstance }
	return inventories[player] or {}
end

Players.PlayerRemoving:Connect(function(player)
	inventories[player] = nil
end)

return InventoryService
