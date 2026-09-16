--!strict
-- The authority. Owns every enemy's state machine, validates every parry and
-- every swing, and is the only place damage or healing is applied.
--
-- The client's inputs are a parry timestamp, a swing request, and a weapon id.
-- All three are treated as untrusted: the timestamp is bounded-rewound, the
-- swing is resolved against server-side positions, and the weapon id is
-- checked against the definition table. Notably the client never names which
-- enemy it is parrying or swinging at — the server resolves both.

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

-- How long a killed enemy stays down before coming back, so tuning can carry
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

local playerStates: { [Player]: PlayerState } = {}
local enemies: { [string]: EnemyAI.Enemy } = {}
-- Keyed by enemyId: at most one wind-up per enemy, but many across the room.
local activeAttacks: { [string]: ActiveAttack } = {}
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

local function isAlive(player: Player): boolean
	local humanoid = getHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Nearest living player, used both for enemy targeting and for deciding
-- whether an enemy has anyone to act on at all.
local function getNearestPlayer(position: Vector3): (Player?, number)
	local nearest: Player? = nil
	local nearestDistance = math.huge

	for _, player in Players:GetPlayers() do
		local root = getCharacterRoot(player)
		if not root or not isAlive(player) then
			continue
		end

		local offset = root.Position - position
		local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if distance < nearestDistance then
			nearest = player
			nearestDistance = distance
		end
	end

	return nearest, nearestDistance
end

local function broadcastEnemyHealth(enemy: EnemyAI.Enemy)
	Remotes.get("EnemyHealthChanged"):FireAllClients({
		enemyId = enemy.id,
		health = enemy.health,
		maxHealth = enemy.def.maxHealth,
		alive = enemy.alive,
	})
end

--[[ Enemy attacks ]]

local function resolveStrike(enemy: EnemyAI.Enemy, attack: ActiveAttack)
	local playerHit = Remotes.get("PlayerHit")
	local attackerPos = toVec2(enemy.root.Position)
	local attackerFacing = toVec2(enemy.root.CFrame.LookVector)

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
			sourceId = enemy.id,
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
		waitUntilOrInterrupted(attack.impactTime + CombatConstants.STRIKE_RESOLUTION_GRACE, attack)

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

-- One loop per enemy, so a staggered Shambler doesn't hold up a Spitter across
-- the room. Each loop only ever touches its own enemy's state.
local function runEnemyLoop(enemy: EnemyAI.Enemy)
	while encounterRunning do
		task.wait(enemy.def.attackInterval)

		if not encounterRunning then
			break
		end

		if not enemy.alive or enemy.state ~= "idle" then
			continue
		end

		local target, distance = getNearestPlayer(enemy.root.Position)
		if not target or distance > enemy.def.aggroRange then
			continue
		end

		local attackId = EnemyAI.chooseAttack(enemy, distance, Workspace:GetServerTimeNow())
		if attackId then
			runAttack(enemy, attackId)
		end
	end
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

-- Nearest enemy inside the swing volume. Swings hit one target: cleave across
-- a group is a weapon property that doesn't exist yet, and giving it away free
-- would quietly trivialise multi-enemy fights the moment they arrived.
local function findSwingTarget(root: BasePart, attack: { range: number, arcDegrees: number }): EnemyAI.Enemy?
	local attackerPos = toVec2(root.Position)
	local attackerFacing = toVec2(root.CFrame.LookVector)

	local best: EnemyAI.Enemy? = nil
	local bestDistance = math.huge

	for _, enemy in enemies do
		if not enemy.alive then
			continue
		end

		local inVolume = DamageMath.isInHitVolume({
			attackerPos = attackerPos,
			attackerFacing = attackerFacing,
			targetPos = toVec2(enemy.root.Position),
			range = attack.range,
			arcDegrees = attack.arcDegrees,
		})

		if not inVolume then
			continue
		end

		local distance = (enemy.root.Position - root.Position).Magnitude
		if distance < bestDistance then
			best = enemy
			bestDistance = distance
		end
	end

	return best
end

