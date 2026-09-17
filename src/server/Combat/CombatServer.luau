--!strict
-- The authority. Owns every enemy's state machine, resolves every hit in both
-- directions, and is the only place PvE damage or healing is applied.
--
-- The client's inputs are presses: block (with a timestamp), release, attack,
-- critical, feint, dodge (with a timestamp), and (in Studio only) a weapon id.
-- All are untrusted: timestamps are checked against the server's own estimate
-- of when they could have been sent, hits are resolved against server-side
-- positions, and cooldowns and stuns are the server's. The client never names
-- what it is hitting, parrying or dodging — the server works it out when each
-- hit lands.
--
-- How an enemy's hit on a player resolves, in order (runAttack, then
-- resolveParried or resolveLanded):
--   1. Dodging, with the hit inside the dodge's invulnerability: nothing lands.
--   2. A parryable hit inside the frames of the player's last block press, from
--      the front: parried. The attack is cancelled for everyone and the enemy
--      staggers.
--   3. Guarding against a parryable hit from the front: blocked. No health
--      lost; posture fills, and a full posture breaks the guard and stuns.
--   4. Otherwise: the hit lands, and stuns briefly.
--
-- This module also owns the input listeners for duels, routing a dueling
-- player's attacks to PvPCombatServer, so one press can never be handled twice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AttackSelector = require(Shared.AttackSelector)
local CombatConstants = require(Shared.CombatConstants)
local DamageMath = require(Shared.DamageMath)
local EnemyDefs = require(Shared.EnemyDefs)
local Loadout = require(Shared.Loadout)
local ParryMath = require(Shared.ParryMath)
local PostureMath = require(Shared.PostureMath)
local Remotes = require(Shared.Remotes)

local Characters = require(script.Parent.Characters)
local EnemyAI = require(script.Parent.EnemyAI)
local PlayerCombatState = require(script.Parent.PlayerCombatState)
local EquipService = require(script.Parent.Parent.EquipService)
local PvPCombatServer = require(script.Parent.Parent.PvP.PvPCombatServer)

local CombatServer = {}

type ActiveAttack = {
	enemyId: string,
	attackId: string,
	def: EnemyDefs.AttackDef,
	impactTime: number,
	-- Set by a player's hit during the windup (unless the attack has hyper
	-- armour): the attack is cancelled and the enemy flinches.
	interrupted: boolean,
}

-- The profile a player's swing resolves with: a combo step or a critical.
type SwingProfile = {
	range: number,
	arcDegrees: number,
	damageMultiplier: number,
}

local enemies: { [string]: EnemyAI.Enemy } = {}
-- Enemies that stay dead once killed: a dungeon run's rooms stay cleared.
local staysDead: { [string]: boolean } = {}
-- Keyed by enemyId: at most one wind-up per enemy, but many across the dungeon.
local activeAttacks: { [string]: ActiveAttack } = {}
-- enemyId -> server time before which the enemy can't be flinched again.
local flinchImmuneUntil: { [string]: number } = {}
local running = false

local function broadcastEnemyHealth(enemy: EnemyAI.Enemy)
	Remotes.get("EnemyHealthChanged"):FireAllClients({
		enemyId = enemy.id,
		health = enemy.health,
		maxHealth = enemy.def.maxHealth,
		alive = enemy.alive,
	})
end

-- Nearest living player this enemy may act on: inside its room, out of the
-- duel arena. Used for targeting and for deciding whether to act at all.
local function getTarget(enemy: EnemyAI.Enemy): (Player?, number)
	local position = enemy.root.Position
	local nearest: Player? = nil
	local nearestDistance = math.huge

	for _, player in Players:GetPlayers() do
		local root = Characters.getRoot(player)
		if not root or not Characters.isAlive(player) or PvPCombatServer.isDueling(player) then
			continue
		end

		if not EnemyAI.canReach(enemy, root.Position) then
			continue
		end

		local distance = DamageMath.horizontalDistance(Characters.flat(position), Characters.flat(root.Position))
		if distance < nearestDistance then
			nearest = player
			nearestDistance = distance
		end
	end

	return nearest, nearestDistance
end

--[[ Enemy attacks ]]

