--!strict
-- The authority. Owns every enemy's state machine, validates every parry and
-- every swing, and is the only place PvE damage or healing is applied.
--
-- The client's inputs are a parry timestamp, a swing request, and (in Studio
-- only) a weapon id. All are treated as untrusted: the timestamp is checked
-- against the server's own estimate of when it could have been sent, swings
-- are resolved against server-side positions, and weapon ids are checked
-- against the definition table. The client never names which enemy it is
-- parrying or swinging at — the server resolves both.
--
-- This module also owns the ParryAttempt and AttackRequest listeners for
-- PvP, routing a dueling player to PvPCombatServer, so one press can never be
-- handled by both.

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
	-- Set the instant a parry is validated, which interrupts the strike before
	-- it resolves.
	parried: boolean,
	parriedBy: Player?,
	-- Scaled by the parrying player's class payoff, so a Tank's parry buys a
	-- longer opening than an Assassin's.
	staggerDuration: number,
}

local enemies: { [string]: EnemyAI.Enemy } = {}
-- Keyed by enemyId: at most one wind-up per enemy, but many across the dungeon.
local activeAttacks: { [string]: ActiveAttack } = {}
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

local function resolveStrike(enemy: EnemyAI.Enemy, attack: ActiveAttack)
	local attackerPos = Characters.flat(enemy.root.Position)
	local attackerFacing = Characters.flat(enemy.root.CFrame.LookVector)

	for _, player in Players:GetPlayers() do
		local root = Characters.getRoot(player)
		if not root then
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

		local wasParried = attack.parried and attack.parriedBy == player
		local damage = DamageMath.resolveIncoming(attack.def.damage, wasParried)
		if damage <= 0 then
			continue
		end

		local humanoid = Characters.getHumanoid(player)
		if humanoid then
			-- TakeDamage rather than subtracting Health directly, so a
			-- ForceField is respected.
			humanoid:TakeDamage(damage)
		end

		Remotes.get("PlayerHit"):FireClient(player, {
			amount = damage,
			sourceId = enemy.id,
			attackId = attack.attackId,
		})

		local dot = attack.def.dot
		if dot then
			applyBleed(player, enemy, attack.attackId, dot)
		end
	end
end

-- Waits until `deadline`, returning early if the attack gets parried or the
-- enemy dies. Polled on Heartbeat because the wait has to be interruptible.
local function waitUntilOrInterrupted(deadline: number, enemy: EnemyAI.Enemy, attack: ActiveAttack): boolean
	while Workspace:GetServerTimeNow() < deadline do
		if attack.parried or not enemy.alive then
			return attack.parried
		end
		RunService.Heartbeat:Wait()
	end

	return attack.parried
end

local function runAttack(enemy: EnemyAI.Enemy, attackId: string)
	local attackDef = enemy.def.attacks[attackId]
	local now = Workspace:GetServerTimeNow()

	local attack: ActiveAttack = {
		enemyId = enemy.id,
		attackId = attackId,
		def = attackDef,
		impactTime = now + attackDef.telegraphDuration,
		parried = false,
		parriedBy = nil,
		staggerDuration = CombatConstants.STAGGER_DURATION,
	}

	activeAttacks[enemy.id] = attack
	enemy.state = "telegraph"
	EnemyAI.markAttackUsed(enemy, attackId, now)

	-- The client needs impactTime, not just the duration, so its countdown
	-- stays correct even if this message is delayed in transit.
	Remotes.get("EnemyTelegraphStart"):FireAllClients({
		enemyId = enemy.id,
		attackId = attackId,
		duration = attackDef.telegraphDuration,
		impactTime = attack.impactTime,
		parryable = attackDef.parryable,
	})

	-- Hold the strike open past impact so a late-half parry has time to arrive.
	-- See STRIKE_RESOLUTION_GRACE in CombatConstants for the tradeoff.
	local interrupted =
		waitUntilOrInterrupted(attack.impactTime + CombatConstants.STRIKE_RESOLUTION_GRACE, enemy, attack)

	activeAttacks[enemy.id] = nil

	if not enemy.alive then
		return
	end

	if interrupted then
		enemy.state = "staggered"
		Remotes.get("EnemyStaggered"):FireAllClients({
			enemyId = enemy.id,
			duration = attack.staggerDuration,
		})
		task.wait(attack.staggerDuration)
	else
		resolveStrike(enemy, attack)
		task.wait(CombatConstants.RECOVER_DURATION)
	end

	if enemy.alive then
		enemy.state = "idle"
	end
