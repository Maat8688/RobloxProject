--!strict
-- Vertical slice bootstrap: build the room, spawn the enemy, start combat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CombatServer = require(script.Combat.CombatServer)
local RoomBuilder = require(script.Dungeon.RoomBuilder)

-- Remotes must exist before any client starts waiting on them.
Remotes.init()

local room = RoomBuilder.build()

-- Drop players into the room rather than wherever the empty baseplate would
-- put them.
local function placeCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if root then
		root.CFrame = CFrame.lookAt(room.playerSpawn, room.enemySpawn)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(placeCharacter)
	if player.Character then
		placeCharacter(player.Character)
	end
end)

CombatServer.start(room.enemySpawn, room.playerSpawn)
