-- The blacksmith: a physical anvil in the start room that upgrades whatever
-- weapon the player currently has equipped, for coins (+ class crystals at the
-- higher tiers). Diegetic rather than a shop menu, matching WeaponPickups —
-- the ProximityPrompt's Triggered already fires server-side with the player,
-- so the interaction itself needs no RemoteEvent (see DESIGN.md).
--
-- Owns the economy half of upgrading only: it decides the price and takes
-- payment, then hands off to EquipService, which owns the weapon state.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyDefs = require(Shared:WaitForChild("EconomyDefs"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CurrencyService = require(script.Parent.CurrencyService)
local EquipService = require(script.Parent.Parent.EquipService)

local upgradeResultRemote = Remotes.Get(Remotes.Names.UpgradeResult)

local ANVIL_OFFSET = Vector3.new(0, 1.5, -8)

local BlacksmithService = {}

-- Returns success plus either the new level or a player-facing reason. The
-- client renders the message; it never computes the price it gets charged.
function BlacksmithService.TryUpgrade(player)
	local weaponId = EquipService.GetEquippedWeaponId(player)
	if weaponId == nil then
		return false, "Equip a weapon first"
	end

	local level = EquipService.GetUpgradeLevel(player, weaponId)
	if level >= EconomyDefs.MAX_UPGRADE_LEVEL then
		return false, "Already at max upgrade level"
	end

	local cost = EconomyDefs.GetUpgradeCost(level)
	local crystalType = EquipService.GetWeapon(player).class

	if not CurrencyService.TrySpend(player, cost.coins, crystalType, cost.crystals) then
		if cost.crystals > 0 then
			return false, string.format("Need %d coins and %d %s crystals", cost.coins, cost.crystals, crystalType)
		end
		return false, string.format("Need %d coins", cost.coins)
	end

	return true, nil, EquipService.ApplyUpgrade(player, weaponId)
end

function BlacksmithService.Start(originCFrame)
	local anvil = Instance.new("Part")
	anvil.Name = "Blacksmith"
	anvil.Anchored = true
	anvil.CanCollide = true
	anvil.Size = Vector3.new(4, 3, 3)
	anvil.BrickColor = BrickColor.new("Reddish brown")
	anvil.CFrame = originCFrame * CFrame.new(ANVIL_OFFSET)
	anvil.Parent = Workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Blacksmith"
	prompt.ActionText = "Upgrade Weapon"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.Parent = anvil

	prompt.Triggered:Connect(function(player)
		local success, reason, newLevel = BlacksmithService.TryUpgrade(player)
		upgradeResultRemote:FireClient(player, success, reason, newLevel)
	end)

	return anvil
end

return BlacksmithService
