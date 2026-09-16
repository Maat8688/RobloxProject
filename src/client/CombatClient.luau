--!strict
-- Input capture only. The client stamps when the player pressed parry and
-- sends it; it decides nothing about the outcome.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CombatClient = {}

local PARRY_ACTION = "Parry"

function CombatClient.start()
	local parryAttempt = Remotes.get("ParryAttempt")

	ContextActionService:BindAction(PARRY_ACTION, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end

		-- GetServerTimeNow is already synchronised to the server clock, so no
		-- handshake is needed and the server can compare this directly against
		-- its own clock.
		parryAttempt:FireServer({ timestamp = Workspace:GetServerTimeNow() })

		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonL1)

	ContextActionService:SetTitle(PARRY_ACTION, "Parry")
end

return CombatClient
