--!strict
-- Combat input capture. The client stamps when the player pressed parry and
-- sends it, and asks to swing — it decides none of the outcomes. The same
-- inputs drive PvE and duels; the server routes them.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Loadout = require(Shared.Loadout)
local Remotes = require(Shared.Remotes)

local PlayerAnimation = require(script.Parent.PlayerAnimation)

local CombatClient = {}

local PARRY_ACTION = "Parry"
local ATTACK_ACTION = "Attack"

-- Number-key weapon swapping, for comparing parry windows back to back while
-- tuning. Studio only, on both ends: in a live game the weapon stands are the
-- way to equip, and the server ignores this remote outside Studio anyway.
local SWAP_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
}

local function bindDebugSwaps()
	local equipWeapon = Remotes.get("EquipWeapon")
	local weaponIds = Loadout.allWeaponIds()

	for index, keyCode in SWAP_KEYS do
		local weaponId = weaponIds[index]
		if not weaponId then
			break
		end

		ContextActionService:BindAction(`Equip_{weaponId}`, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				equipWeapon:FireServer({ weaponId = weaponId })
			end
			return Enum.ContextActionResult.Sink
		end, false, keyCode)
	end
end

function CombatClient.start()
	local parryAttempt = Remotes.get("ParryAttempt")
	local attackRequest = Remotes.get("AttackRequest")

	ContextActionService:BindAction(PARRY_ACTION, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end

		-- GetServerTimeNow is already synchronised to the server clock, so the
		-- server can compare this directly against its own clock — and against
		-- its own estimate of when this could have been sent.
		parryAttempt:FireServer({ timestamp = Workspace:GetServerTimeNow() })
		-- Animated now rather than after a round trip; see PlayerAnimation.
		PlayerAnimation.predictParry()

		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonL1)

	ContextActionService:SetTitle(PARRY_ACTION, "Parry")

	ContextActionService:BindAction(ATTACK_ACTION, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end

		-- No timestamp: a swing is not reactive, so the server has no reason to
		-- trust client timing for it and simply resolves on its own clock.
		attackRequest:FireServer()
		PlayerAnimation.predictSwing()

		return Enum.ContextActionResult.Sink
	end, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	ContextActionService:SetTitle(ATTACK_ACTION, "Attack")

	if RunService:IsStudio() then
		bindDebugSwaps()
	end
end

return CombatClient
