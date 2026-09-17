--!strict
-- Visual read on every enemy's windup: the rig's colour ramp, the stagger
-- colour, and a ground danger zone for attacks that hit all around.
--
-- This is the signal the player actually reacts to, so it has to track the
-- server's timeline exactly: the ramp runs toward impactTime, which the server
-- sends as an absolute timestamp rather than a duration so a delayed packet
-- doesn't shift the cue.
--
-- State is per-enemy. A single shared connection would mean the second enemy
-- to wind up cancels the first one's cue, which is exactly the situation the
-- player most needs to read.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EnemyDefs = require(Shared.EnemyDefs)
local Remotes = require(Shared.Remotes)

local TelegraphVFX = {}

-- Parryable attacks ramp toward white so the parry beat is readable; the
-- unparryable ones go deep orange and never flash, so "this one you move out
-- of" is legible without reading a tooltip.
local PARRYABLE_PEAK = Color3.fromRGB(255, 255, 255)
local UNPARRYABLE_PEAK = Color3.fromRGB(255, 120, 0)
local STAGGER_COLOR = Color3.fromRGB(80, 120, 255)
local DEAD_COLOR = Color3.fromRGB(60, 60, 60)

-- Matches EnemyAI's per-type colours so a telegraph fades back to the right
-- base rather than to a single shared red.
local BASE_COLORS: { [string]: Color3 } = {
	TrainingDummy = Color3.fromRGB(150, 60, 60),
	SkeletonWarrior = Color3.fromRGB(200, 195, 170),
	Shambler = Color3.fromRGB(120, 90, 50),
	Spitter = Color3.fromRGB(80, 130, 70),
}

local DEFAULT_BASE = Color3.fromRGB(150, 60, 60)

-- Server-side EnemyAI tags every enemy model with this.
local ENEMY_TAG = "Enemy"

-- Held at peak briefly past impact so the hit reads, as a fraction of the
-- telegraph's length.
local HOLD_AFTER_IMPACT = 0.5

-- Danger zones: a flat disc covering the attack's real hit volume.
local ZONE_THICKNESS = 0.15
local ZONE_START_TRANSPARENCY = 0.85
local ZONE_END_TRANSPARENCY = 0.35
local ZONE_IMPACT_TRANSPARENCY = 0.15

type Telegraph = {
	root: BasePart,
	startTime: number,
	impactTime: number,
	parryable: boolean,
	baseColor: Color3,
	zone: Part?,
}

local telegraphs: { [string]: Telegraph } = {}

-- enemyId -> client clock time the stagger colour should clear.
local staggeredUntil: { [string]: number } = {}

-- By tag rather than by scanning Workspace: dungeon enemies live inside a
-- folder, not at the top level.
local function findEnemyModel(enemyId: string): Model?
	for _, tagged in CollectionService:GetTagged(ENEMY_TAG) do
		if tagged:IsA("Model") and tagged:GetAttribute("EnemyId") == enemyId then
			return tagged
		end
	end

	return nil
end

local function defIdOf(model: Model): string?
	local defId = model:GetAttribute("EnemyDefId")
	return if typeof(defId) == "string" then defId else nil
end

local function baseColorFor(model: Model): Color3
	local defId = defIdOf(model)
	return if defId then BASE_COLORS[defId] or DEFAULT_BASE else DEFAULT_BASE
end

-- The colour a rig should rest at when nothing is winding up.
local function restingColor(enemyId: string, model: Model): Color3
	local until_ = staggeredUntil[enemyId]
	if until_ and os.clock() < until_ then
		return STAGGER_COLOR
	end

	return baseColorFor(model)
end

-- A disc on the floor under the enemy, sized to the attack's hit volume.
--
-- Only for attacks that hit all around. Their hit radius can be larger than
-- the range they're used from (the SkeletonWarrior slams from 10 but reaches
-- 14), so without the disc there is no way to know how far to back off.
-- Directional attacks read from the enemy's facing instead; a full disc would
-- lie about them.
--
-- Created on this client only, so each player sees their own and nothing
-- replicates.
local function makeDangerZone(root: BasePart, radius: number, color: Color3): Part
	local zone = Instance.new("Part")
	zone.Name = "DangerZone"
	zone.Shape = Enum.PartType.Cylinder
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.CastShadow = false
	zone.Material = Enum.Material.Neon
	zone.Color = color
	zone.Transparency = ZONE_START_TRANSPARENCY
	zone.Size = Vector3.new(ZONE_THICKNESS, radius * 2, radius * 2)

	local floorY = root.Position.Y - root.Size.Y / 2
	-- A cylinder's axis runs along its X, so rolling it 90 degrees lays it flat.
	zone.CFrame = CFrame.new(root.Position.X, floorY + ZONE_THICKNESS / 2 + 0.02, root.Position.Z)
		* CFrame.Angles(0, 0, math.rad(90))

	zone.Parent = Workspace
	return zone
