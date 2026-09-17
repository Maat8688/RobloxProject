--!strict
-- The instrument the combat work exists to provide.
--
-- Tuning parry windows by feel alone is guesswork — "that felt late" is not a
-- number you can move a constant by. This surfaces the millisecond delta on
-- every attempt, next to the ping that explains it, so the constants in
-- CombatConstants and WeaponDefs can be moved on evidence.
--
-- The target readout mirrors the server's rule exactly — ParryMath's
-- selectParryTarget over attacks within reach — because a HUD highlighting a
-- different attack than the one a parry will resolve against would actively
-- mislead a tuning session.
--
-- Replaced by real UI at build-order step 10.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConstants = require(Shared.CombatConstants)
local DamageMath = require(Shared.DamageMath)
local EnemyDefs = require(Shared.EnemyDefs)
local Loadout = require(Shared.Loadout)
local ParryMath = require(Shared.ParryMath)
local Remotes = require(Shared.Remotes)

local DebugHUD = {}

-- A strike resolves at impact plus the grace period; past this the telegraph
-- is certainly over, whatever happened to it.
local TELEGRAPH_EXPIRY = CombatConstants.STRIKE_RESOLUTION_GRACE + 0.5

local GREY = Color3.fromRGB(150, 150, 150)
local WHITE = Color3.fromRGB(235, 235, 235)
local ORANGE = Color3.fromRGB(255, 140, 60)

local VERDICT_COLORS: { [string]: Color3 } = {
	parried = Color3.fromRGB(120, 230, 140),
	early = Color3.fromRGB(240, 200, 100),
	late = Color3.fromRGB(240, 200, 100),
	unparryable = ORANGE,
	no_attack = Color3.fromRGB(180, 180, 180),
	exhausted = Color3.fromRGB(180, 180, 180),
	recovering = Color3.fromRGB(180, 180, 180),
	unequipped = Color3.fromRGB(180, 180, 180),
	rejected_future = Color3.fromRGB(255, 90, 90),
	rejected_stale = Color3.fromRGB(255, 90, 90),
}

type Telegraph = {
	attackId: string,
	impactTime: number,
	parryable: boolean,
	root: BasePart?,
	reach: number,
}

type EnemyInfo = {
	alive: boolean,
}

type State = {
	weaponId: string?,
	classTag: string?,
	telegraphs: { [string]: Telegraph },
	enemies: { [string]: EnemyInfo },
	stamina: number,
	staminaAt: number,
	riposteUntil: number,
	lastVerdict: string?,
	lastDeltaMs: number,
	lastParryTarget: string?,
	lastSwing: string?,
}

local state: State = {
	weaponId = nil,
	classTag = nil,
	telegraphs = {},
	enemies = {},
	stamina = CombatConstants.MAX_STAMINA,
	staminaAt = 0,
	riposteUntil = 0,
	lastVerdict = nil,
	lastDeltaMs = 0,
	lastParryTarget = nil,
	lastSwing = nil,
}

