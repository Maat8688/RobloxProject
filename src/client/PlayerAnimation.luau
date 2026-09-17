--!strict
-- Combat animations on players' avatars: a swing per weapon and the parry,
-- layered over Roblox's own walk, run and idle, which keep playing underneath.
--
-- Other players are animated from the server's PlayerCombatAction broadcast.
-- The local player is animated the moment they press, without waiting a round
-- trip, gated by the rules the client can check for itself (equipped weapon,
-- swing cooldown). A swing the server then refuses for lack of stamina will
-- still have animated — an accepted cost of responsive input.
--
-- The animations are authored for R15 joints; an R6 avatar simply isn't
-- animated here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local AnimationDefs = require(Shared.AnimationDefs)
local Loadout = require(Shared.Loadout)
local Remotes = require(Shared.Remotes)
local RigDefs = require(Shared.RigDefs)

local RigAnimation = require(script.Parent.RigAnimation)

local PlayerAnimation = {}

local R15_JOINTS = 15
local RIG_WAIT_LIMIT = 10

type Tracked = {
	controller: RigAnimation.Controller,
	character: Model,
}

local localPlayer = Players.LocalPlayer
local tracked: { [Player]: Tracked } = {}

local equippedWeapon: string? = nil
local dueling = false
local nextSwingAt = 0

local function countJoints(model: Model): number
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part1 then
			count += 1
		end
	end
	return count
end

local function onCharacterAdded(player: Player, character: Model)
	local previous = tracked[player]
	if previous then
		RigAnimation.destroy(previous.controller)
		tracked[player] = nil
	end

	local humanoid = character:WaitForChild("Humanoid", RIG_WAIT_LIMIT) :: Humanoid?
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end

	local waited = 0
	while countJoints(character) < R15_JOINTS and character.Parent and waited < RIG_WAIT_LIMIT do
		waited += task.wait(0.2)
	end

	-- Still the current character?
	if player.Character ~= character or not character.Parent then
		return
	end

	tracked[player] = {
		controller = RigAnimation.new(character, RigDefs.PLAYER_RIG, true),
		character = character,
	}
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	local character = player.Character
	if character then
		task.spawn(onCharacterAdded, player, character)
	end
end

local function play(player: Player, action: string, weaponId: string, windup: number?)
	local entry = tracked[player]
	if not entry or entry.character ~= player.Character then
		return
	end

	if action == "swing" then
		RigAnimation.playAction(entry.controller, AnimationDefs.swing(weaponId), { windup = windup })
	elseif action == "parry" then
		RigAnimation.playAction(entry.controller, AnimationDefs.PARRY)
	end
end

-- Called by CombatClient on the attack input.
function PlayerAnimation.predictSwing()
	local weaponId = equippedWeapon
	if not weaponId then
		return
	end

	local now = os.clock()
	if now < nextSwingAt then
		return
	end

	local attack = Loadout.getDef(weaponId).attack
	local windup = if dueling then attack.pvpTelegraph else attack.windup
	nextSwingAt = now + windup + attack.cooldown

	play(localPlayer, "swing", weaponId, windup)
end

-- Called by CombatClient on the parry input.
function PlayerAnimation.predictParry()
	local weaponId = equippedWeapon
	local entry = tracked[localPlayer]
	if not weaponId or not entry then
		return
	end

	-- Mashing doesn't restart the guard; the server's lockout is what actually
	-- punishes it.
	if RigAnimation.currentAction(entry.controller) == AnimationDefs.PARRY then
		return
	end

	play(localPlayer, "parry", weaponId)
end

function PlayerAnimation.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local entry = tracked[player]
		if entry then
			RigAnimation.destroy(entry.controller)
			tracked[player] = nil
		end
	end)

	Remotes.get("WeaponEquipped").OnClientEvent:Connect(function(payload)
		equippedWeapon = payload.weaponId
	end)

	Remotes.get("PvPStatusChanged").OnClientEvent:Connect(function(payload)
		dueling = payload.status == "dueling"
	end)

	Remotes.get("PlayerCombatAction").OnClientEvent:Connect(function(payload)
		-- The local player's own actions were already animated on input.
		if payload.userId == localPlayer.UserId then
			return
		end

		local player = Players:GetPlayerByUserId(payload.userId)
		if player then
			play(player, payload.action, payload.weaponId, payload.windup)
		end
	end)

	-- After Roblox's Animate script has posed each avatar for this frame.
	RunService.PreSimulation:Connect(function(deltaTime)
		for _, entry in tracked do
			RigAnimation.step(entry.controller, deltaTime)
		end
	end)
end

return PlayerAnimation
