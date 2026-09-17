--!strict
-- Builds a rig's body from RigDefs: parts, Motor6D joints, and welded
-- decorations.
--
-- It uses only the Roblox-style API handed to it, never globals. The game
-- passes Roblox's own `Instance`, `CFrame` and friends; the animation
-- workbench generator passes @lune/roblox's. One implementation therefore
-- builds both the rigs enemies wear in game and the rigs animations are
-- refined on, so the two can't drift apart.
--
-- Not a pure module (it creates instances), so it isn't on ARCHITECTURE.md's
-- pure-module list, and no spec loads it; the workbench generator exercises
-- it and checks what it built.

local RigDefs = require(script.Parent.RigDefs)

local RigAssembly = {}

-- The slice of the Roblox API this module uses.
export type Api = {
	Instance: any,
	CFrame: any,
	Vector3: any,
	Color3: any,
	Enum: any,
}

local ORIGIN = { 0, 0, 0 }

local centers: { [string]: { number } } = { HumanoidRootPart = ORIGIN }
for _, part in RigDefs.SKELETON do
	centers[part.name] = part.center
end

local function offset(api: Api, from: { number }, to: { number }): any
	return api.CFrame.new(to[1] - from[1], to[2] - from[2], to[3] - from[3])
end

local function color(api: Api, rgb: { number }): any
	return api.Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function makePart(api: Api, name: string, size: any, rgb: { number }, material: string?, shape: string?): any
	local part = api.Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color(api, rgb)
	part.Material = api.Enum.Material[material or "SmoothPlastic"]
	if shape then
		part.Shape = api.Enum.PartType[shape]
	end
	part.TopSurface = api.Enum.SurfaceType.Smooth
	part.BottomSurface = api.Enum.SurfaceType.Smooth
	-- Visual only: the root is the hitbox and the only thing that collides.
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	return part
end

-- Builds the body around `root`, which must already be where the rig should
-- stand, and parents it all to `parent`. Returns every body part by name,
-- including the root.
function RigAssembly.attach(api: Api, root: any, rigId: string, parent: any): { [string]: any }
	local style = RigDefs.styleOf(rigId)
	local parts: { [string]: any } = { HumanoidRootPart = root }
	local rootCFrame = root.CFrame

	for _, def in RigDefs.SKELETON do
		local partStyle = RigDefs.partStyle(style, def.name)
		local size = api.Vector3.new(
			def.size[1] * (partStyle.width or 1),
			def.size[2],
			def.size[3] * (partStyle.depth or 1)
		)

		local part = makePart(api, def.name, size, partStyle.color, partStyle.material, nil)
		part.CFrame = rootCFrame * offset(api, ORIGIN, def.center)
		part.Parent = parent

		-- R15 convention: the joint lives in the part it moves, and C0/C1 both
		-- point at the pivot, so a joint's Transform rotates about it.
		local joint = api.Instance.new("Motor6D")
		joint.Name = def.joint
		joint.Part0 = parts[def.parent]
		joint.Part1 = part
		joint.C0 = offset(api, centers[def.parent], def.pivot)
		joint.C1 = offset(api, def.center, def.pivot)
		joint.Parent = part

		parts[def.name] = part
	end

	for _, decoration in style.decorations do
		local host = parts[decoration.attachTo]
		local size = api.Vector3.new(decoration.size[1], decoration.size[2], decoration.size[3])
		local piece = makePart(api, decoration.name, size, decoration.color, decoration.material, decoration.shape)
		piece.Transparency = decoration.transparency or 0

		local placement = offset(api, ORIGIN, decoration.offset)
		piece.CFrame = host.CFrame * placement
		piece.Parent = parent

		local weld = api.Instance.new("Weld")
		weld.Name = `{decoration.name}Weld`
		weld.Part0 = host
		weld.Part1 = piece
		weld.C0 = placement
		weld.Parent = piece
	end

	return parts
end

-- What the Animation Editor needs to recognise a non-Humanoid rig, and what a
-- published animation plays through.
function RigAssembly.addAnimator(api: Api, model: any): any
	local controller = api.Instance.new("AnimationController")
	controller.Parent = model

	local animator = api.Instance.new("Animator")
	animator.Parent = controller

	return animator
end

-- A complete standalone rig: model, invisible root sized like an enemy
-- hitbox, body, and animator. Used by the workbench.
function RigAssembly.build(api: Api, rigId: string, cframe: any): any
	local model = api.Instance.new("Model")
	model.Name = rigId

	local root = api.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = api.Vector3.new(RigDefs.ROOT_SIZE[1], RigDefs.ROOT_SIZE[2], RigDefs.ROOT_SIZE[3])
	root.CFrame = cframe
	root.Anchored = true
	root.CanCollide = false
	root.Transparency = 1
	root.Parent = model

	model.PrimaryPart = root
	RigAssembly.attach(api, root, rigId, model)
	RigAssembly.addAnimator(api, model)

	return model
end

return RigAssembly
