--!strict
-- Visual read on every enemy's windup: a glow over the rig that builds toward
-- impact, the stagger and death tints, and a ground danger zone for attacks
-- that hit all around.
--
-- This is the signal the player actually reacts to, so it has to track the
-- server's timeline exactly: the glow runs toward impactTime, which the server
-- sends as an absolute timestamp rather than a duration so a delayed packet
-- doesn't shift the cue.
--
-- The glow is a Highlight over the whole rig, so each rig keeps its own
-- colours at rest and only lights up when something is happening. State is
-- per enemy: a second enemy winding up must never cancel the first one's cue.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EnemyDefs = require(Shared.EnemyDefs)
local Remotes = require(Shared.Remotes)

local TelegraphVFX = {}

-- Parryable attacks build toward white so the parry beat is readable;
-- unparryable ones glow deep orange, so "this one you move out of" is legible
-- without a tooltip.
local PARRYABLE_PEAK = Color3.fromRGB(255, 255, 255)
local UNPARRYABLE_PEAK = Color3.fromRGB(255, 120, 0)
local STAGGER_COLOR = Color3.fromRGB(80, 120, 255)
local DEAD_COLOR = Color3.fromRGB(40, 40, 40)

local STAGGER_STRENGTH = 0.6
local DEAD_STRENGTH = 0.85

-- Server-side EnemyAI tags every enemy model with this.
local ENEMY_TAG = "Enemy"

-- Held at full glow briefly past impact so the hit reads, as a fraction of
-- the telegraph's length.
local HOLD_AFTER_IMPACT = 0.5

-- Danger zones: a flat disc covering the attack's real hit volume.
local ZONE_THICKNESS = 0.15
local ZONE_START_TRANSPARENCY = 0.85
local ZONE_END_TRANSPARENCY = 0.35
local ZONE_IMPACT_TRANSPARENCY = 0.15

type Telegraph = {
	model: Model,
	root: BasePart,
	startTime: number,
	impactTime: number,
	parryable: boolean,
	zone: Part?,
}

local telegraphs: { [string]: Telegraph } = {}

-- enemyId -> client clock time the stagger tint should clear.
local staggeredUntil: { [string]: number } = {}
local dead: { [string]: boolean } = {}
local glows: { [string]: Highlight } = {}

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

-- One glow per enemy, made on first use and parented to the rig so it goes
-- when the rig does.
local function glowFor(enemyId: string, model: Model): Highlight
	local existing = glows[enemyId]
	if existing and existing.Parent == model then
		return existing
	end

	local glow = Instance.new("Highlight")
	glow.Name = "TelegraphGlow"
	glow.Adornee = model
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Enabled = false
	glow.Parent = model

	glows[enemyId] = glow
	return glow
end

-- `strength` 0 turns the glow off; 1 is the strongest tint.
local function setGlow(enemyId: string, model: Model, color: Color3, strength: number)
	local glow = glowFor(enemyId, model)
	if strength <= 0 then
		glow.Enabled = false
		return
	end

	glow.Enabled = true
	glow.FillColor = color
	glow.OutlineColor = color
	glow.FillTransparency = 1 - strength * 0.7
	glow.OutlineTransparency = 1 - strength
end

-- What an enemy looks like with no windup running.
local function settle(enemyId: string, model: Model)
	if dead[enemyId] then
		setGlow(enemyId, model, DEAD_COLOR, DEAD_STRENGTH)
		return
	end

	local until_ = staggeredUntil[enemyId]
	if until_ and os.clock() < until_ then
		setGlow(enemyId, model, STAGGER_COLOR, STAGGER_STRENGTH)
		return
	end

	setGlow(enemyId, model, STAGGER_COLOR, 0)
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
	settle(enemyId, telegraph.model)
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

		local zone: Part? = nil
		local defId = model:GetAttribute("EnemyDefId")
		local def = if typeof(defId) == "string" then EnemyDefs[defId] else nil
		local attack = def and def.attacks[payload.attackId]
		if attack and attack.arcDegrees >= 360 then
			zone = makeDangerZone(root, attack.range, if payload.parryable then PARRYABLE_PEAK else UNPARRYABLE_PEAK)
		end

		telegraphs[payload.enemyId] = {
			model = model,
			root = root,
			startTime = payload.impactTime - payload.duration,
			impactTime = payload.impactTime,
			parryable = payload.parryable,
			zone = zone,
		}
	end)

	Remotes.get("EnemyStaggered").OnClientEvent:Connect(function(payload)
		-- Tracked rather than just painted, so a punish hit landing during the
		-- stagger doesn't clear the "punish now" tint.
		staggeredUntil[payload.enemyId] = os.clock() + payload.duration

		local model = findEnemyModel(payload.enemyId)
		if telegraphs[payload.enemyId] then
			endTelegraph(payload.enemyId)
		elseif model then
			settle(payload.enemyId, model)
		end
	end)

	Remotes.get("EnemyHealthChanged").OnClientEvent:Connect(function(payload)
		dead[payload.enemyId] = not payload.alive or nil

		local model = findEnemyModel(payload.enemyId)
		if not payload.alive then
			staggeredUntil[payload.enemyId] = nil
			endTelegraph(payload.enemyId)
		end

		if model and not telegraphs[payload.enemyId] then
			settle(payload.enemyId, model)
		end
	end)

	-- One loop for every enemy, rather than a connection each.
	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()

		for enemyId, telegraph in telegraphs do
			local duration = telegraph.impactTime - telegraph.startTime
			if duration <= 0 or not telegraph.model.Parent then
				endTelegraph(enemyId)
				continue
			end

			local progress = (now - telegraph.startTime) / duration
			local peak = if telegraph.parryable then PARRYABLE_PEAK else UNPARRYABLE_PEAK
			local zone = telegraph.zone

			if progress > 1 + HOLD_AFTER_IMPACT then
				endTelegraph(enemyId)
			elseif progress >= 1 then
				setGlow(enemyId, telegraph.model, peak, 1)
				if zone then
					zone.Transparency = ZONE_IMPACT_TRANSPARENCY
				end
			else
				local t = math.clamp(progress, 0, 1)
				setGlow(enemyId, telegraph.model, peak, t)
				if zone then
					zone.Transparency = ZONE_START_TRANSPARENCY + (ZONE_END_TRANSPARENCY - ZONE_START_TRANSPARENCY) * t
				end
			end
		end

		-- Clear stagger tints whose time is up.
		local clock = os.clock()
		for enemyId, until_ in staggeredUntil do
			if clock >= until_ then
				staggeredUntil[enemyId] = nil
				if not telegraphs[enemyId] then
					local model = findEnemyModel(enemyId)
					if model then
						settle(enemyId, model)
					end
				end
			end
		end
	end)
end

return TelegraphVFX
