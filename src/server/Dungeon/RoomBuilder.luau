--!strict
-- Builds the vertical slice's single test room from Parts at runtime.
--
-- Code-generated rather than a committed .rbxmx model so the room stays
-- diffable in git and the slice runs from a bare place file. Build-order step 4
-- replaces this with hand-built RoomTemplates prefabs; the marker names below
-- (EnemySpawn / PlayerSpawn) are the contract that survives that swap.

local Workspace = game:GetService("Workspace")

local RoomBuilder = {}

local ROOM_SIZE = 80
local WALL_HEIGHT = 20
local WALL_THICKNESS = 2

export type Room = {
	model: Model,
	playerSpawn: Vector3,
	enemySpawn: Vector3,
}

local function makePart(name: string, size: Vector3, position: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function RoomBuilder.build(): Room
	local existing = Workspace:FindFirstChild("TestRoom")
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "TestRoom"

	local floor = makePart("Floor", Vector3.new(ROOM_SIZE, 1, ROOM_SIZE), Vector3.new(0, 0, 0), model)
	floor.Color = Color3.fromRGB(70, 70, 78)
	floor.Material = Enum.Material.Slate

	local half = ROOM_SIZE / 2
	local wallY = WALL_HEIGHT / 2

	local walls = {
		{ name = "WallNorth", size = Vector3.new(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS), pos = Vector3.new(0, wallY, half) },
		{ name = "WallSouth", size = Vector3.new(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS), pos = Vector3.new(0, wallY, -half) },
		{ name = "WallEast", size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE), pos = Vector3.new(half, wallY, 0) },
		{ name = "WallWest", size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE), pos = Vector3.new(-half, wallY, 0) },
	}

	for _, wall in walls do
		local part = makePart(wall.name, wall.size, wall.pos, model)
		part.Color = Color3.fromRGB(48, 48, 56)
		part.Material = Enum.Material.Concrete
	end

	model.Parent = Workspace

	-- Spawns face each other across the room's short axis, far enough apart
	-- that the player has to close distance and can retreat out of range.
	return {
		model = model,
		playerSpawn = Vector3.new(0, 4, -15),
		enemySpawn = Vector3.new(0, 3, 15),
	}
end

return RoomBuilder
