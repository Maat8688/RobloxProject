-- Every RemoteEvent/RemoteFunction is created and looked up through here so
-- nothing gets created ad hoc elsewhere. RemoteEvents are runtime Instances
-- (not source files), so this module creates them under ReplicatedStorage.Remotes
-- on the server the first time each is requested, and waits for them on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.Names = {
	AttackAttempt = "AttackAttempt",
	ParryAttempt = "ParryAttempt",
	EnemyTelegraphStart = "EnemyTelegraphStart",
	EnemyStateChanged = "EnemyStateChanged",
	PlayerHit = "PlayerHit",
	WeaponEquipped = "WeaponEquipped",
	ChestOpened = "ChestOpened",
	InventoryUpdated = "InventoryUpdated",
	CurrencyUpdated = "CurrencyUpdated",
	UpgradeResult = "UpgradeResult",
	HealBurst = "HealBurst",
	PvPStatusChanged = "PvPStatusChanged",
	PvPTelegraphStart = "PvPTelegraphStart",
	PvPParryResult = "PvPParryResult",
	PvPHealthChanged = "PvPHealthChanged",
}

local FOLDER_NAME = "Remotes"

local function getFolder()
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing
		end

		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end

	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.Get(name)
	local folder = getFolder()

	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end

		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	return folder:WaitForChild(name)
end

return Remotes
