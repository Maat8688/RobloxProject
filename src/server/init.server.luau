--!strict
-- Server bootstrap: combat authority, the dungeon, the start-room stations and
-- the duel arena — then players, who only get a character once their saved
-- progress has loaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CombatServer = require(script.Combat.CombatServer)
local DataService = require(script.DataService)
local DungeonGenerator = require(script.Dungeon.DungeonGenerator)
local BlacksmithService = require(script.Economy.BlacksmithService)
local ArenaService = require(script.PvP.ArenaService)
local SpawnService = require(script.SpawnService)
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
-- weapon stands in front of them. There's no SpawnLocation; SpawnService
-- places every character here.
SpawnService.start(CFrame.lookAt(
	dungeon.startCFrame.Position + Vector3.new(0, 4, 0),
	dungeon.startCFrame.Position + Vector3.new(0, 4, 20)
))

-- Last, so everything a loaded player can touch already exists. DataService
-- hands each player to SpawnService once their profile is ready.
DataService.start()
