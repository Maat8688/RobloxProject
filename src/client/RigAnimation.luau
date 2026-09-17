--!strict
-- Plays AnimationDefs animations on one rig, by writing its Motor6D
-- Transforms every frame — and hands any animation with a published version
-- (AnimationIds) to Roblox's Animator instead.
--
-- Two layers, like Roblox animation priorities: a looping base (idle, walk)
-- and a one-shot action (an attack, a stagger, death). An action poses only
-- the parts it animates; the base keeps moving the rest.
--
-- A rig whose base belongs to someone else — a player's avatar, whose walk
-- and idle come from Roblox's Animate script — is "external". There, an
-- action is blended over whatever the joints already hold, and nothing else
-- is touched.
--
-- Runs on each client, for that client's view only. Transforms are written in
-- PreSimulation: after the Animator has posed the rig for this frame, and
-- before joints are applied — the point where a script's pose wins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AnimationDefs = require(Shared.AnimationDefs)
local AnimationIds = require(Shared.AnimationIds)
local KeyframeMath = require(Shared.KeyframeMath)

local RigAnimation = {}

-- How long a switch between animations blends.
local CROSSFADE = 0.15

-- External rigs: how quickly an action takes over, and lets go at the end.
local OVERLAY_FADE_IN = 0.06
local OVERLAY_FADE_OUT = 0.12

-- The keyframe a refined strike must keep, so its timing survives publishing.
local IMPACT_KEYFRAME = "Impact"

type AnimationDef = KeyframeMath.AnimationDef
type PoseMap = KeyframeMath.PoseMap

export type ActionOptions = {
	-- Strikes: real seconds from the start of the windup to impact. Everything
	-- before the animation's impact keyframe is stretched to fit.
	windup: number?,
	-- Seconds of the action already over before it started playing here, e.g.
	-- a telegraph message that arrived late.
	elapsed: number?,
	-- Anything else: stretch the whole animation over this many seconds.
	duration: number?,
	-- Stay on the last frame when finished (death), until stopped.
	hold: boolean?,
}

type Layer = {
	name: string,
	anim: AnimationDef,
	startedAt: number,
	windup: number?,
	timeScale: number,
	hold: boolean,
	-- Loops advance by accumulated phase, so a change of speed doesn't jump.
	phase: number,
	track: AnimationTrack?,
}

export type Controller = {
	model: Model,
	rigId: string,
	joints: { [string]: Motor6D },
	animator: Animator?,
	external: boolean,
	base: Layer?,
	baseSpeed: number,
	action: Layer?,
	fadeFrom: PoseMap?,
	fadeStart: number,
	lastPose: PoseMap,
	written: { [string]: boolean },
	tracks: { [string]: AnimationTrack },
}

local function clock(): number
	return os.clock()
end

local function findJoints(model: Model): { [string]: Motor6D }
	local joints = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part1 then
			joints[descendant.Part1.Name] = descendant
		end
	end
	return joints
end

function RigAnimation.new(model: Model, rigId: string, external: boolean): Controller
	return {
		model = model,
		rigId = rigId,
		joints = findJoints(model),
		animator = model:FindFirstChildWhichIsA("Animator", true),
		external = external,
		base = nil,
		baseSpeed = 1,
		action = nil,
		fadeFrom = nil,
		fadeStart = 0,
		lastPose = {},
		written = {},
		tracks = {},
	}
end

-- How many joints were found: callers wait for a replicating rig to be whole.
function RigAnimation.jointCount(controller: Controller): number
	local count = 0
	for _ in controller.joints do
		count += 1
	end
	return count
end

-- The published version of an animation, loaded once, if it has one.
local function publishedTrack(controller: Controller, name: string): AnimationTrack?
	local id = AnimationIds.get(controller.rigId, name)
	local animator = controller.animator
	if not id or not animator then
		return nil
	end

	local cached = controller.tracks[name]
	if cached then
		return cached
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = id

	local ok, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok then
		warn(`[RigAnimation] Couldn't load {controller.rigId}/{name} ({id}); using the rough version. {result}`)
		return nil
	end

	controller.tracks[name] = result
	return result
end

-- Whether this frame's rough poses go on top of something else writing the
-- joints: a player's Animate script, or this rig's own published base
-- animation. Either way, blend over the joints instead of replacing them.
local function overlaysAnimator(controller: Controller): boolean
	local base = controller.base
	return controller.external or (base ~= nil and base.track ~= nil)
end

-- Start blending from whatever the rig showed last frame.
local function beginFade(controller: Controller)
	if overlaysAnimator(controller) then
		return
	end
	controller.fadeFrom = controller.lastPose
	controller.fadeStart = clock()
end

local function actionTime(layer: Layer, now: number): number
	local elapsed = now - layer.startedAt
	local impact = layer.anim.impact
	if layer.windup and impact then
		return KeyframeMath.alignedTime(elapsed, impact, layer.windup)
	end
	return elapsed * layer.timeScale
end

function RigAnimation.setBase(controller: Controller, name: string, speed: number?)
	controller.baseSpeed = speed or 1

	local current = controller.base
	if current and current.name == name then
		if current.track then
			current.track:AdjustSpeed(controller.baseSpeed)
		end
		return
	end

	local anim = AnimationDefs.get(controller.rigId, name)
	if not anim then
		return
	end

	if current and current.track then
		current.track:Stop(CROSSFADE)
	end

	local track = publishedTrack(controller, name)
	if track then
		track.Looped = true
		track:Play(CROSSFADE, 1, controller.baseSpeed)
	end

	if not controller.action then
		beginFade(controller)
	end

	controller.base = {
		name = name,
		anim = anim,
		startedAt = clock(),
		windup = nil,
		timeScale = 1,
		hold = false,
		phase = 0,
		track = track,
	}
