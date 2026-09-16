--!strict
-- The instrument the combat work exists to provide.
--
-- Tuning parry windows by feel alone is guesswork — "that felt late" is not a
-- number you can move a constant by. This surfaces the millisecond delta on
-- every attempt, next to the ping that explains it, so the constants in
-- CombatConstants and WeaponDefs can be moved on evidence.
--
-- The window readout follows the equipped weapon, which is the fastest way to
-- feel how far apart the Tank and Assassin profiles actually are.
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

type State = {
	weaponId: string,
	classTag: string,
	attackId: string?,
	impactTime: number,
	parryable: boolean,
	stamina: number,
	staminaAt: number,
	riposteUntil: number,
	lastVerdict: string?,
	lastDeltaMs: number,
	enemyHealth: number,
	enemyMaxHealth: number,
	lastSwing: string?,
}

local state: State = {
	weaponId = Loadout.DEFAULT_WEAPON,
	classTag = Loadout.classOf(Loadout.DEFAULT_WEAPON),
	attackId = nil,
	impactTime = 0,
	parryable = true,
	stamina = CombatConstants.MAX_STAMINA,
	staminaAt = 0,
	riposteUntil = 0,
	lastVerdict = nil,
	lastDeltaMs = 0,
	enemyHealth = 0,
	enemyMaxHealth = 0,
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

function DebugHUD.start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatDebugHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(360, 250)
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
	local attackLabel = makeLabel(frame, 2, 15)
	local countdownLabel = makeLabel(frame, 3, 15)
	local windowLabel = makeLabel(frame, 4, 13)
	local staminaLabel = makeLabel(frame, 5, 13)
	local enemyLabel = makeLabel(frame, 6, 13)
	local pingLabel = makeLabel(frame, 7, 13)
	local swingLabel = makeLabel(frame, 8, 14)
	local resultLabel = makeLabel(frame, 9, 20)

	Remotes.get("WeaponEquipped").OnClientEvent:Connect(function(payload)
		state.weaponId = payload.weaponId
		state.classTag = payload.classTag
	end)

	Remotes.get("EnemyTelegraphStart").OnClientEvent:Connect(function(payload)
		state.attackId = payload.attackId
		state.impactTime = payload.impactTime
		state.parryable = payload.parryable
	end)

	Remotes.get("ParryResult").OnClientEvent:Connect(function(payload)
		state.lastVerdict = payload.verdict
		state.lastDeltaMs = payload.deltaMs
		-- Authoritative values; the readout predicts forward from here.
		state.stamina = payload.stamina
		state.staminaAt = Workspace:GetServerTimeNow()
		state.riposteUntil = payload.riposteUntil or 0
	end)

	Remotes.get("EnemyStaggered").OnClientEvent:Connect(function()
		state.attackId = nil
	end)

	Remotes.get("EnemyHealthChanged").OnClientEvent:Connect(function(payload)
		state.enemyHealth = payload.health
		state.enemyMaxHealth = payload.maxHealth
		if not payload.alive then
			state.attackId = nil
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

		if state.attackId then
			local kind = if state.parryable then "PARRYABLE" else "UNPARRYABLE"
			attackLabel.Text = `attack   {state.attackId}  [{kind}]`
			attackLabel.TextColor3 = if state.parryable
				then Color3.fromRGB(235, 235, 235)
				else Color3.fromRGB(255, 140, 60)

			local remaining = (state.impactTime - now) * 1000
			countdownLabel.Text = string.format("impact   %+.0f ms", remaining)

			-- Absolute bounds of the window, so you can see exactly where the
			-- press needed to land relative to the countdown above.
			windowLabel.Text = string.format(
				"window   %+.0f ms .. %+.0f ms   (%.0f ms wide)",
				-profile.earlyTolerance * 1000,
				profile.lateTolerance * 1000,
				(profile.earlyTolerance + profile.lateTolerance) * 1000
			)
		else
			attackLabel.Text = "attack   idle"
			attackLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			countdownLabel.Text = "impact   --"
			windowLabel.Text = string.format(
				"window   %.0f ms wide",
				(profile.earlyTolerance + profile.lateTolerance) * 1000
			)
		end

		local predicted = ParryMath.regenerateStamina(state.stamina, now - state.staminaAt)
		staminaLabel.Text = string.format(
			"stamina  %d / %d   (parry %d, swing %d)",
			math.floor(predicted),
			CombatConstants.MAX_STAMINA,
			CombatConstants.PARRY_STAMINA_COST,
			weapon.attack.staminaCost
		)

		if state.enemyMaxHealth > 0 then
			enemyLabel.Text = string.format("enemy    %d / %d hp", state.enemyHealth, state.enemyMaxHealth)
		else
			enemyLabel.Text = "enemy    --"
		end

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
			resultLabel.Text = string.format("%s  %+.0f ms", string.upper(state.lastVerdict), state.lastDeltaMs)
			resultLabel.TextColor3 = VERDICT_COLORS[state.lastVerdict] or Color3.fromRGB(235, 235, 235)
		else
			resultLabel.Text = "F parry / click attack"
			resultLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end)
end

return DebugHUD
