--!strict
-- The authority. Owns the enemy state machine, validates every parry and every
-- swing, and is the only place damage or healing is applied.
--
-- The client's inputs are a parry timestamp, a swing request, and a weapon id.
-- All three are treated as untrusted: the timestamp is bounded-rewound, the
-- swing is resolved against server-side positions, and the weapon id is
-- checked against the definition table.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConstants = require(Shared.CombatConstants)
local DamageMath = require(Shared.DamageMath)
local EnemyDefs = require(Shared.EnemyDefs)
local Loadout = require(Shared.Loadout)
local ParryMath = require(Shared.ParryMath)
local Remotes = require(Shared.Remotes)

local EnemyAI = require(script.Parent.EnemyAI)

local CombatServer = {}

-- How long a killed dummy stays down before coming back, so tuning can carry
-- on without restarting the session.
local RESPAWN_DELAY = 3

type PlayerState = {
	weaponId: string,
	stamina: number,
	lockoutUntil: number,
	staminaUpdatedAt: number,
	-- Set by a successful parry; the Assassin's payoff window.
	riposteUntil: number,
	attackReadyAt: number,
	swinging: boolean,
}

type ActiveAttack = {
	attackId: string,
	def: EnemyDefs.AttackDef,
	startTime: number,
	impactTime: number,
	-- Set the instant a parry is validated, which interrupts the strike before
	-- it resolves.
	parried: boolean,
	parriedBy: Player?,
	-- Scaled by the parrying player's class payoff, so a Tank's parry buys a
	-- longer opening than an Assassin's.
	staggerDuration: number,
}

local playerStates: { [Player]: PlayerState } = {}
local enemy: EnemyAI.Enemy? = nil
local activeAttack: ActiveAttack? = nil
local encounterRunning = false

local function getPlayerState(player: Player): PlayerState
	local state = playerStates[player]
	if state then
		return state
	end

	local created: PlayerState = {
		weaponId = Loadout.DEFAULT_WEAPON,
		stamina = CombatConstants.MAX_STAMINA,
		lockoutUntil = 0,
		staminaUpdatedAt = Workspace:GetServerTimeNow(),
		riposteUntil = 0,
		attackReadyAt = 0,
		swinging = false,
	}
	playerStates[player] = created
	return created
end

-- Regen is applied lazily rather than on a tick, so it stays exact regardless
-- of server framerate and costs nothing while nobody is acting.
local function syncStamina(state: PlayerState, now: number)
	local elapsed = math.max(now - state.staminaUpdatedAt, 0)
	state.stamina = ParryMath.regenerateStamina(state.stamina, elapsed)
	state.staminaUpdatedAt = now
end

local function toVec2(position: Vector3): DamageMath.Vec2
	return { x = position.X, z = position.Z }
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function broadcastEnemyHealth(target: EnemyAI.Enemy)
	Remotes.get("EnemyHealthChanged"):FireAllClients({
		enemyId = target.id,
		health = target.health,
		maxHealth = target.def.maxHealth,
		alive = target.alive,
	})
end

--[[ Enemy attacks ]]

