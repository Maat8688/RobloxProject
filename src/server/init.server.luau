local DungeonGenerator = require(script:WaitForChild("Dungeon"):WaitForChild("DungeonGenerator"))
local dungeon = DungeonGenerator.Generate()

local WeaponPickups = require(script:WaitForChild("WeaponPickups"))
WeaponPickups.Start(dungeon.startCFrame)

local BlacksmithService = require(script:WaitForChild("Economy"):WaitForChild("BlacksmithService"))
BlacksmithService.Start(dungeon.startCFrame)

local CombatServer = require(script:WaitForChild("Combat"):WaitForChild("CombatServer"))
CombatServer.Start(dungeon.enemies)

local PvP = script:WaitForChild("PvP")
local ArenaService = require(PvP:WaitForChild("ArenaService"))
ArenaService.Start(dungeon.startCFrame)

local PvPCombatServer = require(PvP:WaitForChild("PvPCombatServer"))
PvPCombatServer.Start(ArenaService)