-- Keeps ticking independently of the enemy, which may die, respawn or start
-- another attack while the player is still bleeding. Stops early if the
-- player's character is gone.
local function applyBleed(player: Player, enemy: EnemyAI.Enemy, attackId: string, dot: EnemyDefs.DotDef)
	task.spawn(function()
		for _ = 1, dot.ticks do
			task.wait(dot.tickInterval)

			local humanoid = Characters.getHumanoid(player)
			if not humanoid or humanoid.Health <= 0 then
				return
			end

			humanoid:TakeDamage(dot.tickDamage)
			Remotes.get("PlayerHit"):FireClient(player, {
				amount = dot.tickDamage,
				sourceId = enemy.id,
				attackId = attackId,
				bleed = true,
			})
		end
	end)
end

-- Burst heal for the parrying player and every living player near them. A
-- payoff read from WeaponDefs rather than a check on class name, so any
-- future weapon can carry it.
local function applyBurstHeal(healer: Player, amount: number, radius: number)
	local healerRoot = Characters.getRoot(healer)
	if not healerRoot then
		return
	end

	local origin = Characters.flat(healerRoot.Position)

	for _, player in Players:GetPlayers() do
		local root = Characters.getRoot(player)
		local humanoid = Characters.getHumanoid(player)
		if not root or not humanoid or humanoid.Health <= 0 then
			continue
		end

		if player ~= healer and DamageMath.horizontalDistance(origin, Characters.flat(root.Position)) > radius then
			continue
		end

		local before = humanoid.Health
		humanoid.Health = DamageMath.applyHealing(before, humanoid.MaxHealth, amount)

		local healed = humanoid.Health - before
		if healed > 0 then
			Remotes.get("HealBurst"):FireClient(player, { amount = healed, healerName = healer.Name })
		end
	end
end

type Victim = {
	player: Player,
	root: BasePart,
	state: PlayerCombatState.State,
	facing: boolean,
}

-- Everyone this strike's volume covers, with their state brought up to now.
local function collectVictims(enemy: EnemyAI.Enemy, attack: ActiveAttack, now: number): { Victim }
	local attackerPos = Characters.flat(enemy.root.Position)
	local attackerFacing = Characters.flat(enemy.root.CFrame.LookVector)
	local victims = {}

	for _, player in Players:GetPlayers() do
		local root = Characters.getRoot(player)
		if not root or not Characters.isAlive(player) or PvPCombatServer.isDueling(player) then
			continue
		end

		-- Server-side positions only. A client that teleports its local view
		-- out of the cone changes nothing here.
		local inVolume = DamageMath.isInHitVolume({
			attackerPos = attackerPos,
			attackerFacing = attackerFacing,
			targetPos = Characters.flat(root.Position),
			range = attack.def.range,
			arcDegrees = attack.def.arcDegrees,
		})
		if not inVolume then
			continue
		end

		table.insert(victims, {
			player = player,
			root = root,
			state = PlayerCombatState.sync(player, now),
			facing = DamageMath.isFacing(
				Characters.flat(root.Position),
				Characters.flat(root.CFrame.LookVector),
				attackerPos,
				CombatConstants.BLOCK_ARC_DEGREES
			),
		})
	end

	return victims
end

local function parries(victim: Victim, attack: ActiveAttack): boolean
	local pressAt = victim.state.parryPressAt
	if not attack.def.parryable or not victim.facing or not victim.state.parryFramesOpen or not pressAt then
		return false
	end
	if PlayerCombatState.isStunned(victim.state, attack.impactTime) then
		return false
	end

	local weaponId = EquipService.getWeaponId(victim.player)
	if not weaponId then
		return false
	end
	return ParryMath.catches(pressAt, Loadout.getDef(weaponId).parry, attack.impactTime)
end

