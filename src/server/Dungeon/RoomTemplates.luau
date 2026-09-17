--!strict
-- Room prefab recipes: floor and four walls (with optional door gaps front and
-- back), plus a marked enemy spawn, a marked chest spot, and the room's leash
-- bounds.
--
-- One module rather than a RoomTemplates/ folder: each room kind is a short
-- geometry recipe, not enough content to warrant its own file — the same way
-- WeaponDefs and EnemyDefs keep every entry in one module.

local RoomTemplates = {}

RoomTemplates.ROOM_SIZE = 40
RoomTemplates.DOOR_WIDTH = 8

local WALL_HEIGHT = 12
local WALL_THICKNESS = 1
local SEGMENT_WIDTH = (RoomTemplates.ROOM_SIZE - RoomTemplates.DOOR_WIDTH) / 2

-- How far inside the walls an enemy's leash stops. Enemy rigs are 4 studs
-- wide, so this keeps them from clipping into the wall they're backed against.
local LEASH_INSET = 3

local FLOOR_COLOR = Color3.fromRGB(163, 162, 165)
local WALL_COLOR = Color3.fromRGB(199, 193, 183)
local PILLAR_COLOR = Color3.fromRGB(99, 95, 98)

export type RoomKind = "Empty" | "Pillars"

export type Room = {
	model: Model,
	enemySpawn: CFrame,
	chestSpot: CFrame,
	-- XZ rectangle enemies in this room are leashed to.
	bounds: {
		minX: number,
		maxX: number,
		minZ: number,
		maxZ: number,
	},
}

local function makePart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function addSideWalls(model: Model, cframe: CFrame)
	for _, xSign in { -1, 1 } do
		makePart(
			model,
			"SideWall",
			Vector3.new(WALL_THICKNESS, WALL_HEIGHT, RoomTemplates.ROOM_SIZE),
			cframe * CFrame.new(xSign * RoomTemplates.ROOM_SIZE / 2, WALL_HEIGHT / 2, 0),
			WALL_COLOR
		)
	end
end

-- zSign = 1 for the front wall (+Z, the direction the dungeon extends), -1 for
-- the back. hasDoor leaves a gap in the middle.
local function addEndWall(model: Model, cframe: CFrame, zSign: number, hasDoor: boolean)
	local z = zSign * RoomTemplates.ROOM_SIZE / 2

	if not hasDoor then
		makePart(
			model,
			"EndWall",
			Vector3.new(RoomTemplates.ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS),
			cframe * CFrame.new(0, WALL_HEIGHT / 2, z),
			WALL_COLOR
		)
		return
	end

	for _, xSign in { -1, 1 } do
		local segmentX = xSign * (RoomTemplates.DOOR_WIDTH / 2 + SEGMENT_WIDTH / 2)
		makePart(
			model,
			"EndWallSegment",
			Vector3.new(SEGMENT_WIDTH, WALL_HEIGHT, WALL_THICKNESS),
			cframe * CFrame.new(segmentX, WALL_HEIGHT / 2, z),
			WALL_COLOR
		)
	end
end

local function addPillars(model: Model, cframe: CFrame)
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			makePart(
				model,
				"Pillar",
				Vector3.new(2, 8, 2),
				cframe * CFrame.new(xSign * 12, 4, zSign * 12),
				PILLAR_COLOR
			)
		end
	end
end

-- Rooms are only ever translated, never rotated, so the leash can be an
-- axis-aligned rectangle around the room's centre.
function RoomTemplates.build(kind: RoomKind, cframe: CFrame, hasFrontDoor: boolean, hasBackDoor: boolean): Room
	local model = Instance.new("Model")
	model.Name = `{kind}Room`

	makePart(
		model,
		"Floor",
		Vector3.new(RoomTemplates.ROOM_SIZE, 1, RoomTemplates.ROOM_SIZE),
		cframe * CFrame.new(0, -0.5, 0),
		FLOOR_COLOR
	)
	addSideWalls(model, cframe)
	addEndWall(model, cframe, 1, hasFrontDoor)
	addEndWall(model, cframe, -1, hasBackDoor)

	if kind == "Pillars" then
		addPillars(model, cframe)
	end

	local centre = cframe.Position
	local halfExtent = RoomTemplates.ROOM_SIZE / 2 - LEASH_INSET

	return {
		model = model,
		enemySpawn = cframe * CFrame.new(0, 3, 0),
		-- Near the back wall, where players come in, opposite the enemy.
		chestSpot = cframe * CFrame.new(0, 1.5, -15),
		bounds = {
			minX = centre.X - halfExtent,
			maxX = centre.X + halfExtent,
			minZ = centre.Z - halfExtent,
			maxZ = centre.Z + halfExtent,
		},
	}
end

return RoomTemplates
