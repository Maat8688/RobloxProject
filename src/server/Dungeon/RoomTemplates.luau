-- Room prefab recipes: floor + 4 walls (with an optional door gap on the
-- front/back side), plus one marked enemy-spawn point. One file rather than
-- a RoomTemplates/ folder (as ARCHITECTURE.md's original layout sketch
-- showed) — each template is a short geometry recipe, not enough content to
-- warrant its own file, matching how WeaponDefs.luau/EnemyDefs.luau already
-- keep all their entries in one module.

local RoomTemplates = {}

RoomTemplates.ROOM_SIZE = 40
RoomTemplates.DOOR_WIDTH = 8

local WALL_HEIGHT = 12
local WALL_THICKNESS = 1
local SEGMENT_WIDTH = (RoomTemplates.ROOM_SIZE - RoomTemplates.DOOR_WIDTH) / 2

local function addFloor(model, cframe)
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.CanCollide = true
	floor.Size = Vector3.new(RoomTemplates.ROOM_SIZE, 1, RoomTemplates.ROOM_SIZE)
	floor.CFrame = cframe * CFrame.new(0, -0.5, 0)
	floor.BrickColor = BrickColor.new("Medium stone grey")
	floor.Parent = model
end

local function addSideWalls(model, cframe)
	for _, xSign in { -1, 1 } do
		local wall = Instance.new("Part")
		wall.Name = "SideWall"
		wall.Anchored = true
		wall.CanCollide = true
		wall.Size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, RoomTemplates.ROOM_SIZE)
		wall.CFrame = cframe * CFrame.new(xSign * RoomTemplates.ROOM_SIZE / 2, WALL_HEIGHT / 2, 0)
		wall.BrickColor = BrickColor.new("Light stone grey")
		wall.Parent = model
	end
end

-- zSign = 1 for the "front" wall (+Z, the direction the dungeon extends
-- toward), -1 for the "back" wall. hasDoor leaves an 8-stud gap in the middle.
local function addEndWall(model, cframe, zSign, hasDoor)
	local z = zSign * RoomTemplates.ROOM_SIZE / 2

	if not hasDoor then
		local wall = Instance.new("Part")
		wall.Name = "EndWall"
		wall.Anchored = true
		wall.CanCollide = true
		wall.Size = Vector3.new(RoomTemplates.ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS)
		wall.CFrame = cframe * CFrame.new(0, WALL_HEIGHT / 2, z)
		wall.BrickColor = BrickColor.new("Light stone grey")
		wall.Parent = model
		return
	end

	for _, xSign in { -1, 1 } do
		local segmentX = xSign * (RoomTemplates.DOOR_WIDTH / 2 + SEGMENT_WIDTH / 2)
		local wall = Instance.new("Part")
		wall.Name = "EndWallSegment"
		wall.Anchored = true
		wall.CanCollide = true
		wall.Size = Vector3.new(SEGMENT_WIDTH, WALL_HEIGHT, WALL_THICKNESS)
		wall.CFrame = cframe * CFrame.new(segmentX, WALL_HEIGHT / 2, z)
		wall.BrickColor = BrickColor.new("Light stone grey")
		wall.Parent = model
	end
end

local function addPillars(model, cframe)
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local pillar = Instance.new("Part")
			pillar.Name = "Pillar"
			pillar.Anchored = true
			pillar.CanCollide = true
			pillar.Size = Vector3.new(2, 8, 2)
			pillar.CFrame = cframe * CFrame.new(xSign * 12, 4, zSign * 12)
			pillar.BrickColor = BrickColor.new("Dark stone grey")
			pillar.Parent = model
		end
	end
end

-- Returns the built Model, the world CFrame of this room's marked enemy
-- spawn point, and the world CFrame of its marked chest spot (near the back
-- wall, opposite the enemy spawn).
function RoomTemplates.Build(kind, cframe, hasFrontDoor, hasBackDoor)
	local model = Instance.new("Model")
	model.Name = kind .. "Room"

	addFloor(model, cframe)
	addSideWalls(model, cframe)
	addEndWall(model, cframe, 1, hasFrontDoor)
	addEndWall(model, cframe, -1, hasBackDoor)

	if kind == "Pillars" then
		addPillars(model, cframe)
	end

	local enemySpawnCFrame = cframe * CFrame.new(0, 3, 0)
	local chestCFrame = cframe * CFrame.new(0, 1.5, -15)
	return model, enemySpawnCFrame, chestCFrame
end

return RoomTemplates
