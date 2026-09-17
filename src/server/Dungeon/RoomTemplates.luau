--!strict
-- Room geometry: a square floor, four walls with a door gap on any side that
-- needs one, the variant's inner layout (pillars, ruins, a throne hall), and
-- torches. Also the corridors between rooms, so every piece of dungeon shares
-- one look.
--
-- One module rather than a RoomTemplates/ folder: each variant is a short
-- geometry recipe, not enough content to warrant its own file — the same way
-- WeaponDefs and EnemyDefs keep every entry in one module.
--
-- Rooms are only ever translated, never rotated, so walls, corridors and the
-- leash are all axis-aligned. Dressing (trim, arches, torches, rubble) is
-- decoration: it never collides except where a player would expect to bump
-- into something, and never changes a room's size, doors or leash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonDefs = require(ReplicatedStorage.Shared.DungeonDefs)

local RoomTemplates = {}

RoomTemplates.DOOR_WIDTH = DungeonDefs.CORRIDOR_WIDTH

local WALL_HEIGHT = 12
local WALL_THICKNESS = 1

-- How far inside the walls an enemy's leash stops, so a rig backed against a
-- wall doesn't clip into it. Scaled by the rig's size where it's used.
RoomTemplates.LEASH_INSET = 3

local FLOOR_COLOR = Color3.fromRGB(78, 74, 80)
local WALL_COLOR = Color3.fromRGB(104, 96, 90)
local TRIM_COLOR = Color3.fromRGB(62, 58, 62)
local PILLAR_COLOR = Color3.fromRGB(120, 112, 106)
local RUBBLE_COLOR = Color3.fromRGB(90, 84, 82)
local IRON_COLOR = Color3.fromRGB(45, 42, 44)
local DEFAULT_TORCH = Color3.fromRGB(255, 150, 70)

local TORCH_HEIGHT = 7

export type Side = "North" | "South" | "East" | "West"

export type Bounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

export type RoomSpec = {
	variant: DungeonDefs.RoomVariant,
	size: number,
	doors: { [Side]: boolean },
	-- The side the way in is on, so a hall's throne faces the door.
	entrance: Side?,
	torchColor: Color3?,
}

export type Room = {
	model: Model,
	-- The centre of the floor's top surface.
	centre: CFrame,
	size: number,
	-- The whole floor inside the walls, for "is anyone in this room".
	floorBounds: Bounds,
}

