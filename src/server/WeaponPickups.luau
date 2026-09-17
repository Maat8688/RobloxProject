-- Three physical weapon stands near spawn — not a menu. Interacting with one
-- equips that weapon (and can freely re-equip a different one later; no
-- lock/cost yet, see DESIGN.md). No visible weapon-in-hand model yet — pure
-- data/interaction, visuals are step 10 polish.

local Workspace = game:GetService("Workspace")

local EquipService = require(script.Parent.EquipService)

local PICKUPS = {
	{ weaponId = "Tank", displayName = "Sword & Shield", color = BrickColor.new("Dark stone grey"), offset = Vector3.new(-6, 2, 5) },
	{ weaponId = "Assassin", displayName = "Daggers", color = BrickColor.new("Really black"), offset = Vector3.new(0, 2, 5) },
	{ weaponId = "Healer", displayName = "Staff", color = BrickColor.new("New White"), offset = Vector3.new(6, 2, 5) },
}

local WeaponPickups = {}

function WeaponPickups.Start(originCFrame)
	for _, pickup in PICKUPS do
		local stand = Instance.new("Part")
		stand.Name = pickup.weaponId .. "Pickup"
		stand.Size = Vector3.new(2, 4, 2)
		stand.Anchored = true
		stand.CanCollide = true
		stand.BrickColor = pickup.color
		stand.CFrame = originCFrame * CFrame.new(pickup.offset)
		stand.Parent = Workspace

		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = pickup.displayName
		prompt.ActionText = "Equip"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.Parent = stand

		prompt.Triggered:Connect(function(player)
			EquipService.SetWeapon(player, pickup.weaponId)
		end)
	end
end

return WeaponPickups
