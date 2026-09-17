--!strict
-- Resolves swings and parries inside the active duel.
--
-- PvP reuses the PvE combat system rather than a parallel rule set (DESIGN.md),
-- so a duel runs on the same pieces: ParryMath's timestamp authority and
-- impact-anchored window, the shared stamina pool and whiff lockout, the same
-- late-parry grace, and DamageMath's range/arc hit test. A player's swing
-- stands in for an enemy attack, and their opponent is the one parrying it.
--
-- This module doesn't listen on any remote itself. CombatServer owns the
-- ParryAttempt and AttackRequest listeners and routes a dueling player here,
-- so a single press can never be handled by both PvE and PvP at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConstants = require(Shared.CombatConstants)
local DamageMath = require(Shared.DamageMath)
local Loadout = require(Shared.Loadout)
local ParryMath = require(Shared.ParryMath)
local Remotes = require(Shared.Remotes)

local Characters = require(script.Parent.Parent.Combat.Characters)
local PlayerCombatState = require(script.Parent.Parent.Combat.PlayerCombatState)
local EquipService = require(script.Parent.Parent.EquipService)
local ArenaService = require(script.Parent.ArenaService)
local Duelist = require(script.Parent.Duelist)

local PvPCombatServer = {}

function PvPCombatServer.isDueling(player: Player): boolean
	return ArenaService.getDuelist(player) ~= nil
end

local function attackResult(player: Player, payload: { [string]: any })
	Remotes.get("AttackResult"):FireClient(player, payload)
end

local function resolveSwing(attacker: Player, attackerDuelist: Duelist.Duelist, swing: Duelist.Swing)
	-- A newer swing, or a parry that already staggered this one, owns the
	-- duelist's state now.
	if attackerDuelist.swing ~= swing then
		return
	end
	attackerDuelist.swing = nil

	if swing.parried then
		return
	end

	-- Re-fetched rather than captured at swing time: the duel may have ended
	-- while the telegraph was in flight.
	local opponentDuelist, opponent = ArenaService.getOpponent(attacker)
	if not opponentDuelist or not opponent then
		return
	end

	local weapon = Loadout.getDef(swing.weaponId)
	local attackerRoot = Characters.getRoot(attacker)
	local opponentRoot = Characters.getRoot(opponent)

	local inVolume = attackerRoot ~= nil
		and opponentRoot ~= nil
		and DamageMath.isInHitVolume({
			attackerPos = Characters.flat(attackerRoot.Position),
			attackerFacing = Characters.flat(attackerRoot.CFrame.LookVector),
			targetPos = Characters.flat(opponentRoot.Position),
			range = weapon.attack.range,
			arcDegrees = weapon.attack.arcDegrees,
		})

	Duelist.holdState(attackerDuelist, "recover", weapon.attack.cooldown)

	if not inVolume then
		attackResult(attacker, { hit = false, reason = "missed", damage = 0, riposte = false })
		return
	end

	local now = Workspace:GetServerTimeNow()
	local attackerState = PlayerCombatState.peek(attacker)
	local riposteActive = now < attackerState.riposteUntil

	local damage = DamageMath.resolveOutgoing(EquipService.getDamage(attacker, swing.weaponId), {
		targetStaggered = opponentDuelist.state == "staggered",
		riposteActive = riposteActive,
		riposteMultiplier = weapon.payoff.riposteMultiplier,
	})

	local defeated = Duelist.applyDamage(opponentDuelist, damage)

	Remotes.get("PlayerHit"):FireClient(opponent, {
		amount = damage,
		sourceId = attacker.Name,
		attackId = swing.weaponId,
	})
	attackResult(attacker, { hit = true, reason = "hit", damage = damage, riposte = riposteActive })
	ArenaService.publishHealth()

	if defeated then
		ArenaService.endDuel(opponent)
	end
end

