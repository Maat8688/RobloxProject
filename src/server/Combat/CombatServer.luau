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

local CombatServer = {}

local lastSwingAt = {}

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

		target:TryParry(player, weaponDef.parryWindow)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSwingAt[player] = nil
	end)
end

return CombatServer