-- Yaw that turns a room-local frame so its +Z points out through `side`.
local SIDE_YAW: { [Side]: number } = {
	North = 0,
	East = math.rad(90),
	South = math.rad(180),
	West = math.rad(-90),
}

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Decoration a player walks through rather than snags on.
local function makeDecor(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = makePart(parent, name, size, cframe, color, material)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- A wall with a darker cap along its top and a skirting along its base.
-- `cframe` is the wall's centre; its local X runs along the wall.
local function makeWall(model: Instance, name: string, length: number, cframe: CFrame)
	makePart(model, name, Vector3.new(length, WALL_HEIGHT, WALL_THICKNESS), cframe, WALL_COLOR, Enum.Material.Cobblestone)
	makeDecor(model, `{name}Cap`, Vector3.new(length + 0.4, 0.6, WALL_THICKNESS + 0.4), cframe * CFrame.new(0, WALL_HEIGHT / 2 + 0.3, 0), TRIM_COLOR, Enum.Material.Slate)
	makeDecor(model, `{name}Skirt`, Vector3.new(length + 0.3, 0.8, WALL_THICKNESS + 0.3), cframe * CFrame.new(0, -WALL_HEIGHT / 2 + 0.4, 0), TRIM_COLOR, Enum.Material.Slate)
end

-- An iron bracket holding a burning torch. `cframe` is on the wall's inner
-- face, looking into the room.
local function addTorch(model: Instance, cframe: CFrame, color: Color3)
	makeDecor(model, "TorchBracket", Vector3.new(0.3, 0.3, 1.2), cframe * CFrame.new(0, 0, -0.6), IRON_COLOR, Enum.Material.Metal)
	local head = makeDecor(model, "Torch", Vector3.new(0.5, 1.2, 0.5), cframe * CFrame.new(0, 0.4, -1.1), Color3.fromRGB(90, 60, 35), Enum.Material.Wood)

	local fire = Instance.new("Fire")
	fire.Size = 2.5
	fire.Heat = 7
	fire.Color = color
	fire.SecondaryColor = color:Lerp(Color3.new(0, 0, 0), 0.5)
	fire.Parent = head

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2.2
	light.Range = 24
	light.Shadows = true
	light.Parent = head
end

-- One side of a room: a full wall, or two segments framing a doorway, plus
-- its torches.
local function addSide(model: Model, centre: CFrame, size: number, side: Side, hasDoor: boolean, torchColor: Color3)
	-- Local +Z points out through this side; local X runs along its wall.
	local frame = centre * CFrame.Angles(0, SIDE_YAW[side], 0)
	local wallZ = size / 2 + WALL_THICKNESS / 2

	if hasDoor then
		local segment = (size - RoomTemplates.DOOR_WIDTH) / 2
		for _, sign in { -1, 1 } do
			local x = sign * (RoomTemplates.DOOR_WIDTH / 2 + segment / 2)
			makeWall(model, "WallSegment", segment + WALL_THICKNESS, frame * CFrame.new(x, WALL_HEIGHT / 2, wallZ))

			-- A heavy post either side of the doorway.
			local postX = sign * (RoomTemplates.DOOR_WIDTH / 2 + 0.6)
			makePart(model, "DoorPost", Vector3.new(1.2, WALL_HEIGHT, 1.8), frame * CFrame.new(postX, WALL_HEIGHT / 2, wallZ), TRIM_COLOR, Enum.Material.Slate)
		end

		-- The lintel over the doorway, high enough to never catch a player.
		makeDecor(
			model,
			"DoorLintel",
			Vector3.new(RoomTemplates.DOOR_WIDTH + 2.4, 1.6, 1.8),
			frame * CFrame.new(0, WALL_HEIGHT - 1.7, wallZ),
			TRIM_COLOR,
			Enum.Material.Slate
		)
	else
		makeWall(model, "Wall", size + WALL_THICKNESS * 2, frame * CFrame.new(0, WALL_HEIGHT / 2, wallZ))
	end

	-- Torches either side of centre on bigger walls, one on smaller ones,
	-- always clear of the doorway.
	local offsets = if size >= 52 then { -size / 4, size / 4 } else { size / 4 }
	for _, x in offsets do
		local mount = frame * CFrame.new(x, TORCH_HEIGHT, size / 2)
		local inward = frame * CFrame.new(x, TORCH_HEIGHT, 0)
		addTorch(model, CFrame.lookAt(mount.Position, inward.Position), torchColor)
	end
end

local function addPillar(model: Model, base: CFrame, height: number)
	makePart(model, "Pillar", Vector3.new(2, height, 2), base * CFrame.new(0, height / 2, 0), PILLAR_COLOR, Enum.Material.Granite)
	makeDecor(model, "PillarBase", Vector3.new(2.8, 0.8, 2.8), base * CFrame.new(0, 0.4, 0), TRIM_COLOR, Enum.Material.Slate)
	makeDecor(model, "PillarCapital", Vector3.new(2.8, 0.6, 2.8), base * CFrame.new(0, height + 0.3, 0), TRIM_COLOR, Enum.Material.Slate)
end

-- Four pillars, a third of the way in from each corner: cover to break a
-- Spitter's line, and something to circle a melee enemy around.
local function addPillars(model: Model, centre: CFrame, size: number)
	local at = size * 0.28
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			addPillar(model, centre * CFrame.new(xSign * at, 0, zSign * at), 8)
		end
	end
end

-- Broken, waist-high walls on the diagonals: cover that doesn't block the view
-- of a telegraph. Kept out of the centre, where enemies spawn, and off the
-- straight lines between doors.
local function addRuins(model: Model, centre: CFrame, size: number)
	for i = 0, 3 do
		local angle = math.rad(45 + 90 * i) + (math.random() - 0.5) * 0.3
		local radius = size * (0.28 + math.random() * 0.06)
		local length = 2.5 + math.random() * 2
		local height = 2 + math.random() * 1.5
		local base = centre * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			* CFrame.Angles(0, angle + math.pi / 2 + (math.random() - 0.5) * 0.5, 0)

		makePart(model, "RuinWall", Vector3.new(length, height, 1.2), base * CFrame.new(0, height / 2, 0), WALL_COLOR, Enum.Material.Cobblestone)
		makeDecor(model, "RuinRubble", Vector3.new(1.2, 0.8, 1), base * CFrame.new(length / 2 + 0.6, 0.4, 0.8) * CFrame.Angles(0, 0.6, 0.3), RUBBLE_COLOR, Enum.Material.Slate)
	end
end

-- The boss's hall: two rows of tall pillars down the long axis, braziers of
-- ghost fire, and a throne against the wall opposite the door.
local function addHall(model: Model, centre: CFrame, size: number, entrance: Side?)
	local towardThrone = centre * CFrame.Angles(0, SIDE_YAW[entrance or "South"] + math.pi, 0)

	for _, x in { -size * 0.34, size * 0.34 } do
		for _, z in { -size * 0.3, 0, size * 0.3 } do
			addPillar(model, towardThrone * CFrame.new(x, 0, z), 10)
		end
	end

	local throneBack = towardThrone * CFrame.new(0, 0, size / 2 - 2)
	makePart(model, "ThroneDais", Vector3.new(10, 0.8, 5), throneBack * CFrame.new(0, 0.4, -1), TRIM_COLOR, Enum.Material.Slate)
	makePart(model, "ThroneSeat", Vector3.new(4, 2.6, 3), throneBack * CFrame.new(0, 2.1, -0.5), IRON_COLOR, Enum.Material.Metal)
	makeDecor(model, "ThroneBack", Vector3.new(4.4, 7, 0.8), throneBack * CFrame.new(0, 4.3, 0.8), IRON_COLOR, Enum.Material.Metal)
	for _, x in { -2.1, 0, 2.1 } do
		makeDecor(model, "ThroneSpike", Vector3.new(0.4, 1.6, 0.4), throneBack * CFrame.new(x, 8.4, 0.8), Color3.fromRGB(150, 120, 60), Enum.Material.Metal)
	end

	for _, x in { -6.5, 6.5 } do
		local brazier = makePart(model, "Brazier", Vector3.new(2, 3, 2), throneBack * CFrame.new(x, 1.5, -1.5), IRON_COLOR, Enum.Material.Metal)
		local flames = makeDecor(brazier, "Flames", Vector3.new(1.4, 0.2, 1.4), brazier.CFrame * CFrame.new(0, 1.6, 0), Color3.fromRGB(110, 190, 255), Enum.Material.Neon)

		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 10
		fire.Color = Color3.fromRGB(110, 190, 255)
		fire.SecondaryColor = Color3.fromRGB(30, 60, 140)
		fire.Parent = flames

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(110, 190, 255)
		light.Brightness = 3
		light.Range = 26
		light.Shadows = true
		light.Parent = flames
	end
end

-- A few loose stones along the walls, placed at random so no two rooms look
-- quite alike. Kept to the edges and out of doorways.
local function addRubble(model: Model, centre: CFrame, size: number)
	local edge = size / 2 - 2.5
	for _ = 1, math.random(3, 6) do
		local alongX = math.random() < 0.5
		local along = (math.random() - 0.5) * (size - 10)
		if math.abs(along) < RoomTemplates.DOOR_WIDTH / 2 + 2 then
			continue
		end

		local wallSide = if math.random() < 0.5 then -edge else edge
		local x = if alongX then along else wallSide
		local z = if alongX then wallSide else along

		local stone = 0.6 + math.random() * 1.2
		local rock = makeDecor(
			model,
			"Rubble",
			Vector3.new(stone, stone * 0.6, stone * (0.8 + math.random() * 0.4)),
			centre * CFrame.new(x, stone * 0.25, z) * CFrame.Angles(0, math.random() * math.pi, math.rad(math.random(-15, 15))),
			RUBBLE_COLOR,
			Enum.Material.Slate
		)
		rock.CastShadow = false
	end
end

-- `origin` is the room's floor centre in the world.
function RoomTemplates.build(spec: RoomSpec, origin: CFrame): Room
	local size = spec.size
	local centre = CFrame.new(origin.Position)
	local torchColor = spec.torchColor or DEFAULT_TORCH

	local model = Instance.new("Model")
	model.Name = `{spec.variant}Room`

	makePart(model, "Floor", Vector3.new(size + WALL_THICKNESS * 2, 1, size + WALL_THICKNESS * 2), centre * CFrame.new(0, -0.5, 0), FLOOR_COLOR, Enum.Material.Slate)

	for side in SIDE_YAW do
		addSide(model, centre, size, side, spec.doors[side] == true, torchColor)
	end

	addRubble(model, centre, size)

	if spec.variant == "Pillars" then
		addPillars(model, centre, size)
	elseif spec.variant == "Ruins" then
		addRuins(model, centre, size)
	elseif spec.variant == "Hall" then
		addHall(model, centre, size, spec.entrance)
	end

	local position = centre.Position
	local half = size / 2

	return {
		model = model,
		centre = centre,
		size = size,
		floorBounds = {
			minX = position.X - half,
			maxX = position.X + half,
			minZ = position.Z - half,
			maxZ = position.Z + half,
		},
	}
end

-- Where an enemy in this room may go: the floor, less `inset` from each wall.
function RoomTemplates.leashBounds(room: Room, inset: number): Bounds
	local bounds = room.floorBounds
	return {
		minX = bounds.minX + inset,
		maxX = bounds.maxX - inset,
		minZ = bounds.minZ + inset,
		maxZ = bounds.maxZ - inset,
	}
end

-- A walled passage centred on `centre` (floor level), `length` long, running
-- east-west when `alongX`, otherwise north-south. Walled so nobody walks off
-- the edge into the void.
function RoomTemplates.buildCorridor(parent: Instance, centre: Vector3, length: number, alongX: boolean): Model
	local model = Instance.new("Model")
	model.Name = "Corridor"

	-- Local Z runs along the corridor.
	local frame = CFrame.new(centre) * CFrame.Angles(0, if alongX then math.rad(90) else 0, 0)
	makePart(model, "Floor", Vector3.new(RoomTemplates.DOOR_WIDTH, 1, length), frame * CFrame.new(0, -0.5, 0), FLOOR_COLOR, Enum.Material.Slate)

	for _, sign in { -1, 1 } do
		local x = sign * (RoomTemplates.DOOR_WIDTH / 2 + WALL_THICKNESS / 2)
		makeWall(model, "CorridorWall", length, frame * CFrame.new(x, WALL_HEIGHT / 2, 0) * CFrame.Angles(0, math.rad(90), 0))
	end

	-- One lantern overhead, so the walk between rooms isn't pitch dark.
	local lantern = makeDecor(model, "Lantern", Vector3.new(0.8, 1, 0.8), frame * CFrame.new(0, WALL_HEIGHT - 3, 0), Color3.fromRGB(255, 190, 110), Enum.Material.Neon)
	makeDecor(model, "LanternChain", Vector3.new(0.12, 2.2, 0.12), frame * CFrame.new(0, WALL_HEIGHT - 1.4, 0), IRON_COLOR, Enum.Material.Metal)
	local light = Instance.new("PointLight")
	light.Color = DEFAULT_TORCH
	light.Brightness = 1.2
	light.Range = 14
	light.Parent = lantern

	model.Parent = parent
	return model
end

return RoomTemplates