local function resolveSwing(player: Player, state: PlayerState, weaponId: string)
	state.swinging = false

	local attackResult = Remotes.get("AttackResult")
	local weapon = Loadout.getDef(weaponId)

	local root = getCharacterRoot(player)
	if not root then
		attackResult:FireClient(player, { hit = false, reason = "no_target", damage = 0, riposte = false })
		return
	end

	local target = findSwingTarget(root, weapon.attack)
	if not target then
		attackResult:FireClient(player, { hit = false, reason = "missed", damage = 0, riposte = false })
		return
	end

	local now = Workspace:GetServerTimeNow()
	local riposteActive = now < state.riposteUntil
	local damage = DamageMath.resolveOutgoing(weapon.attack.damage, riposteActive, weapon.payoff.riposteMultiplier)

	local killed = EnemyAI.applyDamage(target, damage)

	attackResult:FireClient(player, {
		hit = true,
		reason = "hit",
		damage = damage,
		riposte = riposteActive,
		enemyId = target.id,
	})
	broadcastEnemyHealth(target)

	if killed then
		EnemyAI.markDead(target)
		task.delay(RESPAWN_DELAY, function()
			if encounterRunning and enemies[target.id] == target then
				EnemyAI.revive(target)
				broadcastEnemyHealth(target)
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

-- Every wind-up currently in flight, as parry candidates. Built fresh per
-- attempt rather than cached, because an attack can resolve between two
-- presses.
local function collectParryCandidates(): { ParryMath.ParryCandidate }
	local candidates = {}

	for _, attack in activeAttacks do
		table.insert(candidates, {
			enemyId = attack.enemyId,
			impactTime = attack.impactTime,
			parryable = attack.def.parryable,
		})
	end

	return candidates
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

	local function respond(verdict: string, success: boolean, deltaMs: number, enemyId: string?)
		parryResult:FireClient(player, {
			verdict = verdict,
			success = success,
			deltaMs = deltaMs,
			stamina = state.stamina,
			riposteUntil = state.riposteUntil,
			enemyId = enemyId,
		})
	end

	local readiness = ParryMath.checkReadiness(state.stamina, state.lockoutUntil, now)
	if not readiness.allowed then
		respond(readiness.reason :: string, false, 0, nil)
		return
	end

	-- Spending stamina before evaluating means a whiff costs the same as a
	-- success. Parrying on a read has to be a decision, not a free roll.
	state.stamina -= CombatConstants.PARRY_STAMINA_COST

	-- The server picks which incoming attack this press is aimed at; the client
	-- never names a target.
	local candidate = ParryMath.selectParryTarget(collectParryCandidates(), attemptTime)
	if not candidate then
		-- Nothing incoming: treat as a whiff so blind mashing still burns
		-- stamina and eats the lockout.
		state.lockoutUntil = now + CombatConstants.WHIFF_LOCKOUT
		respond("no_attack", false, 0, nil)
		return
	end

	local attack = activeAttacks[candidate.enemyId]
	if not attack then
		state.lockoutUntil = now + CombatConstants.WHIFF_LOCKOUT
		respond("no_attack", false, 0, nil)
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

	respond(evaluation.verdict, evaluation.success, evaluation.deltaMs, attack.enemyId)
end

--[[ Lifecycle ]]

function CombatServer.start(spawns: { { defId: string, position: Vector3 } }, playerSpawn: Vector3)
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

		for _, enemy in enemies do
			broadcastEnemyHealth(enemy)
		end
	end)

	encounterRunning = true

	for _, spawn in spawns do
		local enemy = EnemyAI.spawn(spawn.defId, spawn.position, playerSpawn)
		enemies[enemy.id] = enemy
		task.spawn(runEnemyLoop, enemy)
	end

	-- Movement steps every enemy on one Heartbeat rather than inside each
	-- enemy's own loop, so they all move against the same frame delta.
	RunService.Heartbeat:Connect(function(deltaTime)
		if not encounterRunning then
			return
		end

		for _, enemy in enemies do
			local target = getNearestPlayer(enemy.root.Position)
			local root = if target then getCharacterRoot(target) else nil
			if root then
				EnemyAI.step(enemy, root.Position, deltaTime)
			end
		end
	end)
end

return CombatServer
