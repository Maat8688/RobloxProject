-- Wires the same AttackAttempt/ParryAttempt remotes Combat/CombatServer.luau
-- uses for PvE to duel resolution instead, for whichever two players
-- ArenaService currently has dueling — reusing WeaponDefs/CombatConstants
-- rather than a parallel PvP-only rule set, per DESIGN.md's "PvP exists but
-- reuses the same combat system" decision. A player who isn't in a duel is
-- simply ignored here (CombatServer.luau's own listener handles them
-- against dungeon enemies instead — the two listeners never overlap since a
-- player can't be in the arena and the dungeon at once).
--
-- Damage bonus on a Staggered target and the parry-timing check themselves
-- are identical in spirit to Enemy.luau; see Duelist.luau for why each
-- player's own state machine stands in for what Enemy.luau does for a single
-- enemy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConstants = require(Shared:WaitForChild("CombatConstants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local EquipService = require(script.Parent.Parent.EquipService)

local attackAttemptRemote = Remotes.Get(Remotes.Names.AttackAttempt)
local parryAttemptRemote = Remotes.Get(Remotes.Names.ParryAttempt)
local pvpTelegraphRemote = Remotes.Get(Remotes.Names.PvPTelegraphStart)
local pvpParryResultRemote = Remotes.Get(Remotes.Names.PvPParryResult)
local playerHitRemote = Remotes.Get(Remotes.Names.PlayerHit)

local PvPCombatServer = {}

function PvPCombatServer.Start(ArenaService)
	local function resolveAttack(attacker, attackerDuelist)
		-- Re-fetch rather than trusting the opponent captured at swing time:
		-- the duel may have already ended (opponent left, or this duelist
		-- already lost) while the telegraph was in flight.
		local opponentDuelist, opponent = ArenaService.GetOpponent(attacker)
		if opponentDuelist == nil or attackerDuelist.state ~= "Telegraph" then
			return
		end

		if attackerDuelist.parriedThisAttack then
			attackerDuelist.state = "Staggered"
			pvpParryResultRemote:FireClient(opponent, true, "Parried!")
			pvpParryResultRemote:FireClient(attacker, false, "Your attack was parried!")

			task.delay(CombatConstants.STAGGER_DURATION, function()
				if attackerDuelist.state == "Staggered" then
					attackerDuelist.state = "Idle"
				end
			end)

			return
		end

		local damage = attackerDuelist.pendingWeaponDef.baseDamage
		if opponentDuelist.state == "Staggered" then
			damage *= CombatConstants.STAGGER_DAMAGE_MULTIPLIER
		end

		local defeated = opponentDuelist:ApplyDamage(damage)
		playerHitRemote:FireClient(opponent, damage, attacker.Name)
		ArenaService.PublishHealth()

		if defeated then
			ArenaService.EndDuel(opponent)
			return
		end

		attackerDuelist.state = "Recover"
		task.delay(CombatConstants.RECOVER_DURATION, function()
			if attackerDuelist.state == "Recover" then
				attackerDuelist.state = "Idle"
			end
		end)
	end

	attackAttemptRemote.OnServerEvent:Connect(function(player)
		local attackerDuelist = ArenaService.GetDuelist(player)
		if attackerDuelist == nil or attackerDuelist.state ~= "Idle" then
			return
		end

		local _, opponent = ArenaService.GetOpponent(player)
		if opponent == nil then
			return
		end

		local weaponDef = EquipService.GetWeapon(player)
		if weaponDef == nil then
			return
		end

		attackerDuelist:BeginTelegraph(weaponDef)
		pvpTelegraphRemote:FireClient(opponent, player.Name, weaponDef.pvpTelegraphDuration)

		task.delay(weaponDef.pvpTelegraphDuration, function()
			resolveAttack(player, attackerDuelist)
		end)
	end)

	parryAttemptRemote.OnServerEvent:Connect(function(player)
		local opponentDuelist = ArenaService.GetOpponent(player)
		if opponentDuelist == nil or opponentDuelist.state ~= "Telegraph" then
			return
		end

		local weaponDef = EquipService.GetWeapon(player)
		if weaponDef == nil then
			return
		end

		opponentDuelist:TryParry(player, weaponDef.parryWindow)
	end)
end

return PvPCombatServer
