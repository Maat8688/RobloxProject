-- Owns combat authority: rate-limits basic attacks per player, wires the
-- AttackAttempt/ParryAttempt remotes to whichever enemy is the right target.
-- Reads the player's equipped weapon from EquipService — an unequipped
-- player's attacks/parries are ignored. Takes its enemy list from whoever
-- populated the dungeon (DungeonGenerator) rather than spawning its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConstants = require(Shared:WaitForChild("CombatConstants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local EquipService = require(script.Parent.Parent.EquipService)

local attackAttemptRemote = Remotes.Get(Remotes.Names.AttackAttempt)
local parryAttemptRemote = Remotes.Get(Remotes.Names.ParryAttempt)
local healBurstRemote = Remotes.Get(Remotes.Names.HealBurst)

local CombatServer = {}

local lastSwingAt = {}

-- Heals `healer` plus every other player within HEALER_PARRY_HEAL_RADIUS of
-- them, up to their Humanoid's MaxHealth. Fired only after a Healer's parry
-- actually lands (see the ParryAttempt handler below) — this is the "parry
-- near allies triggers burst heal" mechanic from DESIGN.md's healer pillar,
-- deliberately not a passive HoT.
local function healNearbyAllies(healer, healerPosition)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid == nil or rootPart == nil then
			continue
		end

		if player ~= healer then
			local distance = (rootPart.Position - healerPosition).Magnitude
			if distance > CombatConstants.HEALER_PARRY_HEAL_RADIUS then
				continue
			end
		end

		local healed = math.min(CombatConstants.HEALER_PARRY_BURST_HEAL, humanoid.MaxHealth - humanoid.Health)
		if healed <= 0 then
			continue
		end

		humanoid.Health += healed
		healBurstRemote:FireClient(player, healed)
	end
end

-- Nearest non-Dead enemy whose PrimaryPart is within `range` of `position`,
-- optionally filtered further by `predicate(enemy)`. No aggro/threat system —
-- just "what's actually close enough" for a first pass.
local function findNearestEnemy(enemies, position, range, predicate)
	local nearest, nearestDistance = nil, nil

	for _, enemy in enemies do
		if enemy.state == "Dead" then
			continue
		end
		if predicate ~= nil and not predicate(enemy) then
			continue
		end

		local primaryPart = enemy.model.PrimaryPart
		if primaryPart == nil then
			continue
		end

		local distance = (primaryPart.Position - position).Magnitude
		if distance <= range and (nearestDistance == nil or distance < nearestDistance) then
			nearest, nearestDistance = enemy, distance
		end
	end

	return nearest
end

function CombatServer.Start(enemies)
	attackAttemptRemote.OnServerEvent:Connect(function(player)
		local weaponDef = EquipService.GetWeapon(player)
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if weaponDef == nil or rootPart == nil then
			return
		end

		local now = os.clock()
		local last = lastSwingAt[player]

		if last ~= nil and (now - last) < weaponDef.swingCooldown then
			return
		end

		local target = findNearestEnemy(enemies, rootPart.Position, weaponDef.swingRange)
		if target == nil then
			return
		end

		lastSwingAt[player] = now
		target:TryAttack(player, weaponDef)
	end)

	parryAttemptRemote.OnServerEvent:Connect(function(player)
		local weaponDef = EquipService.GetWeapon(player)
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if weaponDef == nil or rootPart == nil then
			return
		end

		local target = findNearestEnemy(enemies, rootPart.Position, CombatConstants.PARRY_DETECTION_RANGE, function(enemy)
			return enemy.state == "Telegraph"
		end)
		if target == nil then
			return
		end

		local parried = target:TryParry(player, weaponDef.parryWindow)
		if parried and weaponDef.class == "Healer" then
			healNearbyAllies(player, rootPart.Position)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSwingAt[player] = nil
	end)
end

return CombatServer