end

function RigAnimation.playAction(controller: Controller, name: string, options: ActionOptions?)
	local anim = AnimationDefs.get(controller.rigId, name)
	if not anim then
		return
	end

	local opts: ActionOptions = options or {}
	local previous = controller.action
	if previous and previous.track then
		previous.track:Stop(CROSSFADE)
	end

	local elapsed = math.max(opts.elapsed or 0, 0)
	local duration = opts.duration
	local layer: Layer = {
		name = name,
		anim = anim,
		startedAt = clock() - elapsed,
		windup = opts.windup,
		timeScale = if duration and duration > 0 then anim.length / duration else 1,
		hold = opts.hold == true,
		phase = 0,
		track = nil,
	}

	local track = publishedTrack(controller, name)
	if track then
		track.Looped = false
		track.Priority = Enum.AnimationPriority.Action

		local speed = layer.timeScale
		local windup = opts.windup
		if windup and windup > 0 then
			-- Needs the animation loaded; if it isn't yet, play at normal speed
			-- rather than guess.
			local ok, impactAt = pcall(function()
				return track:GetTimeOfKeyframe(IMPACT_KEYFRAME)
			end)
			if ok and impactAt > 0 then
				speed = impactAt / windup
				task.delay(math.max(windup - elapsed, 0), function()
					if controller.action == layer and track.IsPlaying then
						track:AdjustSpeed(1)
					end
				end)
			end
		end

		track:Play(CROSSFADE, 1, speed)
		layer.track = track
	else
		beginFade(controller)
	end

	controller.action = layer
end

function RigAnimation.stopAction(controller: Controller)
	local action = controller.action
	if not action then
		return
	end

	if action.track then
		action.track:Stop(CROSSFADE)
	end

	controller.action = nil
	beginFade(controller)
end

function RigAnimation.currentAction(controller: Controller): string?
	local action = controller.action
	return action and action.name
end

local function toCFrame(values: KeyframeMath.PoseValues): CFrame
	return CFrame.new(values.px, values.py, values.pz)
		* CFrame.Angles(math.rad(values.rx), math.rad(values.ry), math.rad(values.rz))
end

-- Advance one frame and pose the rig. Call from PreSimulation.
function RigAnimation.step(controller: Controller, deltaTime: number)
	local now = clock()
	local action = controller.action

	-- A published action is the Animator's to play; stay off its joints.
	if action and action.track then
		local track = action.track
		if action.hold then
			-- A finished track lets go of the rig, and it would stand back up.
			-- Freeze just short of the end instead.
			if track.IsPlaying and track.Length > 0 and track.TimePosition >= track.Length - 0.05 then
				track:AdjustSpeed(0)
			end
		elseif not track.IsPlaying then
			controller.action = nil
		end
		return
	end

	local pose: PoseMap = {}
	local overlayWeight = 1
	local overlay = overlaysAnimator(controller)

	local base = controller.base
	if base and not base.track and not controller.external then
		base.phase += deltaTime * controller.baseSpeed
		pose = KeyframeMath.sample(base.anim, base.phase)
	end

	if action then
		local t = actionTime(action, now)
		local actionPose = KeyframeMath.sample(action.anim, t)

		-- The action takes over the parts it animates; the base keeps the rest.
		for part, values in actionPose do
			pose[part] = values
		end

		local finished = not action.anim.looped and t >= action.anim.length
		if overlay then
			local sinceStart = now - action.startedAt
			local untilEnd = (action.anim.length - t) / math.max(action.timeScale, 1e-3)
			overlayWeight = math.min(sinceStart / OVERLAY_FADE_IN, 1)
			if not action.hold then
				overlayWeight = math.min(overlayWeight, math.max(untilEnd / OVERLAY_FADE_OUT, 0))
			end
		end

		if finished and not action.hold then
			controller.action = nil
			beginFade(controller)
		end
	end

	local fadeFrom = controller.fadeFrom
	if fadeFrom then
		local progress = (now - controller.fadeStart) / CROSSFADE
		if progress >= 1 then
			controller.fadeFrom = nil
		else
			pose = KeyframeMath.blend(fadeFrom, pose, progress)
		end
	end

	controller.lastPose = pose

	for part, values in pose do
		local joint = controller.joints[part]
		if joint then
			local target = toCFrame(values)
			if overlay then
				joint.Transform = joint.Transform:Lerp(target, overlayWeight)
			else
				joint.Transform = target
				controller.written[part] = true
			end
		end
	end

	-- A part this rig stopped animating goes back to rest rather than
	-- freezing wherever it was last left. Overlays leave that to the Animator.
	if not overlay then
		for part in controller.written do
			if not pose[part] then
				local joint = controller.joints[part]
				if joint then
					joint.Transform = CFrame.identity
				end
				controller.written[part] = nil
			end
		end
	end
end

function RigAnimation.destroy(controller: Controller)
	for _, track in controller.tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(controller.tracks)
	controller.action = nil
	controller.base = nil
end

return RigAnimation
