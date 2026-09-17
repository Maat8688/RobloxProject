-- One enemy instance: spawns its body in Workspace and runs its own
-- Idle -> Telegraph -> (Staggered | Recover) -> Idle loop, picking randomly
-- among its EnemyDefs attacks each cycle. This class is already the
-- generalized enemy AI (build order step 3) — a separate EnemyAI.luau was
-- planned in ARCHITECTURE.md but turned out unnecessary, since every enemy
-- already goes through Enemy.new; see DESIGN.md's decision log.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConstants = require(Shared:WaitForChild("CombatConstants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local telegraphRemote = Remotes.Get(Remotes.Names.EnemyTelegraphStart)
local stateChangedRemote = Remotes.Get(Remotes.Names.EnemyStateChanged)
local playerHitRemote = Remotes.Get(Remotes.Names.PlayerHit)

local Enemy = {}
Enemy.__index = Enemy

function Enemy.new(id, def, spawnCFrame, parent)
	parent = parent or Workspace

	local model = Instance.new("Model")
	model.Name = id

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(4, 6, 2)
	body.Anchored = true
	body.CanCollide = true
	body.BrickColor = BrickColor.new("Really red")
	body.CFrame = spawnCFrame
	body.Parent = model

	model.PrimaryPart = body
	model.Parent = parent

	local attackIds = {}
	for attackId in def.attacks do
		table.insert(attackIds, attackId)
	end

	local self = setmetatable({
		id = id,
		def = def,
		attackIds = attackIds,
		state = "Idle",
		health = def.hp,
		model = model,
		parent = parent,
		pendingAttackId = nil,
		telegraphResolveTime = nil,
		parriedThisAttack = false,
		spawnCFrame = spawnCFrame,
		deathCallbacks = {},
	}, Enemy)

	task.spawn(function()
		self:_runLoop()
	end)

	return self
end

function Enemy:_setState(newState)
	self.state = newState
	stateChangedRemote:FireAllClients(self.id, newState, self.health)
end

function Enemy:_beginTelegraph(attackId, attack)
	self.pendingAttackId = attackId
	self.parriedThisAttack = false
	self.telegraphResolveTime = os.clock() + attack.telegraphDuration
	self:_setState("Telegraph")
	telegraphRemote:FireAllClients(self.id, attackId, attack.telegraphDuration, attack.parryable)
end

function Enemy:_resolveAttack(attack)
	if self.parriedThisAttack then
		return
	end

	local primaryPart = self.model.PrimaryPart
	if primaryPart == nil then
		return
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart == nil then
			continue
		end

		local distance = (rootPart.Position - primaryPart.Position).Magnitude
		if distance <= attack.range then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health -= attack.damage
			end
			playerHitRemote:FireClient(player, attack.damage, self.id)

			if attack.dot then
				self:_applyDot(player, attack.dot)
			end
		end
	end
end

-- Ticks `dot.tickDamage` every `dot.tickInterval` for `dot.ticks`, independent
-- of the enemy's own state (the enemy can die, respawn, or start a new
-- attack while a player is still bleeding from this one). Stops early if the
-- player leaves or their character is gone.
function Enemy:_applyDot(player, dot)
	task.spawn(function()
		for _ = 1, dot.ticks do
			task.wait(dot.tickInterval)

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid == nil or humanoid.Health <= 0 then
				return
			end

			humanoid.Health -= dot.tickDamage
			playerHitRemote:FireClient(player, dot.tickDamage, self.id)
		end
	end)
end

function Enemy:_applyDamage(amount, killer)
	self.health = math.max(0, self.health - amount)

	if self.health <= 0 then
		self:_die(killer)
	else
		stateChangedRemote:FireAllClients(self.id, self.state, self.health)
	end
end

-- Callbacks run every time this enemy dies, in registration order, each
-- receiving the player who landed the killing blow (nil if it died without
-- one). Two independent listeners exist now — the guarded chest unlocking
-- and the kill payout — so this is a list rather than the single slot it
-- started as.
function Enemy:OnDeath(callback)
	table.insert(self.deathCallbacks, callback)
end

function Enemy:_die(killer)
	self.health = 0
	self:_setState("Dead")
	self.model.Parent = nil

	for _, callback in self.deathCallbacks do
		callback(killer)
	end
end

function Enemy:_respawn()
	self.health = self.def.hp
	self.model:PivotTo(self.spawnCFrame)
	self.model.Parent = self.parent
end

-- Called by CombatServer once it has already checked the attacker's swing
-- cooldown; `weaponDef` carries the damage this swing deals.
function Enemy:TryAttack(player, weaponDef)
	if self.state == "Dead" then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local primaryPart = self.model.PrimaryPart
	if rootPart == nil or primaryPart == nil then
		return
	end

	local distance = (rootPart.Position - primaryPart.Position).Magnitude
	if distance > weaponDef.swingRange then
		return
	end

	local damage = weaponDef.baseDamage
	if self.state == "Staggered" then
		damage *= CombatConstants.STAGGER_DAMAGE_MULTIPLIER
	end

	self:_applyDamage(damage, player)
end

-- Validated using server receipt time minus half the player's round-trip
-- ping, not the client's own clock — client and server os.clock() aren't
-- synchronized, so a client-supplied timestamp can't be compared directly
-- against the server's telegraphResolveTime. `parryWindow` is the equipped
-- weapon's own window (Tank wide, Assassin tight — see WeaponDefs). Returns
-- whether the parry actually succeeded, so callers can react to it (e.g. a
-- Healer's parry-triggered burst heal — see CombatServer.luau).
function Enemy:TryParry(player, parryWindow)
	if self.state ~= "Telegraph" or self.telegraphResolveTime == nil then
		return false
	end

	local pendingAttack = self.def.attacks[self.pendingAttackId]
	if pendingAttack == nil or not pendingAttack.parryable then
		return false
	end

	local halfPing = player:GetNetworkPing() / 2
	local perceivedTime = os.clock() - halfPing
	local delta = math.abs(perceivedTime - self.telegraphResolveTime)

	if delta <= parryWindow then
		self.parriedThisAttack = true
		return true
	end

	return false
end

function Enemy:_runLoop()
	while true do
		if self.state == "Dead" then
			task.wait(CombatConstants.ENEMY_RESPAWN_DELAY)
			self:_respawn()
		end

		self:_setState("Idle")
		task.wait(CombatConstants.IDLE_DURATION)
		if self.state == "Dead" then
			continue
		end

		local attackId = self.attackIds[math.random(#self.attackIds)]
		local attack = self.def.attacks[attackId]
		self:_beginTelegraph(attackId, attack)

		local elapsed = 0
		while elapsed < attack.telegraphDuration and not self.parriedThisAttack and self.state ~= "Dead" do
			local step = math.min(CombatConstants.TELEGRAPH_POLL_INTERVAL, attack.telegraphDuration - elapsed)
			task.wait(step)
			elapsed += step
		end
		if self.state == "Dead" then
			continue
		end

		self:_resolveAttack(attack)
		if self.state == "Dead" then
			continue
		end

		if self.parriedThisAttack then
			self:_setState("Staggered")
			task.wait(CombatConstants.STAGGER_DURATION)
		else
			self:_setState("Recover")
			task.wait(CombatConstants.RECOVER_DURATION)
		end
	end
end

return Enemy
