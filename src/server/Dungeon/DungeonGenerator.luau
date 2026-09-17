-- Stitches rooms (RoomTemplates) and enemies (Combat/Enemy) into a straight
-- chain: one Start room, then 3-5 random Combat rooms connected by corridor
-- floor segments. "Procedurally generated" here means room count, room kind,
-- and enemy type per room are randomized each server start — not a full
-- branching layout algorithm, which is a reasonable later enhancement (see
-- DESIGN.md). Each combat room's single enemy also guards that room's
-- chest (ChestService) — a real multi-enemy "encounter group" only matters
-- once rooms can hold more than one enemy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EnemyDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EnemyDefs"))

local ChestService = require(script.Parent.ChestService)
local RoomTemplates = require(script.Parent.RoomTemplates)
local CurrencyService = require(script.Parent.Parent.Economy.CurrencyService)
local Enemy = require(script.Parent.Parent.Combat.Enemy)

local CORRIDOR_LENGTH = 10
local ROOM_SPACING = RoomTemplates.ROOM_SIZE + CORRIDOR_LENGTH

local COMBAT_ROOM_KINDS = { "Empty", "Pillars" }
local ENEMY_TYPES = { "TrainingDummy", "SkeletonWarrior" }

local DungeonGenerator = {}

local function addCorridor(dungeonFolder, fromCFrame, toCFrame)
	local corridor = Instance.new("Part")
	corridor.Name = "Corridor"
	corridor.Anchored = true
	corridor.CanCollide = true
	corridor.Size = Vector3.new(RoomTemplates.DOOR_WIDTH, 1, CORRIDOR_LENGTH)
	corridor.CFrame = CFrame.new(
		fromCFrame.Position.X,
		-0.5,
		(fromCFrame.Position.Z + toCFrame.Position.Z) / 2
	)
	corridor.BrickColor = BrickColor.new("Medium stone grey")
	corridor.Parent = dungeonFolder
end

function DungeonGenerator.Generate()
	local dungeonFolder = Instance.new("Folder")
	dungeonFolder.Name = "Dungeon"
	dungeonFolder.Parent = Workspace

	local startCFrame = CFrame.new(0, 0, 0)
	local startModel = RoomTemplates.Build("Empty", startCFrame, true, false)
	startModel.Name = "StartRoom"
	startModel.Parent = dungeonFolder

	local combatRoomCount = math.random(3, 5)
	local enemies = {}
	local previousCFrame = startCFrame

	for i = 1, combatRoomCount do
		local roomCFrame = startCFrame * CFrame.new(0, 0, ROOM_SPACING * i)
		local hasFrontDoor = i < combatRoomCount
		local kind = COMBAT_ROOM_KINDS[math.random(#COMBAT_ROOM_KINDS)]

		local model, enemySpawnCFrame, chestCFrame = RoomTemplates.Build(kind, roomCFrame, hasFrontDoor, true)
		model.Parent = dungeonFolder

		addCorridor(dungeonFolder, previousCFrame, roomCFrame)

		local enemyType = ENEMY_TYPES[math.random(#ENEMY_TYPES)]
		local enemyId = enemyType .. "_" .. i
		local enemy = Enemy.new(enemyId, EnemyDefs[enemyType], enemySpawnCFrame, dungeonFolder)
		table.insert(enemies, enemy)

		ChestService.CreateChest(chestCFrame, enemy, enemyType, dungeonFolder)
		CurrencyService.TrackEnemy(enemy, enemyType)

		previousCFrame = roomCFrame
	end

	return {
		startCFrame = startCFrame,
		enemies = enemies,
	}
end

return DungeonGenerator
