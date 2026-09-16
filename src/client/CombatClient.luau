--!strict
-- Input capture only. The client stamps when the player pressed parry and
-- sends it, asks to swing, and asks to equip — it decides none of the outcomes.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Loadout = require(Shared.Loadout)
local Remotes = require(Shared.Remotes)

local CombatClient = {}

local PARRY_ACTION = "Parry"
local ATTACK_ACTION = "Attack"

-- Number-key weapon switching is a tuning affordance, not the real equip flow.
-- Build-order step 6 replaces it with inventory-driven equipping; until then
-- being able to swap class instantly is the fastest way to compare parry
-- windows back to back.
local SWAP_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
}

function CombatClient.start()
	local parryAttempt = Remotes.get("ParryAttempt")
	local attackRequest = Remotes.get("AttackRequest")
	local equipWeapon = Remotes.get("EquipWeapon")

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

	ContextActionService:BindAction(ATTACK_ACTION, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end

		-- No timestamp: a swing is not reactive, so the server has no reason to
		-- trust client timing for it and simply resolves on its own clock.
		attackRequest:FireServer()

		return Enum.ContextActionResult.Sink
	end, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	ContextActionService:SetTitle(ATTACK_ACTION, "Attack")

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

return CombatClient