end

-- One loop per enemy, so a staggered enemy doesn't hold up another. Each loop
-- only ever touches its own enemy's state.
local function runEnemyLoop(enemy: EnemyAI.Enemy)
	while running do
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

-- Nearest enemy inside the swing volume. Swings hit one target: cleave across
-- a group is a weapon property that doesn't exist yet, and giving it away free
-- would trivialise multi-enemy fights.
local function findSwingTarget(root: BasePart, attack: { range: number, arcDegrees: number }): EnemyAI.Enemy?
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
			range = attack.range,
			arcDegrees = attack.arcDegrees,
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

local function resolveSwing(player: Player, weaponId: string)
	-- Left during the windup. Touching their state now would re-create a record
	-- that PlayerRemoving has already cleared.
	if not player.Parent then
		return
	end

	local state = PlayerCombatState.peek(player)
	state.swinging = false

	local weapon = Loadout.getDef(weaponId)
	local root = Characters.getRoot(player)
	if not root then
		attackResult(player, { hit = false, reason = "no_target", damage = 0, riposte = false })
		return
	end

	local target = findSwingTarget(root, weapon.attack)
	if not target then
		attackResult(player, { hit = false, reason = "missed", damage = 0, riposte = false })
		return
	end

	local now = Workspace:GetServerTimeNow()
	local riposteActive = now < state.riposteUntil
	local damage = DamageMath.resolveOutgoing(EquipService.getDamage(player, weaponId), {
		targetStaggered = target.state == "staggered",
		riposteActive = riposteActive,
		riposteMultiplier = weapon.payoff.riposteMultiplier,
	})

	local killed = EnemyAI.applyDamage(target, damage)

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

local function onAttackRequest(player: Player)
	if PvPCombatServer.isDueling(player) then
		PvPCombatServer.handleAttack(player)
		return
	end

	local weaponId = EquipService.getWeaponId(player)
	if not weaponId then
		attackResult(player, { hit = false, reason = "unequipped", damage = 0, riposte = false })
		return
	end

	local now = Workspace:GetServerTimeNow()
	local state = PlayerCombatState.sync(player, now)

	if state.swinging or now < state.attackReadyAt then
		attackResult(player, { hit = false, reason = "cooldown", damage = 0, riposte = false })
		return
	end

	local attack = Loadout.getDef(weaponId).attack

	if state.stamina < attack.staminaCost then
		attackResult(player, { hit = false, reason = "exhausted", damage = 0, riposte = false })
		return
	end

	state.stamina -= attack.staminaCost
	state.swinging = true
	state.attackReadyAt = now + attack.windup + attack.cooldown

	PlayerCombatState.announce(player, "swing", weaponId, attack.windup)

	-- The weapon is captured now, so a swap landing mid-windup cannot change
	-- which weapon this swing resolves as.
	task.delay(attack.windup, resolveSwing, player, weaponId)
end

--[[ Player parries ]]

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

-- Every wind-up currently in flight, as parry candidates for this player.
-- Built fresh per press, since an attack can resolve between two presses.
local function collectParryCandidates(root: BasePart): { ParryMath.ParryCandidate }
	local playerPos = Characters.flat(root.Position)
	local candidates = {}

	for enemyId, attack in activeAttacks do
		local enemy = enemies[enemyId]
		if not enemy then
			continue
		end

		table.insert(candidates, {
			enemyId = enemyId,
			impactTime = attack.impactTime,
			parryable = attack.def.parryable,
			distance = DamageMath.horizontalDistance(playerPos, Characters.flat(enemy.root.Position)),
			reach = attack.def.range + CombatConstants.PARRY_RANGE_MARGIN,
		})
	end

	return candidates
end

