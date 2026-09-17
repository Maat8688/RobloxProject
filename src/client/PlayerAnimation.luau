--!strict
-- Combat animations on players' avatars: each weapon's fighting stance under
-- walking and idling, its combo swings and critical, the guard held while
-- blocking, feints, the dodge, flinches and guard breaks.
--
-- Every player's stance comes from the weapon their character carries (an
-- attribute set by the server's WeaponVisuals). Other players' actions come
-- from the server's PlayerCombatAction broadcast. The local player's own are
-- played the instant they press, by CombatClient, without waiting a round
-- trip.
--
-- The animations are authored for R15 joints; an R6 avatar simply isn't
-- animated here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local AnimationDefs = require(Shared.AnimationDefs)
local Remotes = require(Shared.Remotes)
local RigDefs = require(Shared.RigDefs)
local SoundDefs = require(Shared.SoundDefs)
local WeaponModelDefs = require(Shared.WeaponModelDefs)

local RigAnimation = require(script.Parent.RigAnimation)
local SoundFX = require(script.Parent.SoundFX)

local PlayerAnimation = {}

local R15_JOINTS = 15
local RIG_WAIT_LIMIT = 10

-- The whoosh sounds as the blade comes through, this far into the windup.
local WHOOSH_AT = 0.6

type Tracked = {
	controller: RigAnimation.Controller,
	character: Model,
}

local localPlayer = Players.LocalPlayer
local tracked: { [Player]: Tracked } = {}

-- Players whose guard is up, so it can resume once a swing or flinch ends.
local guardingPlayers: { [Player]: string } = {}

-- Motor6Ds or AnimationConstraints, whichever this avatar was built with.
local countJoints = RigAnimation.countJoints

local function rootOf(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The stance follows whatever weapon the character is carrying.
local function refreshStance(entry: Tracked)
	local weaponId = entry.character:GetAttribute(WeaponModelDefs.WEAPON_ATTRIBUTE)
	if typeof(weaponId) == "string" then
		RigAnimation.setBase(entry.controller, AnimationDefs.stance(weaponId))
	elseif RigAnimation.currentBase(entry.controller) then
		RigAnimation.clearBase(entry.controller)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local previous = tracked[player]
	if previous then
		RigAnimation.destroy(previous.controller)
		tracked[player] = nil
	end
	guardingPlayers[player] = nil

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

	local entry: Tracked = {
		controller = RigAnimation.new(character, RigDefs.PLAYER_RIG, true),
		character = character,
	}
	tracked[player] = entry

	refreshStance(entry)
	character:GetAttributeChangedSignal(WeaponModelDefs.WEAPON_ATTRIBUTE):Connect(function()
		if tracked[player] == entry then
			refreshStance(entry)
		end
	end)
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

local function holdGuard(entry: Tracked, weaponId: string, fromStart: boolean)
	RigAnimation.playAction(entry.controller, AnimationDefs.guard(weaponId), {
		hold = true,
		-- Resuming a guard after a flinch skips the snap and just settles in.
		elapsed = if fromStart then 0 else 0.1,
	})
end

local function isStrike(name: string?): boolean
	return name ~= nil and (string.sub(name, 1, 6) == "swing_" or string.sub(name, 1, 9) == "critical_")
end

local function whooshLater(entry: Tracked, weaponId: string, windup: number)
	local root = rootOf(entry.character)
	task.delay(windup * WHOOSH_AT, function()
		if root and root.Parent then
			SoundFX.playAt(SoundDefs.swingSound(weaponId), root.Position)
		end
	end)
end

local function play(player: Player, action: string, weaponId: string, windup: number?, step: number?)
	local entry = tracked[player]
	if not entry or entry.character ~= player.Character then
		return
	end
	local controller = entry.controller

	if action == "swing" then
		local swingTime = windup or 0.25
		RigAnimation.playAction(controller, AnimationDefs.swing(weaponId, step or 1), { windup = swingTime })
		whooshLater(entry, weaponId, swingTime)
	elseif action == "critical" then
		local swingTime = windup or 0.5
		RigAnimation.playAction(controller, AnimationDefs.critical(weaponId), { windup = swingTime })
		local root = rootOf(entry.character)
		if root then
			SoundFX.playAt("critical_windup", root.Position)
		end
		whooshLater(entry, weaponId, swingTime)
	elseif action == "parry" then
		guardingPlayers[player] = weaponId
		holdGuard(entry, weaponId, true)
	elseif action == "guard_end" then
		guardingPlayers[player] = nil
		if RigAnimation.currentAction(controller) == AnimationDefs.guard(weaponId) then
			RigAnimation.stopAction(controller)
		end
	elseif action == "feint" then
		if isStrike(RigAnimation.currentAction(controller)) then
			RigAnimation.stopAction(controller)
		end
		local root = rootOf(entry.character)
		if root then
			SoundFX.playAt("feint", root.Position)
		end
	elseif action == "dodge" then
		guardingPlayers[player] = nil
		RigAnimation.playAction(controller, AnimationDefs.DODGE)
		local root = rootOf(entry.character)
		if root then
			SoundFX.playAt("dodge", root.Position)
		end
	end
end

--[[ The local player, played on input by CombatClient ]]

function PlayerAnimation.playLocal(action: string, weaponId: string, windup: number?, step: number?)
	play(localPlayer, action, weaponId, windup, step)
end

-- Freeze the local player's pose for a moment as their blow lands.
function PlayerAnimation.hitStopLocal(seconds: number)
	local entry = tracked[localPlayer]
	if entry then
		RigAnimation.hitStop(entry.controller, seconds)
	end
end

-- Being hit cancels a swing in progress (the server's hitstun does the same).
function PlayerAnimation.playLocalHurt()
	local entry = tracked[localPlayer]
	if not entry then
		return
	end
	local current = RigAnimation.currentAction(entry.controller)
	if current == nil or isStrike(current) then
		RigAnimation.playAction(entry.controller, AnimationDefs.HURT)
	end
end

function PlayerAnimation.playLocalGuardBreak()
	local entry = tracked[localPlayer]
	guardingPlayers[localPlayer] = nil
	if entry then
		RigAnimation.playAction(entry.controller, AnimationDefs.GUARD_BREAK)
	end
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
		guardingPlayers[player] = nil
	end)

	Remotes.get("PlayerCombatAction").OnClientEvent:Connect(function(payload)
		local player = Players:GetPlayerByUserId(payload.userId)
		-- The local player's own actions were animated on input. (A guard the
		-- server breaks comes down through CombatClient, which hears about it
		-- from PlayerHit.)
		if not player or player == localPlayer then
			return
		end

		play(player, payload.action, payload.weaponId, payload.windup, payload.step)
	end)

	-- After Roblox's Animate script has posed each avatar for this frame.
	RunService.PreSimulation:Connect(function(deltaTime)
		for player, entry in tracked do
			-- A guard still held when a flinch or swing finishes settles back in.
			local guardWeapon = guardingPlayers[player]
			if guardWeapon and RigAnimation.currentAction(entry.controller) == nil then
				holdGuard(entry, guardWeapon, false)
			end
			RigAnimation.step(entry.controller, deltaTime)
		end
	end)
end

return PlayerAnimation
