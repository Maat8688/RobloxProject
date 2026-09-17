--!strict
-- Feedback drawn in the world rather than on the screen: enemy health bars,
-- floating damage numbers, and the flash and sparks of a landed parry or hit.
--
-- Everything here is created on this client only and renders what the server
-- already reported; nothing here decides an outcome. Gray-box on purpose — no
-- uploaded assets, only Roblox's built-in defaults — until real art arrives.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local EnemyDefs = require(Shared.EnemyDefs)
local Remotes = require(Shared.Remotes)

local WorldFeedback = {}

-- Server-side EnemyAI tags every enemy model with this.
local ENEMY_TAG = "Enemy"

local BAR_WIDTH = 120
local BAR_MAX_DISTANCE = 70

local HIT_COLOR = Color3.fromRGB(255, 90, 90)
local PARRY_COLOR = Color3.fromRGB(255, 255, 255)
local RIPOSTE_COLOR = Color3.fromRGB(255, 190, 90)

type Bar = {
	gui: BillboardGui,
	fill: Frame,
}

type Health = {
	health: number,
	maxHealth: number,
	alive: boolean,
}

local bars: { [string]: Bar } = {}
-- Latest reported health, kept even for enemies whose model this client
-- doesn't have yet, so a bar can be built the moment one appears.
local healthById: { [string]: Health } = {}
local guiParent: Instance

local function findEnemyModel(enemyId: string): Model?
	for _, tagged in CollectionService:GetTagged(ENEMY_TAG) do
		if tagged:IsA("Model") and tagged:GetAttribute("EnemyId") == enemyId then
			return tagged
		end
	end

	return nil
end

--[[ Health bars ]]

local function applyHealth(bar: Bar, health: Health)
	local fraction = if health.maxHealth > 0 then math.clamp(health.health / health.maxHealth, 0, 1) else 0
	bar.fill.Size = UDim2.fromScale(fraction, 1)
	bar.gui.Enabled = health.alive
end

local function buildBar(model: Model, enemyId: string): Bar?
	local root = model.PrimaryPart
	if not root then
		return nil
	end

	local defId = model:GetAttribute("EnemyDefId")
	local def = if typeof(defId) == "string" then EnemyDefs[defId] else nil

	local gui = Instance.new("BillboardGui")
	gui.Name = `HealthBar_{enemyId}`
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(BAR_WIDTH, 30)
	gui.StudsOffset = Vector3.new(0, root.Size.Y / 2 + 1.5, 0)
	gui.MaxDistance = BAR_MAX_DISTANCE
	-- Lives under PlayerGui, which would otherwise rebuild it on every respawn.
	gui.ResetOnSpawn = false
	gui.Parent = guiParent

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 16)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.SourceSansBold
	name.TextSize = 14
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.4
	name.Text = if def then def.displayName else enemyId
	name.Parent = gui

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 8)
	track.Position = UDim2.fromOffset(0, 18)
	track.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	track.BorderSizePixel = 0
	track.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(200, 55, 55)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local bar = { gui = gui, fill = fill }
	bars[enemyId] = bar

	local health = healthById[enemyId]
	if health then
		applyHealth(bar, health)
	end

	return bar
end

local function onEnemyAdded(instance: Instance)
	if not instance:IsA("Model") then
		return
	end

	local enemyId = instance:GetAttribute("EnemyId")
	if typeof(enemyId) ~= "string" or bars[enemyId] then
		return
	end

	-- The primary part may replicate a moment after the model itself. Polled
	-- with a limit rather than awaited on a signal, so a model removed in the
	-- meantime doesn't leave this thread waiting forever.
	local waited = 0
	while not instance.PrimaryPart and instance.Parent and waited < 10 do
		waited += task.wait(0.2)
	end

	if instance.PrimaryPart and not bars[enemyId] then
		buildBar(instance, enemyId)
	end
end

local function onEnemyRemoved(instance: Instance)
	local enemyId = instance:GetAttribute("EnemyId")
	local bar = if typeof(enemyId) == "string" then bars[enemyId] else nil
	if bar then
		bar.gui:Destroy()
		bars[enemyId :: string] = nil
	end
end

--[[ Floating numbers ]]

local function floatText(root: BasePart, text: string, color: Color3, size: number)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(160, 40)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false

	-- A little sideways scatter so rapid hits don't stack into one number.
	local startOffset = Vector3.new((math.random() - 0.5) * 2, root.Size.Y / 2 + 2.5, 0)
	gui.StudsOffset = startOffset
	gui.Parent = guiParent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui

	local rise = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, rise, { StudsOffset = startOffset + Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	task.delay(0.85, function()
		gui:Destroy()
	end)
end

--[[ Flashes and sparks ]]

local function flash(model: Model, color: Color3, duration: number)
	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.25
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	-- Under the model it lights, so it can't outlive it. Still created by this
	-- client, so only this player sees it.
	highlight.Parent = model

	TweenService:Create(highlight, TweenInfo.new(duration), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	}):Play()

	task.delay(duration + 0.05, function()
		highlight:Destroy()
	end)
end

-- A one-shot burst using ParticleEmitter's built-in default texture, so no
-- asset upload is needed.
local function sparks(root: BasePart, color: Color3)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.25, 0.45)
	emitter.Speed = NumberRange.new(14, 24)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Drag = 4
	emitter.Parent = attachment

	emitter:Emit(30)

	task.delay(1, function()
		attachment:Destroy()
	end)
end

function WorldFeedback.start()
	guiParent = Players.LocalPlayer:WaitForChild("PlayerGui")

	CollectionService:GetInstanceAddedSignal(ENEMY_TAG):Connect(onEnemyAdded)
	CollectionService:GetInstanceRemovedSignal(ENEMY_TAG):Connect(onEnemyRemoved)
	for _, instance in CollectionService:GetTagged(ENEMY_TAG) do
		task.spawn(onEnemyAdded, instance)
	end

	Remotes.get("EnemyHealthChanged").OnClientEvent:Connect(function(payload)
		local health: Health = {
			health = payload.health,
			maxHealth = payload.maxHealth,
			alive = payload.alive,
		}
		healthById[payload.enemyId] = health

		local bar = bars[payload.enemyId]
		if bar then
			applyHealth(bar, health)
		end
	end)

	-- Only your own hits: AttackResult goes to the attacker alone.
	Remotes.get("AttackResult").OnClientEvent:Connect(function(payload)
		if not payload.hit or typeof(payload.enemyId) ~= "string" then
			return
		end

		local model = findEnemyModel(payload.enemyId)
		local root = model and model.PrimaryPart
		if not model or not root then
			return
		end

		local text = tostring(math.floor(payload.damage + 0.5))
		if payload.riposte then
			floatText(root, `{text}!`, RIPOSTE_COLOR, 30)
		else
			floatText(root, text, Color3.fromRGB(255, 255, 255), 24)
		end

		flash(model, HIT_COLOR, 0.15)
	end)

	-- A landed parry against an enemy: the moment the whole system is built
	-- around, so it gets the biggest reaction. A duel parry names a player
	-- rather than an enemy and finds no model here, which is fine — GameUI
	-- covers duels.
	Remotes.get("ParryResult").OnClientEvent:Connect(function(payload)
		if not payload.success or typeof(payload.enemyId) ~= "string" then
			return
		end

		local model = findEnemyModel(payload.enemyId)
		local root = model and model.PrimaryPart
		if not model or not root then
			return
		end

		sparks(root, PARRY_COLOR)
		flash(model, PARRY_COLOR, 0.3)
		floatText(root, "PARRY", PARRY_COLOR, 26)
	end)
end

return WorldFeedback