-- A strike that at least one player parried: nobody takes it, every parrier
-- gets their class payoff, and the enemy staggers for the longest of them.
-- Returns the stagger duration.
local function resolveParried(enemy: EnemyAI.Enemy, attack: ActiveAttack, parriers: { Victim }, now: number): number
	local staggerFor = 0

	for _, victim in parriers do
		local player = victim.player
		local state = victim.state
		local weapon = Loadout.getDef(EquipService.getWeaponId(player) :: string)
		local payoff = weapon.payoff

		state.parryCaught = true
		PlayerCombatState.setPosture(state, PostureMath.afterParry(state.posture), now, false)

		staggerFor = math.max(staggerFor, DamageMath.staggerDuration(CombatConstants.STAGGER_DURATION, payoff.staggerMultiplier))

		if payoff.riposteDuration > 0 then
			state.riposteUntil = now + payoff.riposteDuration
		end
		if payoff.burstHeal > 0 then
			applyBurstHeal(player, payoff.burstHeal, payoff.burstHealRadius)
		end

		Remotes.get("ParryResult"):FireClient(player, {
			verdict = "parried",
			success = true,
			deltaMs = ((state.parryPressAt :: number) - attack.impactTime) * 1000,
			riposteUntil = state.riposteUntil,
			enemyId = enemy.id,
		})
		PlayerCombatState.publish(player)
	end

	return staggerFor
end

-- A strike nobody parried: dodged, blocked, broken through, or taken.
local function resolveLanded(enemy: EnemyAI.Enemy, attack: ActiveAttack, victims: { Victim }, now: number)
	for _, victim in victims do
		local player = victim.player
		local state = victim.state

		if ParryMath.withinWindow(state.dodgeStartedAt, CombatConstants.DODGE_IFRAMES, attack.impactTime) then
			Remotes.get("PlayerHit"):FireClient(player, {
				amount = 0,
				sourceId = enemy.id,
				attackId = attack.attackId,
				dodged = true,
			})
			continue
		end

		local incoming = DamageMath.resolveIncoming(attack.def.damage, false)
		-- Not mid-swing or stunned: attacking out of a guard opens it.
		local guarding = state.guarding and not state.swinging and not PlayerCombatState.isStunned(state, now)
		local block = DamageMath.resolveBlock(incoming, guarding, attack.def.parryable, victim.facing, state.posture)
		PlayerCombatState.setPosture(state, block.posture, now, block.outcome ~= "unguarded")

		if block.outcome == "broken" then
			state.guarding = false
			PlayerCombatState.stun(state, CombatConstants.GUARD_BREAK_STUN, now)
			PlayerCombatState.announce(player, "guard_end", EquipService.getWeaponId(player) or "")
		elseif block.outcome == "unguarded" then
			PlayerCombatState.stun(state, CombatConstants.PLAYER_HIT_STUN, now)
		end

		if block.damage > 0 then
			local humanoid = Characters.getHumanoid(player)
			if humanoid then
				-- TakeDamage rather than subtracting Health directly, so a
				-- ForceField is respected.
				humanoid:TakeDamage(block.damage)
			end
		end

		Remotes.get("PlayerHit"):FireClient(player, {
			amount = block.damage,
			sourceId = enemy.id,
			attackId = attack.attackId,
			blocked = block.outcome == "blocked",
			guardBroken = block.outcome == "broken",
		})
		PlayerCombatState.publish(player)

		-- A blocked hit doesn't open a wound.
		local dot = attack.def.dot
		if dot and block.outcome ~= "blocked" then
			applyBleed(player, enemy, attack.attackId, dot)
		end
	end
end

-- Waits until `deadline`, returning early if the attack is interrupted or the
-- enemy dies. Polled on Heartbeat because the wait has to be interruptible.
local function waitUntilOrInterrupted(deadline: number, enemy: EnemyAI.Enemy, attack: ActiveAttack)
	while Workspace:GetServerTimeNow() < deadline do
		if attack.interrupted or not enemy.alive then
			return
		end
		RunService.Heartbeat:Wait()
	end
end

local function holdEnemyState(enemy: EnemyAI.Enemy, state: EnemyAI.EnemyState, kind: string, duration: number)
	enemy.state = state
	Remotes.get("EnemyStaggered"):FireAllClients({
		enemyId = enemy.id,
		duration = duration,
		kind = kind,
	})
	task.wait(duration)
	if enemy.alive and enemy.state == state then
		enemy.state = "idle"
	end
end

