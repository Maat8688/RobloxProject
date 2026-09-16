-- Input capture (M1 = attack, F = parry) and combat feedback. Server is the
-- sole authority on outcomes; this module only sends intent and renders what
-- the server tells it happened. Simple color flashes for now — no VFX budget
-- until this loop feels right.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local attackAttemptRemote = Remotes.Get(Remotes.Names.AttackAttempt)
local parryAttemptRemote = Remotes.Get(Remotes.Names.ParryAttempt)
local telegraphRemote = Remotes.Get(Remotes.Names.EnemyTelegraphStart)
local stateChangedRemote = Remotes.Get(Remotes.Names.EnemyStateChanged)
local playerHitRemote = Remotes.Get(Remotes.Names.PlayerHit)

local STATE_COLORS = {
	Idle = Color3.fromRGB(150, 40, 40),
	Telegraph = Color3.fromRGB(255, 230, 60),
	Staggered = Color3.fromRGB(255, 255, 255),
	Recover = Color3.fromRGB(150, 40, 40),
	Dead = Color3.fromRGB(60, 60, 60),
}

local function getEnemyBody(enemyId)
	local model = Workspace:FindFirstChild(enemyId)
	return model and model:FindFirstChild("Body")
end

telegraphRemote.OnClientEvent:Connect(function(enemyId)
	local body = getEnemyBody(enemyId)
	if body then
		body.Color = STATE_COLORS.Telegraph
	end
end)

stateChangedRemote.OnClientEvent:Connect(function(enemyId, state)
	local body = getEnemyBody(enemyId)
	if body then
		body.Color = STATE_COLORS[state] or STATE_COLORS.Idle
	end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CombatFeedback"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local damageFlash = Instance.new("Frame")
damageFlash.Size = UDim2.fromScale(1, 1)
damageFlash.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
damageFlash.BackgroundTransparency = 1
damageFlash.ZIndex = 10
damageFlash.Parent = screenGui

playerHitRemote.OnClientEvent:Connect(function()
	damageFlash.BackgroundTransparency = 0.6
	TweenService:Create(damageFlash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		attackAttemptRemote:FireServer(os.clock())
	elseif input.KeyCode == Enum.KeyCode.F then
		parryAttemptRemote:FireServer(os.clock())
	end
end)

return true
