--!strict
-- Combat sandbox bootstrap: build the room, spawn the roster, start combat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CombatServer = require(script.Combat.CombatServer)
local RoomBuilder = require(script.Dungeon.RoomBuilder)

-- Remotes must exist before any client starts waiting on them.
Remotes.init()

local room = RoomBuilder.build()

-- One of each type, spread out so their different movement rules are visible
-- from the player spawn: the dummy holds, the Shambler closes, the Spitter
-- backs off to its preferred range. Encounter composition becomes the dungeon
-- generator's job at build-order step 4.
local roster = {
	{ defId = "TrainingDummy", position = room.enemySpawn },
	{ defId = "Shambler", position = room.enemySpawn + Vector3.new(-18, 0, -6) },
	{ defId = "Spitter", position = room.enemySpawn + Vector3.new(18, 0, 4) },
}

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

CombatServer.start(roster, room.playerSpawn)
