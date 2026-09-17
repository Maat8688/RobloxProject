--!strict
-- Stitches rooms (RoomTemplates) and enemies into a straight chain: one safe
-- Start room, then 3-5 random combat rooms joined by corridors.
--
-- "Procedurally generated" here means room count, room kind and enemy type per
-- room change every server start. It is still room-prefab + connector based,
-- as DESIGN.md requires; a branching layout algorithm is a reasonable later
-- enhancement, not a gap.
--
-- Each combat room's single enemy guards that room's chest. A multi-enemy
-- encounter group only matters once rooms hold more than one enemy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EnemyDefs = require(ReplicatedStorage.Shared.EnemyDefs)

local CombatServer = require(script.Parent.Parent.Combat.CombatServer)
local CurrencyService = require(script.Parent.Parent.Economy.CurrencyService)
local ChestService = require(script.Parent.ChestService)
local RoomTemplates = require(script.Parent.RoomTemplates)

local CORRIDOR_LENGTH = 10
local ROOM_SPACING = RoomTemplates.ROOM_SIZE + CORRIDOR_LENGTH
local MIN_COMBAT_ROOMS = 3
local MAX_COMBAT_ROOMS = 5

local COMBAT_ROOM_KINDS: { RoomTemplates.RoomKind } = { "Empty", "Pillars" }

local DungeonGenerator = {}

export type Dungeon = {
	startCFrame: CFrame,
}

-- Every defined enemy is eligible, in a stable order so a seeded run would be
-- reproducible. Adding an enemy type puts it into rotation automatically.
local function enemyPool(): { string }
	local pool = {}
	for defId in EnemyDefs do
		table.insert(pool, defId)
	end
	table.sort(pool)
	return pool
end

local function addCorridor(folder: Folder, from: CFrame, to: CFrame)
	local corridor = Instance.new("Part")
	corridor.Name = "Corridor"
	corridor.Anchored = true
	corridor.CanCollide = true
	corridor.Size = Vector3.new(RoomTemplates.DOOR_WIDTH, 1, CORRIDOR_LENGTH)
	corridor.CFrame = CFrame.new(from.Position.X, -0.5, (from.Position.Z + to.Position.Z) / 2)
	corridor.Color = Color3.fromRGB(163, 162, 165)
	corridor.Parent = folder
end

function DungeonGenerator.generate(): Dungeon
	local folder = Instance.new("Folder")
	folder.Name = "Dungeon"
	folder.Parent = Workspace

	local startCFrame = CFrame.new(0, 0, 0)
	local startRoom = RoomTemplates.build("Empty", startCFrame, true, false)
	startRoom.model.Name = "StartRoom"
	startRoom.model.Parent = folder

	local pool = enemyPool()
	local roomCount = math.random(MIN_COMBAT_ROOMS, MAX_COMBAT_ROOMS)
	local previous = startCFrame

	for i = 1, roomCount do
		local roomCFrame = startCFrame * CFrame.new(0, 0, ROOM_SPACING * i)
		local kind = COMBAT_ROOM_KINDS[math.random(#COMBAT_ROOM_KINDS)]
		local isLast = i == roomCount

		local room = RoomTemplates.build(kind, roomCFrame, not isLast, true)
		room.model.Parent = folder
		addCorridor(folder, previous, roomCFrame)

		-- Facing the back door, which is where players walk in from.
		local faceTowards = roomCFrame.Position + Vector3.new(0, 0, -RoomTemplates.ROOM_SIZE / 2)
		local defId = pool[math.random(#pool)]

		local guard = CombatServer.spawnEnemy(defId, room.enemySpawn.Position, faceTowards, room.bounds, folder)
		ChestService.createChest(room.chestSpot, guard, folder)
		CurrencyService.trackEnemy(guard)

		previous = roomCFrame
	end

	return {
		startCFrame = startCFrame,
	}
end

return DungeonGenerator
