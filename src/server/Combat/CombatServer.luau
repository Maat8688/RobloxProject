-- Owns combat authority: rate-limits basic attacks per player, wires the
-- AttackAttempt/ParryAttempt remotes to the one enemy instance that exists
-- for the vertical slice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponDefs = require(Shared:WaitForChild("WeaponDefs"))
local EnemyDefs = require(Shared:WaitForChild("EnemyDefs"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Enemy = require(script.Parent.Enemy)

local attackAttemptRemote = Remotes.Get(Remotes.Names.AttackAttempt)
local parryAttemptRemote = Remotes.Get(Remotes.Names.ParryAttempt)

local CombatServer = {}

local lastSwingAt = {}

function CombatServer.Start()
	local dummy = Enemy.new("TrainingDummy", EnemyDefs.TrainingDummy, CFrame.new(0, 3, 20))

	attackAttemptRemote.OnServerEvent:Connect(function(player)
		local weaponDef = WeaponDefs.Tank
		local now = os.clock()
		local last = lastSwingAt[player]

		if last ~= nil and (now - last) < weaponDef.swingCooldown then
			return
		end

		lastSwingAt[player] = now
		dummy:TryAttack(player, weaponDef)
	end)

	parryAttemptRemote.OnServerEvent:Connect(function(player)
		dummy:TryParry(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSwingAt[player] = nil
	end)
end

return CombatServer
