--!strict
-- Three physical weapon stands in the start room — not a menu. Interacting
-- with one equips that weapon, and a different one can be picked up freely
-- later: the real cost of respeccing comes from class-specific crystals, not a
-- lock (DESIGN.md).
--
-- ProximityPrompt.Triggered fires on the server with the player already
-- attached, so equipping needs no RemoteEvent and adds no client-callable
-- path. No weapon-in-hand model yet; visuals are step 10.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Loadout = require(ReplicatedStorage.Shared.Loadout)

local EquipService = require(script.Parent.EquipService)

local WeaponPickups = {}

local STANDS = {
	{ weaponId = "SwordAndShield", color = Color3.fromRGB(99, 95, 98), offset = Vector3.new(-6, 2, 5) },
	{ weaponId = "Daggers", color = Color3.fromRGB(27, 42, 53), offset = Vector3.new(0, 2, 5) },
	{ weaponId = "Staff", color = Color3.fromRGB(242, 243, 243), offset = Vector3.new(6, 2, 5) },
}

function WeaponPickups.start(originCFrame: CFrame)
	for _, stand in STANDS do
		local def = Loadout.getDef(stand.weaponId)

		local part = Instance.new("Part")
		part.Name = `{stand.weaponId}Pickup`
		part.Size = Vector3.new(2, 4, 2)
		part.Anchored = true
		part.CanCollide = true
		part.Color = stand.color
		part.CFrame = originCFrame * CFrame.new(stand.offset)
		part.Parent = Workspace

		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = `{def.displayName} ({def.classTag})`
		prompt.ActionText = "Equip"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.Parent = part

		local weaponId = stand.weaponId
		prompt.Triggered:Connect(function(player)
			EquipService.setWeapon(player, weaponId)
		end)
	end
end

return WeaponPickups
