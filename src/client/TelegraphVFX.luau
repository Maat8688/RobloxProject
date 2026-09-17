--!strict
-- Visual read on every enemy's windup.
--
-- This is the signal the player actually reacts to, so it has to track the
-- server's timeline exactly: the highlight ramps toward impactTime, which the
-- server sends as an absolute timestamp rather than a duration so a delayed
-- packet doesn't shift the cue.
--
-- State is per-enemy. A single shared connection would mean the second enemy
-- to wind up cancels the first one's cue, which is exactly the situation the
-- player most needs to read.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

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

-- Server-side EnemyAI tags every enemy model with this.
local ENEMY_TAG = "Enemy"

local DEFAULT_BASE = Color3.fromRGB(150, 60, 60)

type Telegraph = {
	root: BasePart,
	startTime: number,
	impactTime: number,
	parryable: boolean,
	baseColor: Color3,
}

local telegraphs: { [string]: Telegraph } = {}

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

local function baseColorFor(model: Model): Color3
	local defId = model:GetAttribute("EnemyDefId")
	if typeof(defId) == "string" then
		return BASE_COLORS[defId] or DEFAULT_BASE
	end

	return DEFAULT_BASE
end

function TelegraphVFX.start()
	Remotes.get("EnemyTelegraphStart").OnClientEvent:Connect(function(payload)
		local model = findEnemyModel(payload.enemyId)
		local root = model and model.PrimaryPart
		if not model or not root then
			return
		end

		telegraphs[payload.enemyId] = {
			root = root,
			startTime = payload.impactTime - payload.duration,
			impactTime = payload.impactTime,
			parryable = payload.parryable,
			baseColor = baseColorFor(model),
		}
	end)

	Remotes.get("EnemyStaggered").OnClientEvent:Connect(function(payload)
		local telegraph = telegraphs[payload.enemyId]
		telegraphs[payload.enemyId] = nil

		local root = telegraph and telegraph.root
		if not root then
			local model = findEnemyModel(payload.enemyId)
			root = model and model.PrimaryPart
		end

		if not root then
			return
		end

		root.Color = STAGGER_COLOR

		local staggeredRoot = root
		local baseColor = if telegraph then telegraph.baseColor else DEFAULT_BASE
		task.delay(payload.duration, function()
			-- Don't stomp a new windup that started during the stagger.
			if not telegraphs[payload.enemyId] then
				staggeredRoot.Color = baseColor
			end
		end)
	end)

	Remotes.get("EnemyHealthChanged").OnClientEvent:Connect(function(payload)
		local model = findEnemyModel(payload.enemyId)
		local root = model and model.PrimaryPart
		if not model or not root then
			return
		end

		if not payload.alive then
			telegraphs[payload.enemyId] = nil
			root.Color = DEAD_COLOR
		elseif not telegraphs[payload.enemyId] then
			root.Color = baseColorFor(model)
		end
	end)

	-- One loop for every enemy, rather than a connection each.
	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()

		for enemyId, telegraph in telegraphs do
			local duration = telegraph.impactTime - telegraph.startTime
			if duration <= 0 then
				telegraphs[enemyId] = nil
				continue
			end

			local progress = (now - telegraph.startTime) / duration
			local peak = if telegraph.parryable then PARRYABLE_PEAK else UNPARRYABLE_PEAK

			if progress >= 1 then
				telegraph.root.Color = peak
				-- Held at peak briefly past impact so the hit reads, then the
				-- stagger/health handlers or the next windup take over.
				if progress > 1.5 then
					telegraph.root.Color = telegraph.baseColor
					telegraphs[enemyId] = nil
				end
				continue
			end

			telegraph.root.Color = telegraph.baseColor:Lerp(peak, math.clamp(progress, 0, 1))
		end
	end)
end

return TelegraphVFX
