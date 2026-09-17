--!strict
-- Small lookups on a player's character, shared by every server module that
-- resolves combat against real positions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageMath = require(ReplicatedStorage.Shared.DamageMath)

local Characters = {}

function Characters.getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Characters.getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

function Characters.isAlive(player: Player): boolean
	local humanoid = Characters.getHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

-- The XZ projection the pure combat math works in.
function Characters.flat(position: Vector3): DamageMath.Vec2
	return { x = position.X, z = position.Z }
end

-- GetNetworkPing is the round trip; parry authority needs the one-way half.
function Characters.halfPing(player: Player): number
	return player:GetNetworkPing() / 2
end

return Characters