local function runAttack(enemy: EnemyAI.Enemy, attackId: string)
	local attackDef = enemy.def.attacks[attackId]
	local now = Workspace:GetServerTimeNow()

	local attack: ActiveAttack = {
		enemyId = enemy.id,
		attackId = attackId,
		def = attackDef,
		impactTime = now + attackDef.telegraphDuration,
		interrupted = false,
	}

	activeAttacks[enemy.id] = attack
	enemy.state = "telegraph"
	EnemyAI.markAttackUsed(enemy, attackId, now)

	-- The client needs impactTime, not just the duration, so its animation
	-- stays in step even if this message is delayed in transit.
	Remotes.get("EnemyTelegraphStart"):FireAllClients({
		enemyId = enemy.id,
		attackId = attackId,
		duration = attackDef.telegraphDuration,
		impactTime = attack.impactTime,
		parryable = attackDef.parryable,
	})

	-- Held open past impact so a block press made just before the hit, or a
	-- dodge, has time to arrive. See STRIKE_RESOLUTION_GRACE.
	waitUntilOrInterrupted(attack.impactTime + CombatConstants.STRIKE_RESOLUTION_GRACE, enemy, attack)
	activeAttacks[enemy.id] = nil

	if not enemy.alive then
		return
	end

	if attack.interrupted then
		holdEnemyState(enemy, "flinched", "flinch", CombatConstants.ENEMY_FLINCH_DURATION)
		return
	end

	local resolvedAt = Workspace:GetServerTimeNow()
	local victims = collectVictims(enemy, attack, resolvedAt)

	local parriers = {}
	for _, victim in victims do
		if parries(victim, attack) then
			table.insert(parriers, victim)
		end
	end

	if #parriers > 0 then
		local staggerFor = resolveParried(enemy, attack, parriers, resolvedAt)
		holdEnemyState(enemy, "staggered", "stagger", staggerFor)
		return
	end

	resolveLanded(enemy, attack, victims, resolvedAt)
	task.wait(CombatConstants.RECOVER_DURATION)

	if enemy.alive and enemy.state == "telegraph" then
		enemy.state = "idle"
	end
end

-- One loop per enemy, so a staggered enemy doesn't hold up another. Each loop
-- only ever touches its own enemy's state.
local function runEnemyLoop(enemy: EnemyAI.Enemy)
	-- Ends when the enemy is despawned, not just when it dies: a dead enemy
	-- that will respawn keeps its loop.
	while running and enemies[enemy.id] == enemy do
		task.wait(enemy.def.attackInterval)

		if not running then
			break
		end

		if not enemy.alive or enemy.state ~= "idle" then
			continue
		end

		local target, distance = getTarget(enemy)
		if not target or distance > enemy.def.aggroRange then
			continue
		end

		local attackId = EnemyAI.chooseAttack(enemy, distance, Workspace:GetServerTimeNow())
		if attackId then
			runAttack(enemy, attackId)
		end
	end
end

--[[ Kills ]]

local function onEnemyKilled(enemy: EnemyAI.Enemy, killer: Player)
	EnemyAI.markDead(enemy)
	-- Chest unlocks and payouts hang off this.
	EnemyAI.fireDeath(enemy, killer)

	if staysDead[enemy.id] then
		return
	end

	task.delay(CombatConstants.ENEMY_RESPAWN_DELAY, function()
		if running and enemies[enemy.id] == enemy then
			EnemyAI.revive(enemy)
			broadcastEnemyHealth(enemy)
		end
	end)
end

--[[ Player swings ]]

local function attackResult(player: Player, payload: { [string]: any })
	Remotes.get("AttackResult"):FireClient(player, payload)
end

-- A player's hit interrupts the enemy: a windup without hyper armour is
-- cancelled, and an idle enemy's next move is pushed back. Then it's immune
-- for a moment, so its next attack comes through.
local function flinch(enemy: EnemyAI.Enemy, now: number)
	if now < (flinchImmuneUntil[enemy.id] or 0) then
		return
	end

	if enemy.state == "telegraph" then
		local attack = activeAttacks[enemy.id]
		if not attack or attack.def.hyperArmor then
			return
		end
		attack.interrupted = true
	elseif enemy.state == "idle" then
		task.spawn(holdEnemyState, enemy, "flinched", "flinch", CombatConstants.ENEMY_FLINCH_DURATION)
	else
		return
	end

	flinchImmuneUntil[enemy.id] = now + CombatConstants.ENEMY_FLINCH_IMMUNITY
end

