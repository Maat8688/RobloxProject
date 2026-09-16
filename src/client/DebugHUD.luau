--!strict
-- The instrument the combat work exists to provide.
--
-- Tuning parry windows by feel alone is guesswork — "that felt late" is not a
-- number you can move a constant by. This surfaces the millisecond delta on
-- every attempt, next to the ping that explains it, so the constants in
-- CombatConstants and WeaponDefs can be moved on evidence.
--
-- With several enemies winding up at once, the readout tracks the SAME attack
-- the server would resolve a parry against — nearest impact to now, mirroring
-- ParryMath.selectParryTarget. A HUD that highlighted a different enemy than
-- the one the parry will hit would actively mislead a tuning session.
--
-- Replaced by real UI at build-order step 10.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConstants = require(Shared.CombatConstants)
local Loadout = require(Shared.Loadout)
local ParryMath = require(Shared.ParryMath)
local Remotes = require(Shared.Remotes)

local DebugHUD = {}

local VERDICT_COLORS: { [string]: Color3 } = {
	parried = Color3.fromRGB(120, 230, 140),
	early = Color3.fromRGB(240, 200, 100),
	late = Color3.fromRGB(240, 200, 100),
	unparryable = Color3.fromRGB(255, 140, 60),
	no_attack = Color3.fromRGB(180, 180, 180),
	exhausted = Color3.fromRGB(180, 180, 180),
	recovering = Color3.fromRGB(180, 180, 180),
	rejected_future = Color3.fromRGB(255, 90, 90),
	rejected_stale = Color3.fromRGB(255, 90, 90),
}

type Telegraph = {
	attackId: string,
	impactTime: number,
	parryable: boolean,
}

type EnemyInfo = {
	health: number,
	maxHealth: number,
	alive: boolean,
}

type State = {
	weaponId: string,
	classTag: string,
	telegraphs: { [string]: Telegraph },
	enemies: { [string]: EnemyInfo },
	stamina: number,
	staminaAt: number,
	riposteUntil: number,
	lastVerdict: string?,
	lastDeltaMs: number,
	lastParryEnemy: string?,
	lastSwing: string?,
}

local state: State = {
	weaponId = Loadout.DEFAULT_WEAPON,
	classTag = Loadout.classOf(Loadout.DEFAULT_WEAPON),
	telegraphs = {},
	enemies = {},
	stamina = CombatConstants.MAX_STAMINA,
	staminaAt = 0,
	riposteUntil = 0,
	lastVerdict = nil,
	lastDeltaMs = 0,
	lastParryEnemy = nil,
	lastSwing = nil,
}

local function makeLabel(parent: Instance, order: number, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

-- Same rule the server uses to pick a parry target, so the HUD and the
-- authority never disagree about what you're about to parry.
local function soonestTelegraph(now: number): (string?, Telegraph?)
	local candidates: { ParryMath.ParryCandidate } = {}
	for enemyId, telegraph in state.telegraphs do
		table.insert(candidates, {
			enemyId = enemyId,
			impactTime = telegraph.impactTime,
			parryable = telegraph.parryable,
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
	frame.Size = UDim2.fromOffset(400, 250)
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
		state.telegraphs[payload.enemyId] = {
			attackId = payload.attackId,
			impactTime = payload.impactTime,
			parryable = payload.parryable,
		}
	end)

	Remotes.get("ParryResult").OnClientEvent:Connect(function(payload)
		state.lastVerdict = payload.verdict
		state.lastDeltaMs = payload.deltaMs
		state.lastParryEnemy = payload.enemyId
		-- Authoritative values; the readout predicts forward from here.
		state.stamina = payload.stamina
		state.staminaAt = Workspace:GetServerTimeNow()
		state.riposteUntil = payload.riposteUntil or 0
	end)

	Remotes.get("EnemyStaggered").OnClientEvent:Connect(function(payload)
		state.telegraphs[payload.enemyId] = nil
	end)

	Remotes.get("EnemyHealthChanged").OnClientEvent:Connect(function(payload)
		state.enemies[payload.enemyId] = {
			health = payload.health,
			maxHealth = payload.maxHealth,
			alive = payload.alive,
		}

		if not payload.alive then
			state.telegraphs[payload.enemyId] = nil
		end
	end)

	Remotes.get("AttackResult").OnClientEvent:Connect(function(payload)
		if payload.hit then
			state.lastSwing = string.format(
				"hit %d%s",
				payload.damage,
				if payload.riposte then "  RIPOSTE" else ""
			)
		else
			state.lastSwing = payload.reason
		end
	end)

	Remotes.get("PlayerHit").OnClientEvent:Connect(function(payload)
		resultLabel.Text = `HIT  -{payload.amount}`
		resultLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	end)

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		local weapon = Loadout.getDef(state.weaponId)
		local profile = weapon.parry

		classLabel.Text = `class    {state.classTag}  ({weapon.displayName})   [1/2/3]`

		local targetId, telegraph = soonestTelegraph(now)

		if targetId and telegraph then
			local kind = if telegraph.parryable then "PARRYABLE" else "UNPARRYABLE"
			targetLabel.Text = `target   {targetId}  {telegraph.attackId}  [{kind}]`
			targetLabel.TextColor3 = if telegraph.parryable
				then Color3.fromRGB(235, 235, 235)
				else Color3.fromRGB(255, 140, 60)

			local remaining = (telegraph.impactTime - now) * 1000
			countdownLabel.Text = string.format("impact   %+.0f ms", remaining)
		else
			targetLabel.Text = "target   none incoming"
			targetLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			countdownLabel.Text = "impact   --"
		end

		-- Absolute bounds of the window, so you can see exactly where the
		-- press needed to land relative to the countdown above.
		windowLabel.Text = string.format(
			"window   %+.0f ms .. %+.0f ms   (%.0f ms wide)",
			-profile.earlyTolerance * 1000,
			profile.lateTolerance * 1000,
			(profile.earlyTolerance + profile.lateTolerance) * 1000
		)

		local predicted = ParryMath.regenerateStamina(state.stamina, now - state.staminaAt)
		staminaLabel.Text = string.format(
			"stamina  %d / %d   (parry %d, swing %d)",
			math.floor(predicted),
			CombatConstants.MAX_STAMINA,
			CombatConstants.PARRY_STAMINA_COST,
			weapon.attack.staminaCost
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
		roomLabel.Text = string.format("room     %d/%d alive   %d winding up", alive, total, winding)

		-- Ping is here because it explains late verdicts and bounds how much of
		-- STRIKE_RESOLUTION_GRACE a real player actually gets to use.
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
			local against = if state.lastParryEnemy then `  vs {state.lastParryEnemy}` else ""
			resultLabel.Text = string.format(
				"%s  %+.0f ms%s",
				string.upper(state.lastVerdict),
				state.lastDeltaMs,
				against
			)
			resultLabel.TextColor3 = VERDICT_COLORS[state.lastVerdict] or Color3.fromRGB(235, 235, 235)
		else
			resultLabel.Text = "F parry / click attack"
			resultLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end)
end

return DebugHUD
