local DungeonGenerator = require(script:WaitForChild("Dungeon"):WaitForChild("DungeonGenerator"))
local dungeon = DungeonGenerator.Generate()

local WeaponPickups = require(script:WaitForChild("WeaponPickups"))
WeaponPickups.Start(dungeon.startCFrame)

local BlacksmithService = require(script:WaitForChild("Economy"):WaitForChild("BlacksmithService"))
BlacksmithService.Start(dungeon.startCFrame)

local CombatServer = require(script:WaitForChild("Combat"):WaitForChild("CombatServer"))
CombatServer.Start(dungeon.enemies)