-- Nearest enemy inside the swing volume. Swings hit one target: cleave across
-- a group is a weapon property that doesn't exist yet, and giving it away free
-- would trivialise multi-enemy fights.
local function findSwingTarget(root: BasePart, profile: SwingProfile): EnemyAI.Enemy?
	local attackerPos = Characters.flat(root.Position)
	local attackerFacing = Characters.flat(root.CFrame.LookVector)

	local best: EnemyAI.Enemy? = nil
	local bestDistance = math.huge

	for _, enemy in enemies do
		if not enemy.alive then
			continue
		end

		local targetPos = Characters.flat(enemy.root.Position)
		local inVolume = DamageMath.isInHitVolume({
			attackerPos = attackerPos,
			attackerFacing = attackerFacing,
			targetPos = targetPos,
			range = profile.range,
			arcDegrees = profile.arcDegrees,
		})

		if not inVolume then
			continue
		end

		local distance = DamageMath.horizontalDistance(attackerPos, targetPos)
		if distance < bestDistance then
			best = enemy
			bestDistance = distance
		end
	end

	return best
end

local function resolveSwing(player: Player, weaponId: string, profile: SwingProfile, swingId: number)
	-- Left during the windup. Touching their state now would re-create a record
	-- that PlayerRemoving has already cleared.
	if not player.Parent then
		return
	end

	-- Cancelled by a feint, a dodge, or being hit.
	local state = PlayerCombatState.peek(player)
	if state.swingId ~= swingId then
		return
	end
	state.swinging = false

	local weapon = Loadout.getDef(weaponId)
	local root = Characters.getRoot(player)
	if not root then
		attackResult(player, { hit = false, reason = "no_target", damage = 0, riposte = false })
		return
	end

	local target = findSwingTarget(root, profile)
	if not target then
		attackResult(player, { hit = false, reason = "missed", damage = 0, riposte = false })
		return
	end

	local now = Workspace:GetServerTimeNow()
	local riposteActive = now < state.riposteUntil
	local damage = DamageMath.resolveOutgoing(EquipService.getDamage(player, weaponId) * profile.damageMultiplier, {
		targetStaggered = target.state == "staggered",
		riposteActive = riposteActive,
		riposteMultiplier = weapon.payoff.riposteMultiplier,
	})

	local killed = EnemyAI.applyDamage(target, damage)
	if not killed then
		flinch(target, now)
	end

	attackResult(player, {
		hit = true,
		reason = "hit",
		damage = damage,
		riposte = riposteActive,
		enemyId = target.id,
	})
	broadcastEnemyHealth(target)

	if killed then
		onEnemyKilled(target, player)
	end
end

-- Checks shared by every attack press. Returns the weapon id if the player
-- may attack now.
local function canAttack(player: Player, state: PlayerCombatState.State, now: number): string?
	local weaponId = EquipService.getWeaponId(player)
	if not weaponId then
		attackResult(player, { hit = false, reason = "unequipped", damage = 0, riposte = false })
		return nil
	end

	if PlayerCombatState.isStunned(state, now) then
		attackResult(player, { hit = false, reason = "stunned", damage = 0, riposte = false })
		return nil
	end

	-- Blocking and attacking are exclusive: let go of block to swing.
	if state.guarding then
		attackResult(player, { hit = false, reason = "guarding", damage = 0, riposte = false })
		return nil
	end

	if state.swinging or now < state.attackReadyAt then
		attackResult(player, { hit = false, reason = "cooldown", damage = 0, riposte = false })
		return nil
	end

	return weaponId
end

local function startSwing(player: Player, state: PlayerCombatState.State, weaponId: string, windup: number, profile: SwingProfile, now: number)
	state.swingId += 1
	state.swinging = true
	state.swingStartedAt = now
	state.swingWindup = windup

	-- The weapon and profile are captured now, so a swap landing mid-windup
	-- cannot change what this swing resolves as.
	task.delay(windup, resolveSwing, player, weaponId, profile, state.swingId)
end