end

local function endTelegraph(enemyId: string)
	local telegraph = telegraphs[enemyId]
	if not telegraph then
		return
	end

	telegraphs[enemyId] = nil
	if telegraph.zone then
		telegraph.zone:Destroy()
	end
end

function TelegraphVFX.start()
	Remotes.get("EnemyTelegraphStart").OnClientEvent:Connect(function(payload)
		local model = findEnemyModel(payload.enemyId)
		local root = model and model.PrimaryPart
		if not model or not root then
			return
		end

		endTelegraph(payload.enemyId)
		staggeredUntil[payload.enemyId] = nil

		local peak = if payload.parryable then PARRYABLE_PEAK else UNPARRYABLE_PEAK

		local zone: Part? = nil
		local defId = defIdOf(model)
		local def = if defId then EnemyDefs[defId] else nil
		local attack = def and def.attacks[payload.attackId]
		if attack and attack.arcDegrees >= 360 then
			zone = makeDangerZone(root, attack.range, peak)
		end

		telegraphs[payload.enemyId] = {
			root = root,
			startTime = payload.impactTime - payload.duration,
			impactTime = payload.impactTime,
			parryable = payload.parryable,
			baseColor = baseColorFor(model),
			zone = zone,
		}
	end)

	Remotes.get("EnemyStaggered").OnClientEvent:Connect(function(payload)
		local telegraph = telegraphs[payload.enemyId]
		endTelegraph(payload.enemyId)

		local root = telegraph and telegraph.root
		if not root then
			local model = findEnemyModel(payload.enemyId)
			root = model and model.PrimaryPart
		end

		if not root then
			return
		end

		-- Tracked rather than just painted, so a punish hit landing during the
		-- stagger doesn't wipe the "punish now" colour.
		staggeredUntil[payload.enemyId] = os.clock() + payload.duration
		root.Color = STAGGER_COLOR
	end)

	Remotes.get("EnemyHealthChanged").OnClientEvent:Connect(function(payload)
		local model = findEnemyModel(payload.enemyId)
		local root = model and model.PrimaryPart
		if not model or not root then
			return
		end

		if not payload.alive then
			endTelegraph(payload.enemyId)
			staggeredUntil[payload.enemyId] = nil
			root.Color = DEAD_COLOR
		elseif not telegraphs[payload.enemyId] then
			root.Color = restingColor(payload.enemyId, model)
		end
	end)

	-- One loop for every enemy, rather than a connection each.
	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()

		for enemyId, telegraph in telegraphs do
			local duration = telegraph.impactTime - telegraph.startTime
			if duration <= 0 or not telegraph.root.Parent then
				endTelegraph(enemyId)
				continue
			end

			local progress = (now - telegraph.startTime) / duration
			local peak = if telegraph.parryable then PARRYABLE_PEAK else UNPARRYABLE_PEAK
			local zone = telegraph.zone

			if progress > 1 + HOLD_AFTER_IMPACT then
				telegraph.root.Color = telegraph.baseColor
				endTelegraph(enemyId)
			elseif progress >= 1 then
				telegraph.root.Color = peak
				if zone then
					zone.Transparency = ZONE_IMPACT_TRANSPARENCY
				end
			else
				local t = math.clamp(progress, 0, 1)
				telegraph.root.Color = telegraph.baseColor:Lerp(peak, t)
				if zone then
					zone.Transparency = ZONE_START_TRANSPARENCY + (ZONE_END_TRANSPARENCY - ZONE_START_TRANSPARENCY) * t
				end
			end
		end

		-- Clear stagger colours whose time is up.
		local clock = os.clock()
		for enemyId, until_ in staggeredUntil do
			if clock >= until_ then
				staggeredUntil[enemyId] = nil
				if not telegraphs[enemyId] then
					local model = findEnemyModel(enemyId)
					local root = model and model.PrimaryPart
					if model and root then
						root.Color = baseColorFor(model)
					end
				end
			end
		end
	end)
end

return TelegraphVFX