function PvPCombatServer.handleAttack(attacker: Player)
	local attackerDuelist = ArenaService.getDuelist(attacker)
	local _, opponent = ArenaService.getOpponent(attacker)
	if not attackerDuelist or not opponent then
		return
	end

	local weaponId = EquipService.getWeaponId(attacker)
	if not weaponId then
		attackResult(attacker, { hit = false, reason = "unequipped", damage = 0, riposte = false })
		return
	end

	-- The duel state machine is the cooldown: a swing can only start from idle.
	if attackerDuelist.state ~= "idle" then
		attackResult(attacker, { hit = false, reason = "cooldown", damage = 0, riposte = false })
		return
	end

	local now = Workspace:GetServerTimeNow()
	local state = PlayerCombatState.sync(attacker, now)
	local attack = Loadout.getDef(weaponId).attack

	if state.stamina < attack.staminaCost then
		attackResult(attacker, { hit = false, reason = "exhausted", damage = 0, riposte = false })
		return
	end
	state.stamina -= attack.staminaCost

	local swing = Duelist.beginSwing(attackerDuelist, weaponId, now + attack.pvpTelegraph)

	Remotes.get("PvPTelegraphStart"):FireClient(opponent, {
		attackerName = attacker.Name,
		duration = attack.pvpTelegraph,
		impactTime = swing.impactTime,
	})

	-- Held open past impact so a late-half parry can still arrive, exactly as
	-- for enemy attacks.
	task.delay(attack.pvpTelegraph + CombatConstants.STRIKE_RESOLUTION_GRACE, function()
		resolveSwing(attacker, attackerDuelist, swing)
	end)
end

function PvPCombatServer.handleParry(defender: Player, attemptTime: number, now: number)
	local opponentDuelist, attacker = ArenaService.getOpponent(defender)
	if not opponentDuelist or not attacker then
		return
	end

	local parryResult = Remotes.get("ParryResult")
	local state = PlayerCombatState.sync(defender, now)

	local function respond(verdict: string, success: boolean, deltaMs: number)
		parryResult:FireClient(defender, {
			verdict = verdict,
			success = success,
			deltaMs = deltaMs,
			stamina = state.stamina,
			riposteUntil = state.riposteUntil,
			enemyId = if attacker then attacker.Name else nil,
		})
	end

	local weaponId = EquipService.getWeaponId(defender)
	if not weaponId then
		respond("unequipped", false, 0)
		return
	end

	local readiness = ParryMath.checkReadiness(state.stamina, state.lockoutUntil, now)
	if not readiness.allowed then
		respond(readiness.reason :: string, false, 0)
		return
	end

	-- Spent before evaluating, so a whiff costs the same as a success — the
	-- cost that stops parry spam from making a duelist unbeatable.
	state.stamina -= CombatConstants.PARRY_STAMINA_COST

	local swing = opponentDuelist.swing
	local defenderRoot = Characters.getRoot(defender)
	local attackerRoot = Characters.getRoot(attacker)

	local inReach = false
	if swing and defenderRoot and attackerRoot then
		local distance = DamageMath.horizontalDistance(
			Characters.flat(defenderRoot.Position),
			Characters.flat(attackerRoot.Position)
		)
		inReach = distance <= Loadout.getDef(swing.weaponId).attack.range + CombatConstants.PARRY_RANGE_MARGIN
	end

	if not swing or swing.parried or opponentDuelist.state ~= "telegraph" or not inReach then
		state.lockoutUntil = now + CombatConstants.WHIFF_LOCKOUT
		respond("no_attack", false, 0)
		return
	end

	local defenderWeapon = Loadout.getDef(weaponId)
	local evaluation = ParryMath.evaluate({
		attemptTime = attemptTime,
		serverNow = now,
		halfPing = Characters.halfPing(defender),
		impactTime = swing.impactTime,
		parryProfile = defenderWeapon.parry,
		-- Player swings are always parryable. An unparryable player move would
		-- need its own design pass, not a flag flipped here.
		attackParryable = true,
	})

	if not evaluation.success then
		state.lockoutUntil = now + CombatConstants.WHIFF_LOCKOUT
		respond(evaluation.verdict, false, evaluation.deltaMs)
		return
	end

	swing.parried = true

	-- The defender's class decides how long the attacker is opened up, the
	-- same way it does against an enemy.
	local staggerFor = DamageMath.staggerDuration(CombatConstants.STAGGER_DURATION, defenderWeapon.payoff.staggerMultiplier)
	Duelist.holdState(opponentDuelist, "staggered", staggerFor)

	if defenderWeapon.payoff.riposteDuration > 0 then
		state.riposteUntil = now + defenderWeapon.payoff.riposteDuration
	end

	-- No burst heal in a duel: duel health is a virtual pool, so healing the
	-- real Humanoid would do nothing, and healing the pool would be a PvP-only
	-- rule this module exists to avoid.

	respond(evaluation.verdict, true, evaluation.deltaMs)

	local pvpParryResult = Remotes.get("PvPParryResult")
	pvpParryResult:FireClient(defender, { success = true, message = "Parried!" })
	pvpParryResult:FireClient(attacker, { success = false, message = "Your attack was parried!" })
end

return PvPCombatServer