local function onAttackRequest(player: Player)
	if PvPCombatServer.isDueling(player) then
		PvPCombatServer.handleAttack(player)
		return
	end

	local now = Workspace:GetServerTimeNow()
	local state = PlayerCombatState.sync(player, now)
	local weaponId = canAttack(player, state, now)
	if not weaponId then
		return
	end

	local attack = Loadout.getDef(weaponId).attack
	local step = Loadout.nextComboStep(attack, state.comboStep, now, state.comboExpiresAt)
	local timing = Loadout.swingTiming(attack, step)

	state.attackReadyAt = now + timing.readyAfter
	state.comboStep = step
	state.comboExpiresAt = now + timing.comboExpiresAfter

	PlayerCombatState.announce(player, "swing", weaponId, timing.windup, step)
	startSwing(player, state, weaponId, timing.windup, {
		range = attack.range,
		arcDegrees = attack.arcDegrees,
		damageMultiplier = timing.damageMultiplier,
	}, now)
end

local function onCriticalRequest(player: Player)
	-- Criticals are a dungeon move for now; duels keep to the opening swing.
	if PvPCombatServer.isDueling(player) then
		return
	end

	local now = Workspace:GetServerTimeNow()
	local state = PlayerCombatState.sync(player, now)
	local weaponId = canAttack(player, state, now)
	if not weaponId then
		return
	end

	if now < state.criticalReadyAt then
		attackResult(player, { hit = false, reason = "cooldown", damage = 0, riposte = false })
		return
	end

	local attack = Loadout.getDef(weaponId).attack
	local critical = attack.critical

	state.criticalReadyAt = now + critical.cooldown
	state.attackReadyAt = now + critical.windup + attack.finisherRecovery
	state.comboStep = 0

	PlayerCombatState.announce(player, "critical", weaponId, critical.windup)
	startSwing(player, state, weaponId, critical.windup, {
		range = critical.range,
		arcDegrees = critical.arcDegrees,
		damageMultiplier = critical.damageMultiplier,
	}, now)
	PlayerCombatState.publish(player)
end

-- Cancels a swing early in its windup: the tool for baiting a parry.
local function onFeintRequest(player: Player)
	local now = Workspace:GetServerTimeNow()
	local state = PlayerCombatState.peek(player)
	if now < state.feintReadyAt or not PlayerCombatState.inCancelWindow(state, now) then
		return
	end

	PlayerCombatState.cancelSwing(state)
	state.attackReadyAt = now
	state.feintReadyAt = now + CombatConstants.FEINT_COOLDOWN
	PlayerCombatState.announce(player, "feint", EquipService.getWeaponId(player) or "")
end

--[[ Defence ]]

-- Validates a timestamped press. Returns the claimed time if believable.
local function validatedTimestamp(player: Player, payload: unknown, now: number): number?
	if typeof(payload) ~= "table" then
		return nil
	end

	local attemptTime = (payload :: any).timestamp
	if typeof(attemptTime) ~= "number" or attemptTime ~= attemptTime then
		return nil
	end

	if ParryMath.validateTimestamp(attemptTime, now, Characters.halfPing(player)) then
		return nil
	end
	return attemptTime
end

-- The block key going down: raises the guard, and opens parry frames unless
-- the last press missed and parrying is still on cooldown.
local function onParryAttempt(player: Player, payload: unknown)
	local now = Workspace:GetServerTimeNow()
	local attemptTime = validatedTimestamp(player, payload, now)
	local weaponId = EquipService.getWeaponId(player)
	if not attemptTime or not weaponId then
		return
	end

	local state = PlayerCombatState.sync(player, now)
	if PlayerCombatState.isStunned(state, now) then
		return
	end

	state.guarding = true

	local profile = Loadout.getDef(weaponId).parry
	state.parryFramesOpen = ParryMath.pressOpensFrames(state.parryPressAt, state.parryCaught, profile, now)
	if state.parryFramesOpen then
		state.parryPressAt = attemptTime
		state.parryCaught = false
	end

	-- Nothing is judged now: whatever this press catches is decided when each
	-- hit lands, against enemies and duel opponents alike.
	PlayerCombatState.announce(player, "parry", weaponId)
end

local function onGuardReleased(player: Player)
	local state = PlayerCombatState.peek(player)
	if not state.guarding then
		return
	end

	state.guarding = false
	PlayerCombatState.announce(player, "guard_end", EquipService.getWeaponId(player) or "")
end