local function handlePvEParry(player: Player, attemptTime: number, now: number)
	local state = PlayerCombatState.sync(player, now)

	local function respond(verdict: string, success: boolean, deltaMs: number, enemyId: string?)
		Remotes.get("ParryResult"):FireClient(player, {
			verdict = verdict,
			success = success,
			deltaMs = deltaMs,
			stamina = state.stamina,
			riposteUntil = state.riposteUntil,
			enemyId = enemyId,
		})
	end

	local weaponId = EquipService.getWeaponId(player)
	local root = Characters.getRoot(player)
	if not weaponId or not root then
		respond("unequipped", false, 0, nil)
		return
	end

	local readiness = ParryMath.checkReadiness(state.stamina, state.lockoutUntil, now)
	if not readiness.allowed then
		respond(readiness.reason :: string, false, 0, nil)
		return
	end

	-- Spent before evaluating, so a whiff costs the same as a success. Parrying
	-- on a read has to be a decision, not a free roll.
	state.stamina -= CombatConstants.PARRY_STAMINA_COST

	PlayerCombatState.announce(player, "parry", weaponId)

	local candidate = ParryMath.selectParryTarget(collectParryCandidates(root), attemptTime)
	local attack = if candidate then activeAttacks[candidate.enemyId] else nil
	if not attack then
		-- Nothing incoming that could reach this player: a whiff, so blind
		-- mashing still burns stamina and eats the lockout.
		state.lockoutUntil = now + CombatConstants.WHIFF_LOCKOUT
		respond("no_attack", false, 0, nil)
		return
	end

	local weapon = Loadout.getDef(weaponId)
	local evaluation = ParryMath.evaluate({
		attemptTime = attemptTime,
		serverNow = now,
		halfPing = Characters.halfPing(player),
		impactTime = attack.impactTime,
		parryProfile = weapon.parry,
		attackParryable = attack.def.parryable,
	})

	if not evaluation.success then
		state.lockoutUntil = now + CombatConstants.WHIFF_LOCKOUT
		respond(evaluation.verdict, false, evaluation.deltaMs, attack.enemyId)
		return
	end

	attack.parried = true
	attack.parriedBy = player

	-- Each class converts a parry into a different advantage.
	local payoff = weapon.payoff
	attack.staggerDuration = DamageMath.staggerDuration(CombatConstants.STAGGER_DURATION, payoff.staggerMultiplier)

	if payoff.riposteDuration > 0 then
		state.riposteUntil = now + payoff.riposteDuration
	end

	if payoff.burstHeal > 0 then
		applyBurstHeal(player, payoff.burstHeal, payoff.burstHealRadius)
	end

	respond(evaluation.verdict, true, evaluation.deltaMs, attack.enemyId)
end

local function onParryAttempt(player: Player, payload: unknown)
	-- Remote payloads are client-controlled: validate shape before touching it.
	if typeof(payload) ~= "table" then
		return
	end

	local attemptTime = (payload :: any).timestamp
	if typeof(attemptTime) ~= "number" or attemptTime ~= attemptTime then
		return
	end

	local now = Workspace:GetServerTimeNow()

	if PvPCombatServer.isDueling(player) then
		PvPCombatServer.handleParry(player, attemptTime, now)
	else
		handlePvEParry(player, attemptTime, now)
	end
end

--[[ Debug equip ]]

-- Number-key weapon swapping, for comparing parry windows back to back while
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

-- Spawns an enemy and starts its loop. `bounds` leashes it to its room.
function CombatServer.spawnEnemy(
	defId: string,
	position: Vector3,
	facePosition: Vector3,
	bounds: AttackSelector.Bounds?,
	parent: Instance?
): EnemyAI.Enemy
	assert(running, "CombatServer.start must be called before spawning enemies")

	local enemy = EnemyAI.spawn(defId, position, facePosition, bounds, parent)
	enemies[enemy.id] = enemy
	broadcastEnemyHealth(enemy)
	task.spawn(runEnemyLoop, enemy)
	return enemy
end

function CombatServer.start()
	assert(not running, "CombatServer.start called twice")
	running = true

	Remotes.get("ParryAttempt").OnServerEvent:Connect(onParryAttempt)
	Remotes.get("AttackRequest").OnServerEvent:Connect(onAttackRequest)
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
