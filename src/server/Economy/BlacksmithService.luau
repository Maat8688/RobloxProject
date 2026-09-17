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

-- The centre of the anvil's stone block, which sits on the floor.
local ANVIL_OFFSET = Vector3.new(0, 0.7, -8)

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

local IRON = Color3.fromRGB(58, 56, 62)
local STONE = Color3.fromRGB(70, 64, 62)

local function piece(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

-- Dressing around the anvil: its iron body, a hammer resting on it, and a
-- burning forge to one side that lights the corner.
local function dressAnvil(anvil: Part)
	local base = anvil.CFrame * CFrame.new(0, -anvil.Size.Y / 2, 0)
	piece(anvil, "Waist", Vector3.new(1.4, 0.8, 1.0), base * CFrame.new(0, 1.8, 0), IRON, Enum.Material.Metal)
	piece(anvil, "Face", Vector3.new(3.4, 0.6, 1.4), base * CFrame.new(0, 2.5, 0), IRON, Enum.Material.Metal)
	piece(anvil, "Horn", Vector3.new(1.0, 0.4, 0.8), base * CFrame.new(2.1, 2.55, 0), IRON, Enum.Material.Metal)

	local hammerAt = base * CFrame.new(-0.6, 2.95, 0) * CFrame.Angles(0, math.rad(25), 0)
	piece(anvil, "HammerHandle", Vector3.new(0.2, 0.2, 1.8), hammerAt, Color3.fromRGB(100, 70, 45), Enum.Material.Wood)
	piece(anvil, "HammerHead", Vector3.new(0.5, 0.5, 0.9), hammerAt * CFrame.new(0, 0.05, -0.9) * CFrame.Angles(0, math.rad(90), 0), IRON, Enum.Material.Metal)

	local forge = piece(anvil, "Forge", Vector3.new(3, 2.4, 3), base * CFrame.new(-5, 1.2, -0.5), STONE, Enum.Material.Brick)
	forge.CanCollide = true
	forge.CanQuery = true
	local coals = piece(forge, "Coals", Vector3.new(2.4, 0.2, 2.4), forge.CFrame * CFrame.new(0, 1.25, 0), Color3.fromRGB(255, 110, 30), Enum.Material.Neon)

	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 9
	fire.Color = Color3.fromRGB(255, 130, 40)
	fire.SecondaryColor = Color3.fromRGB(190, 40, 10)
	fire.Parent = coals

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Brightness = 3
	light.Range = 22
	light.Shadows = true
	light.Parent = coals
end

function BlacksmithService.start(originCFrame: CFrame)
	-- The anvil's stone block is the station itself: it collides and carries
	-- the prompt. The rest is dressing.
	local anvil = Instance.new("Part")
	anvil.Name = "Blacksmith"
	anvil.Anchored = true
	anvil.CanCollide = true
	anvil.Size = Vector3.new(2.4, 1.4, 1.8)
	anvil.Color = STONE
	anvil.Material = Enum.Material.Slate
	anvil.CFrame = originCFrame * CFrame.new(ANVIL_OFFSET)
	anvil.Parent = Workspace
	dressAnvil(anvil)

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
