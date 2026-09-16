-- One enemy instance: spawns its body in Workspace and runs its own
-- Idle -> Telegraph -> (Staggered | Recover) -> Idle loop. Generalizing this
-- into a shared EnemyAI across enemy types is build order step 3 — for the
-- vertical slice there's exactly one of these.

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

function Enemy.new(id, def, spawnCFrame)
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
	model.Parent = Workspace

	local self = setmetatable({
		id = id,
		def = def,
		state = "Idle",
		health = def.hp,
		model = model,
		pendingAttackId = nil,
		telegraphResolveTime = nil,
		parriedThisAttack = false,
		spawnCFrame = spawnCFrame,
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
	telegraphRemote:FireAllClients(self.id, attackId, attack.telegraphDuration)
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
		if distance <= CombatConstants.ENEMY_ENGAGE_RANGE then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health -= attack.damage
			end
			playerHitRemote:FireClient(player, attack.damage, self.id)
		end
	end
end

function Enemy:_applyDamage(amount)
	self.health = math.max(0, self.health - amount)

	if self.health <= 0 then
		self:_die()
	else
		stateChangedRemote:FireAllClients(self.id, self.state, self.health)
	end
end

function Enemy:_die()
	self.health = 0
	self:_setState("Dead")
	self.model.Parent = nil
end

function Enemy:_respawn()
	self.health = self.def.hp
	self.model:PivotTo(self.spawnCFrame)
	self.model.Parent = Workspace
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
	if distance > CombatConstants.SWING_RANGE then
		return
	end

	local damage = weaponDef.baseDamage
	if self.state == "Staggered" then
		damage *= CombatConstants.STAGGER_DAMAGE_MULTIPLIER
	end

	self:_applyDamage(damage)
end

-- Validated using server receipt time minus half the player's round-trip
-- ping, not the client's own clock — client and server os.clock() aren't
-- synchronized, so a client-supplied timestamp can't be compared directly
-- against the server's telegraphResolveTime.
function Enemy:TryParry(player)
	if self.state ~= "Telegraph" or self.telegraphResolveTime == nil then
		return
	end

	local halfPing = player:GetNetworkPing() / 2
	local perceivedTime = os.clock() - halfPing
	local delta = math.abs(perceivedTime - self.telegraphResolveTime)

	if delta <= CombatConstants.PARRY_WINDOW then
		self.parriedThisAttack = true
	end
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

		local attackId = "Swing"
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
