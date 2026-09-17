--!strict
-- The blacksmith: a physical anvil in the start room that upgrades whichever
-- weapon the player has equipped, for coins plus class crystals at the higher
-- tiers.
--
-- Diegetic rather than a shop menu, matching the weapon stands:
-- ProximityPrompt.Triggered already fires server-side with the player, so the
-- interaction needs no client-callable remote into spending currency. Only the
-- outcome goes back to the client.
--
-- Owns the economy half of upgrading: it decides the price and takes payment,
-- then hands off to EquipService, which owns weapon state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EconomyDefs = require(Shared.EconomyDefs)
local Loadout = require(Shared.Loadout)
local Remotes = require(Shared.Remotes)

local EquipService = require(script.Parent.Parent.EquipService)
local CurrencyService = require(script.Parent.CurrencyService)

local ANVIL_OFFSET = Vector3.new(0, 1.5, -8)

local BlacksmithService = {}

export type UpgradeOutcome = {
	success: boolean,
	-- Player-facing reason on failure. The client renders it; it never
	-- computes the price itself.
	reason: string?,
	newLevel: number?,
}

function BlacksmithService.tryUpgrade(player: Player): UpgradeOutcome
	local weaponId = EquipService.getWeaponId(player)
	if not weaponId then
		return { success = false, reason = "Equip a weapon first" }
	end

	local level = EquipService.getUpgradeLevel(player, weaponId)
	if level >= EconomyDefs.MAX_UPGRADE_LEVEL then
		return { success = false, reason = "Already at max upgrade level" }
	end

	local cost = EconomyDefs.getUpgradeCost(level)
	local class = Loadout.classOf(weaponId)

	if not CurrencyService.trySpend(player, cost.coins, class, cost.crystals) then
		local reason = if cost.crystals > 0
			then string.format("Need %d coins and %d %s crystals", cost.coins, cost.crystals, class)
			else string.format("Need %d coins", cost.coins)
		return { success = false, reason = reason }
	end

	return { success = true, newLevel = EquipService.applyUpgrade(player, weaponId) }
end

function BlacksmithService.start(originCFrame: CFrame)
	local anvil = Instance.new("Part")
	anvil.Name = "Blacksmith"
	anvil.Anchored = true
	anvil.CanCollide = true
	anvil.Size = Vector3.new(4, 3, 3)
	anvil.Color = Color3.fromRGB(105, 64, 40)
	anvil.CFrame = originCFrame * CFrame.new(ANVIL_OFFSET)
	anvil.Parent = Workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Blacksmith"
	prompt.ActionText = "Upgrade Weapon"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.Parent = anvil

	prompt.Triggered:Connect(function(player)
		local outcome = BlacksmithService.tryUpgrade(player)
		Remotes.get("UpgradeResult"):FireClient(player, outcome)
	end)
end

return BlacksmithService