local function makeLabel(parent: Instance, order: number, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.TextColor3 = WHITE
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

-- Server-side EnemyAI tags every enemy model with this.
local ENEMY_TAG = "Enemy"

local function findEnemyModel(enemyId: string): Model?
	for _, tagged in CollectionService:GetTagged(ENEMY_TAG) do
		if tagged:IsA("Model") and tagged:GetAttribute("EnemyId") == enemyId then
			return tagged
		end
	end

	return nil
end

local function reachOf(model: Model, attackId: string): number
	local defId = model:GetAttribute("EnemyDefId")
	local def = if typeof(defId) == "string" then EnemyDefs[defId] else nil
	local attack = def and def.attacks[attackId]
	-- Unknown attack: don't filter it out, since hiding a real threat is worse
	-- than over-showing one.
	if not attack then
		return math.huge
	end

	return attack.range + CombatConstants.PARRY_RANGE_MARGIN
end

-- Same candidates and same rule the server uses for a press made right now.
local function currentTarget(now: number): (string?, Telegraph?)
	local character = Players.LocalPlayer.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local candidates: { ParryMath.ParryCandidate } = {}

	for enemyId, telegraph in state.telegraphs do
		local enemyRoot = telegraph.root
		local distance: number? = nil
		if myRoot and enemyRoot then
			distance = DamageMath.horizontalDistance(
				{ x = myRoot.Position.X, z = myRoot.Position.Z },
				{ x = enemyRoot.Position.X, z = enemyRoot.Position.Z }
			)
		end

		table.insert(candidates, {
			enemyId = enemyId,
			impactTime = telegraph.impactTime,
			parryable = telegraph.parryable,
			distance = distance,
			reach = telegraph.reach,
		})
	end

	local best = ParryMath.selectParryTarget(candidates, now)
	if not best then
		return nil, nil
	end

	return best.enemyId, state.telegraphs[best.enemyId]
end

function DebugHUD.start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatDebugHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(420, 250)
	frame.Position = UDim2.fromOffset(16, 16)
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame

	local classLabel = makeLabel(frame, 1, 15)
	local targetLabel = makeLabel(frame, 2, 15)
	local countdownLabel = makeLabel(frame, 3, 15)
	local windowLabel = makeLabel(frame, 4, 13)
	local staminaLabel = makeLabel(frame, 5, 13)
	local roomLabel = makeLabel(frame, 6, 13)
	local pingLabel = makeLabel(frame, 7, 13)
	local swingLabel = makeLabel(frame, 8, 14)
	local resultLabel = makeLabel(frame, 9, 20)

	Remotes.get("WeaponEquipped").OnClientEvent:Connect(function(payload)
		state.weaponId = payload.weaponId
		state.classTag = payload.classTag
	end)

	Remotes.get("EnemyTelegraphStart").OnClientEvent:Connect(function(payload)
		local model = findEnemyModel(payload.enemyId)
		state.telegraphs[payload.enemyId] = {
			attackId = payload.attackId,
			impactTime = payload.impactTime,
			parryable = payload.parryable,
			root = model and model.PrimaryPart,
			reach = if model then reachOf(model, payload.attackId) else math.huge,
		}
	end)

	Remotes.get("ParryResult").OnClientEvent:Connect(function(payload)
		state.lastVerdict = payload.verdict
		state.lastDeltaMs = payload.deltaMs
		state.lastParryTarget = payload.enemyId
		-- Authoritative values; the readout predicts forward from here.
		state.stamina = payload.stamina
		state.staminaAt = Workspace:GetServerTimeNow()
		state.riposteUntil = payload.riposteUntil or 0
	end)

	Remotes.get("EnemyStaggered").OnClientEvent:Connect(function(payload)
		state.telegraphs[payload.enemyId] = nil
	end)

	Remotes.get("EnemyHealthChanged").OnClientEvent:Connect(function(payload)
		state.enemies[payload.enemyId] = { alive = payload.alive }
		if not payload.alive then
			state.telegraphs[payload.enemyId] = nil
		end
	end)

	Remotes.get("AttackResult").OnClientEvent:Connect(function(payload)
		if payload.hit then
			state.lastSwing = string.format("hit %.1f%s", payload.damage, if payload.riposte then "  RIPOSTE" else "")
		else
			state.lastSwing = payload.reason
		end
	end)

	Remotes.get("PlayerHit").OnClientEvent:Connect(function(payload)
		resultLabel.Text = string.format("%s  -%.0f", if payload.bleed then "BLEED" else "HIT", payload.amount)
		resultLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	end)

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()

		-- A strike that landed unparried sends no event of its own, so expire
		-- telegraphs by time rather than leaving them to pile up.
		for enemyId, telegraph in state.telegraphs do
			if now > telegraph.impactTime + TELEGRAPH_EXPIRY then
				state.telegraphs[enemyId] = nil
			end
		end

		local weaponId = state.weaponId
		local weapon = if weaponId then Loadout.getDef(weaponId) else nil

		if weapon then
			local hint = if RunService:IsStudio() then "   [1/2/3]" else ""
			classLabel.Text = `class    {state.classTag}  ({weapon.displayName}){hint}`
			classLabel.TextColor3 = WHITE
		else
			classLabel.Text = "class    none — pick a weapon from a stand"
			classLabel.TextColor3 = ORANGE
		end

		local targetId, telegraph = currentTarget(now)
		if targetId and telegraph then
			local kind = if telegraph.parryable then "PARRYABLE" else "UNPARRYABLE"
			targetLabel.Text = `target   {targetId}  {telegraph.attackId}  [{kind}]`
			targetLabel.TextColor3 = if telegraph.parryable then WHITE else ORANGE
			countdownLabel.Text = string.format("impact   %+.0f ms", (telegraph.impactTime - now) * 1000)
		else
			targetLabel.Text = "target   none in reach"
			targetLabel.TextColor3 = GREY
			countdownLabel.Text = "impact   --"
		end

		if weapon then
			local profile = weapon.parry
			windowLabel.Text = string.format(
				"window   %+.0f ms .. %+.0f ms   (%.0f ms wide)",
				-profile.earlyTolerance * 1000,
				profile.lateTolerance * 1000,
				(profile.earlyTolerance + profile.lateTolerance) * 1000
			)
		else
			windowLabel.Text = "window   --"
		end

		local predicted = ParryMath.regenerateStamina(state.stamina, now - state.staminaAt)
		staminaLabel.Text = string.format(
			"stamina  %d / %d   (parry %d, swing %s)",
			math.floor(predicted),
			CombatConstants.MAX_STAMINA,
			CombatConstants.PARRY_STAMINA_COST,
			if weapon then tostring(weapon.attack.staminaCost) else "--"
		)

		local alive, total, winding = 0, 0, 0
		for _, info in state.enemies do
			total += 1
			if info.alive then
				alive += 1
			end
		end
		for _ in state.telegraphs do
			winding += 1
		end
		roomLabel.Text = string.format("dungeon  %d/%d alive   %d winding up", alive, total, winding)

		-- Ping explains late verdicts, and sets how wide a timestamp band the
		-- server will believe (ParryMath.plausibleSendWindow).
		local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		pingLabel.Text = string.format("ping     %.0f ms", ping)

		local riposteRemaining = state.riposteUntil - now
		if riposteRemaining > 0 then
			swingLabel.Text = string.format("swing    %s   RIPOSTE %.1fs", state.lastSwing or "--", riposteRemaining)
			swingLabel.TextColor3 = Color3.fromRGB(255, 200, 120)
		else
			swingLabel.Text = `swing    {state.lastSwing or "--"}`
			swingLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
		end

		if state.lastVerdict then
			local against = if state.lastParryTarget then `  vs {state.lastParryTarget}` else ""
			resultLabel.Text = string.format(
				"%s  %+.0f ms%s",
				string.upper(state.lastVerdict),
				state.lastDeltaMs,
				against
			)
			resultLabel.TextColor3 = VERDICT_COLORS[state.lastVerdict] or WHITE
		else
			resultLabel.Text = "F parry / click attack / I inventory"
			resultLabel.TextColor3 = GREY
		end
	end)
end

return DebugHUD