-- The dash. Invulnerable from the press for DODGE_IFRAMES; cancels a swing
-- still early in its windup, and drops the guard.
local function onDodgeRequest(player: Player, payload: unknown)
	local now = Workspace:GetServerTimeNow()
	local attemptTime = validatedTimestamp(player, payload, now)
	if not attemptTime then
		return
	end

	local state = PlayerCombatState.sync(player, now)
	if PlayerCombatState.isStunned(state, now) or now < state.dodgeReadyAt then
		return
	end

	if state.swinging then
		if not PlayerCombatState.inCancelWindow(state, now) then
			return
		end
		PlayerCombatState.cancelSwing(state)
		state.attackReadyAt = now
	end

	state.guarding = false
	state.dodgeStartedAt = attemptTime
	state.dodgeReadyAt = now + CombatConstants.DODGE_COOLDOWN

	PlayerCombatState.announce(player, "dodge", EquipService.getWeaponId(player) or "")
	PlayerCombatState.publish(player)
end

--[[ Debug equip ]]

-- Number-key weapon swapping, for comparing weapons back to back while
-- tuning. Studio only: in a live server the weapon stands are the one way to
-- equip, and this remote does nothing.
local function onEquipWeapon(player: Player, payload: unknown)
	if not RunService:IsStudio() or typeof(payload) ~= "table" then
		return
	end

	-- Swapping mid-swing would let a player start a cheap fast swing and land a
	-- heavy one.
	if PlayerCombatState.peek(player).swinging then
		return
	end

	EquipService.setWeapon(player, (payload :: any).weaponId)
end

--[[ Lifecycle ]]

export type SpawnOptions = {
	-- Respawn in place a few seconds after dying. On by default.
	respawns: boolean?,
}

-- Spawns an enemy and starts its loop. `bounds` leashes it to its room.
function CombatServer.spawnEnemy(
	defId: string,
	position: Vector3,
	facePosition: Vector3,
	bounds: AttackSelector.Bounds?,
	parent: Instance?,
	options: SpawnOptions?
): EnemyAI.Enemy
	assert(running, "CombatServer.start must be called before spawning enemies")

	local enemy = EnemyAI.spawn(defId, position, facePosition, bounds, parent)
	enemies[enemy.id] = enemy
	if options and options.respawns == false then
		staysDead[enemy.id] = true
	end
	broadcastEnemyHealth(enemy)
	task.spawn(runEnemyLoop, enemy)
	return enemy
end

-- Removes an enemy for good: stops its loop, cancels any windup in flight,
-- and destroys its model. For tearing down a finished dungeon.
function CombatServer.despawnEnemy(enemy: EnemyAI.Enemy)
	if enemies[enemy.id] ~= enemy then
		return
	end

	enemies[enemy.id] = nil
	staysDead[enemy.id] = nil
	activeAttacks[enemy.id] = nil
	flinchImmuneUntil[enemy.id] = nil
	enemy.alive = false
	enemy.state = "dead"
	enemy.model:Destroy()
end

function CombatServer.start()
	assert(not running, "CombatServer.start called twice")
	running = true

	Remotes.get("ParryAttempt").OnServerEvent:Connect(onParryAttempt)
	Remotes.get("GuardReleased").OnServerEvent:Connect(onGuardReleased)
	Remotes.get("AttackRequest").OnServerEvent:Connect(onAttackRequest)
	Remotes.get("CriticalRequest").OnServerEvent:Connect(onCriticalRequest)
	Remotes.get("FeintRequest").OnServerEvent:Connect(onFeintRequest)
	Remotes.get("DodgeRequest").OnServerEvent:Connect(onDodgeRequest)
	Remotes.get("EquipWeapon").OnServerEvent:Connect(onEquipWeapon)

	-- A joining player needs every enemy's current health for the HUD.
	Players.PlayerAdded:Connect(function(player)
		for _, enemy in enemies do
			Remotes.get("EnemyHealthChanged"):FireClient(player, {
				enemyId = enemy.id,
				health = enemy.health,
				maxHealth = enemy.def.maxHealth,
				alive = enemy.alive,
			})
		end
	end)

	-- Movement steps every enemy on one Heartbeat rather than inside each
	-- enemy's own loop, so they all move against the same frame delta.
	RunService.Heartbeat:Connect(function(deltaTime)
		for _, enemy in enemies do
			local target = getTarget(enemy)
			local root = if target then Characters.getRoot(target) else nil
			if root then
				EnemyAI.step(enemy, root.Position, deltaTime)
			end
		end
	end)
end

return CombatServer
