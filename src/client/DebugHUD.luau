--!strict
-- The instrument the vertical slice exists to provide.
--
-- Tuning parry windows by feel alone is guesswork — "that felt late" is not a
-- number you can move a constant by. This surfaces the millisecond delta on
-- every attempt, next to the ping that explains it, so the constants in
-- CombatConstants can be moved on evidence.
--
-- Replaced by real UI at build-order step 10.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConstants = require(Shared.CombatConstants)
local ParryMath = require(Shared.ParryMath)
local Remotes = require(Shared.Remotes)
local WeaponDefs = require(Shared.WeaponDefs)

local DebugHUD = {}

local SLICE_WEAPON = "SwordAndShield"

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
	attackId: string?,
	impactTime: number,
	parryable: boolean,
	stamina: number,
	staminaAt: number,
	lastVerdict: string?,
	lastDeltaMs: number,
}

local state: State = {
	attackId = nil,
	impactTime = 0,
	parryable = true,
	stamina = CombatConstants.MAX_STAMINA,
	staminaAt = 0,
	lastVerdict = nil,
	lastDeltaMs = 0,
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
	frame.Size = UDim2.fromOffset(330, 190)
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

	local attackLabel = makeLabel(frame, 1, 15)
	local countdownLabel = makeLabel(frame, 2, 15)
	local windowLabel = makeLabel(frame, 3, 13)
	local staminaLabel = makeLabel(frame, 4, 13)
	local pingLabel = makeLabel(frame, 5, 13)
	local resultLabel = makeLabel(frame, 6, 20)

	local profile = WeaponDefs[SLICE_WEAPON].parry

	Remotes.get("EnemyTelegraphStart").OnClientEvent:Connect(function(payload)
		state.attackId = payload.attackId
		state.impactTime = payload.impactTime
		state.parryable = payload.parryable
	end)

	Remotes.get("ParryResult").OnClientEvent:Connect(function(payload)
		state.lastVerdict = payload.verdict
		state.lastDeltaMs = payload.deltaMs
		-- Authoritative value; the readout predicts forward from here.
		state.stamina = payload.stamina
		state.staminaAt = Workspace:GetServerTimeNow()
	end)

	Remotes.get("EnemyStaggered").OnClientEvent:Connect(function()
		state.attackId = nil
	end)

	Remotes.get("PlayerHit").OnClientEvent:Connect(function(payload)
		resultLabel.Text = `HIT  -{payload.amount}`
		resultLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	end)

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()

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
				"window   %+.0f ms .. %+.0f ms",
				-profile.earlyTolerance * 1000,
				profile.lateTolerance * 1000
			)
		else
			attackLabel.Text = "attack   idle"
			attackLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			countdownLabel.Text = "impact   --"
			windowLabel.Text = ""
		end

		local predicted = ParryMath.regenerateStamina(state.stamina, now - state.staminaAt)
		staminaLabel.Text = string.format(
			"stamina  %d / %d   (parry costs %d)",
			math.floor(predicted),
			CombatConstants.MAX_STAMINA,
			CombatConstants.PARRY_STAMINA_COST
		)

		-- Ping is here because it explains late verdicts and bounds how much of
		-- STRIKE_RESOLUTION_GRACE a real player actually gets to use.
		local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		pingLabel.Text = string.format("ping     %.0f ms", ping)

		if state.lastVerdict then
			resultLabel.Text = string.format("%s  %+.0f ms", string.upper(state.lastVerdict), state.lastDeltaMs)
			resultLabel.TextColor3 = VERDICT_COLORS[state.lastVerdict] or Color3.fromRGB(235, 235, 235)
		else
			resultLabel.Text = "press F to parry"
			resultLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end)
end

return DebugHUD
