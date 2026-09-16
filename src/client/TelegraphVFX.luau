--!strict
-- Visual read on the enemy's windup. This is the signal the player actually
-- reacts to, so it has to track the server's timeline exactly: the highlight
-- ramps toward impactTime, which the server sends as an absolute timestamp
-- rather than a duration so a delayed packet doesn't shift the cue.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TelegraphVFX = {}

-- Parryable attacks ramp toward white so the parry beat is readable; the
-- unparryable one goes deep orange and never flashes, so "this one you move
-- out of" is legible without reading a tooltip.
local PARRYABLE_START = Color3.fromRGB(150, 60, 60)
local PARRYABLE_PEAK = Color3.fromRGB(255, 255, 255)
local UNPARRYABLE_START = Color3.fromRGB(150, 60, 60)
local UNPARRYABLE_PEAK = Color3.fromRGB(255, 120, 0)
local STAGGER_COLOR = Color3.fromRGB(80, 120, 255)

local activeConnection: RBXScriptConnection? = nil

local function findEnemy(enemyId: string): BasePart?
	for _, model in Workspace:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("EnemyId") == enemyId then
			return model.PrimaryPart
		end
	end

	return nil
end

local function stopActive()
	if activeConnection then
		activeConnection:Disconnect()
		activeConnection = nil
	end
end

function TelegraphVFX.start()
	Remotes.get("EnemyTelegraphStart").OnClientEvent:Connect(function(payload)
		local root = findEnemy(payload.enemyId)
		if not root then
			return
		end

		stopActive()

		local startTime = payload.impactTime - payload.duration
		local fromColor = if payload.parryable then PARRYABLE_START else UNPARRYABLE_START
		local toColor = if payload.parryable then PARRYABLE_PEAK else UNPARRYABLE_PEAK

		activeConnection = RunService.RenderStepped:Connect(function()
			local progress = (Workspace:GetServerTimeNow() - startTime) / payload.duration
			if progress >= 1 then
				root.Color = toColor
				stopActive()
				return
			end

			root.Color = fromColor:Lerp(toColor, math.clamp(progress, 0, 1))
		end)
	end)

	Remotes.get("EnemyStaggered").OnClientEvent:Connect(function(payload)
		local root = findEnemy(payload.enemyId)
		if not root then
			return
		end

		stopActive()
		root.Color = STAGGER_COLOR

		task.delay(payload.duration, function()
			if not activeConnection then
				root.Color = PARRYABLE_START
			end
		end)
	end)
end

return TelegraphVFX
