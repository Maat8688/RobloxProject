--!strict
-- The authority. Owns the enemy state machine, validates every parry, and is
-- the only place damage is applied.
--
-- The client's sole input is a timestamp. It is never asked whether it was hit,
-- whether it parried, or where it stands — all three are decided here against
-- server-side state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConstants = require(Shared.CombatConstants)
local DamageMath = require(Shared.DamageMath)
local EnemyDefs = require(Shared.EnemyDefs)
local ParryMath = require(Shared.ParryMath)
local Remotes = require(Shared.Remotes)
local WeaponDefs = require(Shared.WeaponDefs)

local EnemyAI = require(script.Parent.EnemyAI)

local CombatServer = {}

-- One weapon in the slice; the equip system that would choose this is
-- build-order step 6.
local SLICE_WEAPON = "SwordAndShield"

type PlayerState = {
	stamina: number,
	lockoutUntil: number,
	staminaUpdatedAt: number,
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
		stamina = CombatConstants.MAX_STAMINA,
		lockoutUntil = 0,
		staminaUpdatedAt = Workspace:GetServerTimeNow(),
	}
	playerStates[player] = created
	return created
end

-- Regen is applied lazily rather than on a tick, so it stays exact regardless
-- of server framerate and costs nothing while nobody is parrying.
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

		local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
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
			duration = CombatConstants.STAGGER_DURATION,
		})
		activeAttack = nil
		task.wait(CombatConstants.STAGGER_DURATION)
		return
	end

	resolveStrike(attack)
	activeAttack = nil
	task.wait(CombatConstants.RECOVER_DURATION)
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

	local readiness = ParryMath.checkReadiness(state.stamina, state.lockoutUntil, now)
	if not readiness.allowed then
		parryResult:FireClient(player, {
			verdict = readiness.reason,
			success = false,
			deltaMs = 0,
			stamina = state.stamina,
		})
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
		parryResult:FireClient(player, {
			verdict = "no_attack",
			success = false,
			deltaMs = 0,
			stamina = state.stamina,
		})
		return
	end

	local evaluation = ParryMath.evaluate({
		attemptTime = attemptTime,
		serverNow = now,
		impactTime = attack.impactTime,
		parryProfile = WeaponDefs[SLICE_WEAPON].parry,
		attackParryable = attack.def.parryable,
	})

	if evaluation.success then
		attack.parried = true
		attack.parriedBy = player
	else
		state.lockoutUntil = now + CombatConstants.WHIFF_LOCKOUT
	end

	parryResult:FireClient(player, {
		verdict = evaluation.verdict,
		success = evaluation.success,
		deltaMs = evaluation.deltaMs,
		stamina = state.stamina,
	})
end

function CombatServer.start(enemySpawn: Vector3, playerSpawn: Vector3)
	assert(not encounterRunning, "CombatServer.start called twice")

	Remotes.get("ParryAttempt").OnServerEvent:Connect(onParryAttempt)
	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
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
			runAttack(spawned)
		end
	end)
end

return CombatServer
