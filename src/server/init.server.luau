--!strict
-- Server bootstrap: combat authority, then the dungeon, then the start-room
-- stations and the duel arena.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CombatServer = require(script.Combat.CombatServer)
local DungeonGenerator = require(script.Dungeon.DungeonGenerator)
local BlacksmithService = require(script.Economy.BlacksmithService)
local ArenaService = require(script.PvP.ArenaService)
local WeaponPickups = require(script.WeaponPickups)

-- Remotes must exist before any client starts waiting on them.
Remotes.init()

-- Combat has to be running before the dungeon spawns enemies into it.
CombatServer.start()

local dungeon = DungeonGenerator.generate()

WeaponPickups.start(dungeon.startCFrame)
BlacksmithService.start(dungeon.startCFrame)
ArenaService.start(dungeon.startCFrame)

-- Players start in the safe start room, facing down the dungeon, with the
-- weapon stands in front of them. There is no SpawnLocation, so without this
-- they'd appear wherever Roblox's default puts them.
local spawnCFrame = CFrame.lookAt(
	dungeon.startCFrame.Position + Vector3.new(0, 4, 0),
	dungeon.startCFrame.Position + Vector3.new(0, 4, 20)
)

local function placeCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if root then
		character:PivotTo(spawnCFrame)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(placeCharacter)
	if player.Character then
		placeCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- In Studio the local player can join before this script connects.
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