local function resolveStrike(attack: ActiveAttack)
	local currentEnemy = enemy
	if not currentEnemy then
		return
	end

	local playerHit = Remotes.get("PlayerHit")
	local attackerPos = toVec2(currentEnemy.root.Position)
	local attackerFacing = toVec2(currentEnemy.root.CFrame.LookVector)

	for _, player in Players:GetPlayers() do
		local root = getCharacterRoot(player)
		if not root then
			continue
		end

		-- Server-side positions only. A client that teleports its local view
		-- out of the cone changes nothing here.
		local inVolume = DamageMath.isInHitVolume({
			attackerPos = attackerPos,
			attackerFacing = attackerFacing,
			targetPos = toVec2(root.Position),
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

		local humanoid = getHumanoid(player)
		if humanoid then
			humanoid:TakeDamage(damage)
		end

		playerHit:FireClient(player, {
			amount = damage,
			sourceId = currentEnemy.id,
			attackId = attack.attackId,
		})
	end
end

-- Waits until `deadline`, returning early if the attack gets parried. Polled on
-- Heartbeat rather than task.wait(n) because the wait has to be interruptible.
local function waitUntilOrInterrupted(deadline: number, attack: ActiveAttack): boolean
	while Workspace:GetServerTimeNow() < deadline do
		if attack.parried then
			return true
		end
		RunService.Heartbeat:Wait()
	end

	return attack.parried
end

local function runAttack(currentEnemy: EnemyAI.Enemy)
	local attackId, attackDef = EnemyAI.nextAttack(currentEnemy)

	local now = Workspace:GetServerTimeNow()
	local attack: ActiveAttack = {
		attackId = attackId,
		def = attackDef,
		startTime = now,
		impactTime = now + attackDef.telegraphDuration,
		parried = false,
		parriedBy = nil,
		staggerDuration = CombatConstants.STAGGER_DURATION,
	}
	activeAttack = attack

	-- The client needs impactTime, not just the duration, so its countdown
	-- stays correct even if this message is delayed in transit.
	Remotes.get("EnemyTelegraphStart"):FireAllClients({
		enemyId = currentEnemy.id,
		attackId = attackId,
		duration = attackDef.telegraphDuration,
		impactTime = attack.impactTime,
		parryable = attackDef.parryable,
	})

	-- Hold the strike open past impact so a late-half parry has time to arrive.
	-- See STRIKE_RESOLUTION_GRACE in CombatConstants for the tradeoff.
	local interrupted =
		waitUntilOrInterrupted(attack.impactTime + CombatConstants.STRIKE_RESOLUTION_GRACE, attack)

	if interrupted then
		Remotes.get("EnemyStaggered"):FireAllClients({
			enemyId = currentEnemy.id,
			duration = attack.staggerDuration,
		})
		activeAttack = nil
		task.wait(attack.staggerDuration)
		return
	end

	resolveStrike(attack)
	activeAttack = nil
	task.wait(CombatConstants.RECOVER_DURATION)
end

--[[ Player input ]]

local function onEquipWeapon(player: Player, payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end

	local result = Loadout.resolve((payload :: any).weaponId)
	if not result.ok then
		return
	end

	local state = getPlayerState(player)
	-- Switching mid-swing would let a player start a cheap fast swing and land
	-- a heavy one, so the swap waits for the current swing to finish.
	if state.swinging then
		return
	end

	state.weaponId = result.weaponId :: string

	Remotes.get("WeaponEquipped"):FireClient(player, {
		weaponId = result.weaponId,
		classTag = result.classTag,
	})
end

local function resolveSwing(player: Player, state: PlayerState, weaponId: string)
	state.swinging = false

	local currentEnemy = enemy
	local attackResult = Remotes.get("AttackResult")
	local def = Loadout.getDef(weaponId).attack
	local payoff = Loadout.getDef(weaponId).payoff

	local root = getCharacterRoot(player)
	if not root or not currentEnemy or not currentEnemy.alive then
		attackResult:FireClient(player, { hit = false, reason = "no_target", damage = 0, riposte = false })
		return
	end

	local inVolume = DamageMath.isInHitVolume({
		attackerPos = toVec2(root.Position),
		attackerFacing = toVec2(root.CFrame.LookVector),
		targetPos = toVec2(currentEnemy.root.Position),
		range = def.range,
		arcDegrees = def.arcDegrees,
	})

	if not inVolume then
		attackResult:FireClient(player, { hit = false, reason = "missed", damage = 0, riposte = false })
		return
	end

	local now = Workspace:GetServerTimeNow()
	local riposteActive = now < state.riposteUntil
	local damage = DamageMath.resolveOutgoing(def.damage, riposteActive, payoff.riposteMultiplier)

	local killed = EnemyAI.applyDamage(currentEnemy, damage)

	attackResult:FireClient(player, {
		hit = true,
		reason = "hit",
		damage = damage,
		riposte = riposteActive,
	})
	broadcastEnemyHealth(currentEnemy)

	if killed then
		EnemyAI.markDead(currentEnemy)
		task.delay(RESPAWN_DELAY, function()
			if currentEnemy == enemy and encounterRunning then
				EnemyAI.revive(currentEnemy)
				broadcastEnemyHealth(currentEnemy)
			end
		end)
	end
end

local function onAttackRequest(player: Player)
	local now = Workspace:GetServerTimeNow()
	local state = getPlayerState(player)
	syncStamina(state, now)

	local attackResult = Remotes.get("AttackResult")

	if state.swinging or now < state.attackReadyAt then
		attackResult:FireClient(player, { hit = false, reason = "cooldown", damage = 0, riposte = false })
		return
	end

	local weaponId = state.weaponId
	local def = Loadout.getDef(weaponId).attack

	if state.stamina < def.staminaCost then
		attackResult:FireClient(player, { hit = false, reason = "exhausted", damage = 0, riposte = false })
		return
	end

	state.stamina -= def.staminaCost
	state.swinging = true
	state.attackReadyAt = now + def.windup + def.cooldown

	-- The weapon is captured now, so a swap landing mid-windup cannot change
	-- which weapon this swing resolves as.
	task.delay(def.windup, function()
		resolveSwing(player, state, weaponId)
	end)
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
	local state = getPlayerState(player)
	syncStamina(state, now)

	local parryResult = Remotes.get("ParryResult")
	local weapon = Loadout.getDef(state.weaponId)

	local function respond(verdict: string, success: boolean, deltaMs: number)
		parryResult:FireClient(player, {
			verdict = verdict,
			success = success,
			deltaMs = deltaMs,
			stamina = state.stamina,
			riposteUntil = state.riposteUntil,
		})
	end

	local readiness = ParryMath.checkReadiness(state.stamina, state.lockoutUntil, now)
	if not readiness.allowed then
		respond(readiness.reason :: string, false, 0)
		return
	end

	-- Spending stamina before evaluating means a whiff costs the same as a
	-- success. Parrying on a read has to be a decision, not a free roll.
	state.stamina -= CombatConstants.PARRY_STAMINA_COST

	local attack = activeAttack
	if not attack then
		-- Nothing incoming: treat as a whiff so blind mashing still burns
		-- stamina and eats the lockout.
		state.lockoutUntil = now + CombatConstants.WHIFF_LOCKOUT
		respond("no_attack", false, 0)
		return
	end

	local evaluation = ParryMath.evaluate({
		attemptTime = attemptTime,
		serverNow = now,
		impactTime = attack.impactTime,
		parryProfile = weapon.parry,
		attackParryable = attack.def.parryable,
	})

	if evaluation.success then
		attack.parried = true
		attack.parriedBy = player
		-- Each class converts a parry into a different advantage.
		attack.staggerDuration =
			DamageMath.staggerDuration(CombatConstants.STAGGER_DURATION, weapon.payoff.staggerMultiplier)

		if weapon.payoff.riposteDuration > 0 then
			state.riposteUntil = now + weapon.payoff.riposteDuration
		end

		if weapon.payoff.selfHeal > 0 then
			local humanoid = getHumanoid(player)
			if humanoid then
				humanoid.Health =
					DamageMath.applyHealing(humanoid.Health, humanoid.MaxHealth, weapon.payoff.selfHeal)
			end
		end
	else
		state.lockoutUntil = now + CombatConstants.WHIFF_LOCKOUT
	end

	respond(evaluation.verdict, evaluation.success, evaluation.deltaMs)
end

--[[ Lifecycle ]]

function CombatServer.start(enemySpawn: Vector3, playerSpawn: Vector3)
	assert(not encounterRunning, "CombatServer.start called twice")

	Remotes.get("ParryAttempt").OnServerEvent:Connect(onParryAttempt)
	Remotes.get("AttackRequest").OnServerEvent:Connect(onAttackRequest)
	Remotes.get("EquipWeapon").OnServerEvent:Connect(onEquipWeapon)

	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
	end)

	-- Tell a joining player what they are holding, so the client never has to
	-- assume a default that could drift from the server's.
	Players.PlayerAdded:Connect(function(player)
		local state = getPlayerState(player)
		Remotes.get("WeaponEquipped"):FireClient(player, {
			weaponId = state.weaponId,
			classTag = Loadout.classOf(state.weaponId),
		})
	end)

	local spawned = EnemyAI.spawn("TrainingDummy", enemySpawn, playerSpawn)
	enemy = spawned
	encounterRunning = true

	task.spawn(function()
		while encounterRunning do
			task.wait(spawned.def.attackInterval)
			if not encounterRunning then
				break
			end
			-- A dead dummy stops swinging until it respawns.
			if spawned.alive then
				runAttack(spawned)
			end
		end
	end)
end

return CombatServer
