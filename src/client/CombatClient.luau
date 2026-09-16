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
local LootTables = require(Shared:WaitForChild("LootTables"))

local player = Players.LocalPlayer

local attackAttemptRemote = Remotes.Get(Remotes.Names.AttackAttempt)
local parryAttemptRemote = Remotes.Get(Remotes.Names.ParryAttempt)
local telegraphRemote = Remotes.Get(Remotes.Names.EnemyTelegraphStart)
local stateChangedRemote = Remotes.Get(Remotes.Names.EnemyStateChanged)
local playerHitRemote = Remotes.Get(Remotes.Names.PlayerHit)
local weaponEquippedRemote = Remotes.Get(Remotes.Names.WeaponEquipped)
local chestOpenedRemote = Remotes.Get(Remotes.Names.ChestOpened)
local inventoryUpdatedRemote = Remotes.Get(Remotes.Names.InventoryUpdated)
local currencyUpdatedRemote = Remotes.Get(Remotes.Names.CurrencyUpdated)
local upgradeResultRemote = Remotes.Get(Remotes.Names.UpgradeResult)
local healBurstRemote = Remotes.Get(Remotes.Names.HealBurst)
local pvpStatusRemote = Remotes.Get(Remotes.Names.PvPStatusChanged)
local pvpTelegraphRemote = Remotes.Get(Remotes.Names.PvPTelegraphStart)
local pvpParryResultRemote = Remotes.Get(Remotes.Names.PvPParryResult)
local pvpHealthRemote = Remotes.Get(Remotes.Names.PvPHealthChanged)

-- itemId -> display name, looked up from the same shared LootTables the
-- server built the ItemInstance from (ItemInstance itself has no name field).
local ITEM_NAMES = {}
for _, descriptor in LootTables do
	ITEM_NAMES[descriptor.itemId] = descriptor.name
end

local WEAPON_DISPLAY_NAMES = {
	Tank = "Sword & Shield",
	Assassin = "Daggers",
	Healer = "Staff",
}

local STATE_COLORS = {
	Idle = Color3.fromRGB(150, 40, 40),
	Telegraph = Color3.fromRGB(255, 230, 60), -- blockable — time a parry
	TelegraphUnparryable = Color3.fromRGB(255, 80, 0), -- must-dodge AoE — parrying won't help
	Staggered = Color3.fromRGB(255, 255, 255),
	Recover = Color3.fromRGB(150, 40, 40),
	Dead = Color3.fromRGB(60, 60, 60),
}

local function getEnemyBody(enemyId)
	local model = Workspace:FindFirstChild(enemyId)
	return model and model:FindFirstChild("Body")
end

telegraphRemote.OnClientEvent:Connect(function(enemyId, _attackId, _duration, parryable)
	local body = getEnemyBody(enemyId)
	if body then
		body.Color = parryable and STATE_COLORS.Telegraph or STATE_COLORS.TelegraphUnparryable
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

local healFlash = Instance.new("Frame")
healFlash.Size = UDim2.fromScale(1, 1)
healFlash.BackgroundColor3 = Color3.fromRGB(0, 200, 80)
healFlash.BackgroundTransparency = 1
healFlash.ZIndex = 10
healFlash.Parent = screenGui

healBurstRemote.OnClientEvent:Connect(function()
	healFlash.BackgroundTransparency = 0.7
	TweenService:Create(healFlash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end)

local weaponLabel = Instance.new("TextLabel")
weaponLabel.Size = UDim2.fromOffset(220, 30)
weaponLabel.Position = UDim2.fromOffset(10, 10)
weaponLabel.BackgroundTransparency = 0.4
weaponLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
weaponLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
weaponLabel.Font = Enum.Font.SourceSansBold
weaponLabel.TextSize = 18
weaponLabel.Text = "Weapon: none — find a pickup"
weaponLabel.Parent = screenGui

weaponEquippedRemote.OnClientEvent:Connect(function(weaponId, upgradeLevel)
	local text = "Weapon: " .. (WEAPON_DISPLAY_NAMES[weaponId] or weaponId)
	if upgradeLevel > 0 then
		text ..= " +" .. upgradeLevel
	end
	weaponLabel.Text = text
end)

local currencyLabel = Instance.new("TextLabel")
currencyLabel.Size = UDim2.fromOffset(220, 24)
currencyLabel.Position = UDim2.fromOffset(10, 44)
currencyLabel.BackgroundTransparency = 0.4
currencyLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
currencyLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
currencyLabel.Font = Enum.Font.SourceSansBold
currencyLabel.TextSize = 16
currencyLabel.Text = "0 coins"
currencyLabel.Parent = screenGui

-- Only the crystal types the player actually holds are listed, so an
-- untouched class never shows as "0" clutter.
currencyUpdatedRemote.OnClientEvent:Connect(function(coins, crystals)
	local text = string.format("%d coins", coins)
	for crystalType, amount in crystals do
		if amount > 0 then
			text ..= string.format(" | %d %s", amount, crystalType)
		end
	end
	currencyLabel.Text = text
end)

local upgradeLabel = Instance.new("TextLabel")
upgradeLabel.Size = UDim2.fromOffset(360, 30)
upgradeLabel.Position = UDim2.new(0.5, -180, 0, 95)
upgradeLabel.BackgroundTransparency = 1
upgradeLabel.TextTransparency = 1
upgradeLabel.Font = Enum.Font.SourceSansBold
upgradeLabel.TextSize = 20
upgradeLabel.TextWrapped = true
upgradeLabel.Parent = screenGui

upgradeResultRemote.OnClientEvent:Connect(function(success, reason, newLevel)
	if success then
		upgradeLabel.Text = "Weapon upgraded to +" .. newLevel
		upgradeLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
	else
		upgradeLabel.Text = reason
		upgradeLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	end

	upgradeLabel.TextTransparency = 0
	TweenService:Create(upgradeLabel, TweenInfo.new(3), { TextTransparency = 1 }):Play()
end)

local lootLabel = Instance.new("TextLabel")
lootLabel.Size = UDim2.fromOffset(360, 40)
lootLabel.Position = UDim2.new(0.5, -180, 0, 50)
lootLabel.BackgroundTransparency = 1
lootLabel.TextTransparency = 1
lootLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
lootLabel.Font = Enum.Font.SourceSansBold
lootLabel.TextSize = 20
lootLabel.TextWrapped = true
lootLabel.Parent = screenGui

chestOpenedRemote.OnClientEvent:Connect(function(_chestId, loot)
	local item = loot[1]
	if item == nil then
		return
	end

	lootLabel.Text = "Found: " .. item.name .. " — " .. item.flavor
	lootLabel.TextTransparency = 0
	TweenService:Create(lootLabel, TweenInfo.new(3), { TextTransparency = 1 }):Play()
end)

local inventoryFrame = Instance.new("Frame")
inventoryFrame.Size = UDim2.fromOffset(260, 300)
inventoryFrame.Position = UDim2.new(1, -270, 0, 10)
inventoryFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
inventoryFrame.BackgroundTransparency = 0.3
inventoryFrame.Visible = false
inventoryFrame.Parent = screenGui

local inventoryTitle = Instance.new("TextLabel")
inventoryTitle.Size = UDim2.new(1, 0, 0, 30)
inventoryTitle.BackgroundTransparency = 1
inventoryTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
inventoryTitle.Font = Enum.Font.SourceSansBold
inventoryTitle.TextSize = 20
inventoryTitle.Text = "Inventory (I)"
inventoryTitle.Parent = inventoryFrame

local inventoryList = Instance.new("Frame")
inventoryList.Size = UDim2.new(1, 0, 1, -30)
inventoryList.Position = UDim2.fromOffset(0, 30)
inventoryList.BackgroundTransparency = 1
inventoryList.Parent = inventoryFrame

local inventoryLayout = Instance.new("UIListLayout")
inventoryLayout.Parent = inventoryList

inventoryUpdatedRemote.OnClientEvent:Connect(function(items)
	for _, child in inventoryList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	for _, item in items do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 24)
		row.BackgroundTransparency = 1
		row.TextColor3 = Color3.fromRGB(255, 255, 255)
		row.Font = Enum.Font.SourceSans
		row.TextSize = 16
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = (ITEM_NAMES[item.itemId] or item.itemId) .. " (" .. item.rarity .. ")"
		row.Parent = inventoryList
	end
end)

-- PvP (build order step 9): status/HP are persistent while relevant, the
-- telegraph/parry-result lines are transient flashes like upgradeLabel above.
local pvpStatusLabel = Instance.new("TextLabel")
pvpStatusLabel.Size = UDim2.fromOffset(260, 24)
pvpStatusLabel.Position = UDim2.fromOffset(10, 74)
pvpStatusLabel.BackgroundTransparency = 0.4
pvpStatusLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
pvpStatusLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
pvpStatusLabel.Font = Enum.Font.SourceSansBold
pvpStatusLabel.TextSize = 16
pvpStatusLabel.Visible = false
pvpStatusLabel.Parent = screenGui

local pvpHealthLabel = Instance.new("TextLabel")
pvpHealthLabel.Size = UDim2.fromOffset(260, 24)
pvpHealthLabel.Position = UDim2.fromOffset(10, 100)
pvpHealthLabel.BackgroundTransparency = 0.4
pvpHealthLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
pvpHealthLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
pvpHealthLabel.Font = Enum.Font.SourceSansBold
pvpHealthLabel.TextSize = 16
pvpHealthLabel.Visible = false
pvpHealthLabel.Parent = screenGui

local pvpFlashLabel = Instance.new("TextLabel")
pvpFlashLabel.Size = UDim2.new(0.5, 0, 0, 30)
pvpFlashLabel.Position = UDim2.new(0.25, 0, 0, 140)
pvpFlashLabel.BackgroundTransparency = 1
pvpFlashLabel.TextTransparency = 1
pvpFlashLabel.Font = Enum.Font.SourceSansBold
pvpFlashLabel.TextSize = 22
pvpFlashLabel.TextWrapped = true
pvpFlashLabel.Parent = screenGui

local function flashPvPMessage(text, color)
	pvpFlashLabel.Text = text
	pvpFlashLabel.TextColor3 = color
	pvpFlashLabel.TextTransparency = 0
	TweenService:Create(pvpFlashLabel, TweenInfo.new(2), { TextTransparency = 1 }):Play()
end

pvpStatusRemote.OnClientEvent:Connect(function(status, opponentName, resultMessage)
	if status == "queued" then
		pvpStatusLabel.Text = "Queued for duel..."
		pvpStatusLabel.Visible = true
		pvpHealthLabel.Visible = false
	elseif status == "dueling" then
		pvpStatusLabel.Text = "Dueling: " .. (opponentName or "?")
		pvpStatusLabel.Visible = true
	else
		pvpStatusLabel.Visible = false
		pvpHealthLabel.Visible = false
	end

	if resultMessage then
		flashPvPMessage(resultMessage, Color3.fromRGB(200, 200, 255))
	end
end)

pvpHealthRemote.OnClientEvent:Connect(function(yourHealth, opponentHealth)
	pvpHealthLabel.Text = string.format("You: %d | Opponent: %d", yourHealth, opponentHealth)
	pvpHealthLabel.Visible = true
end)

pvpTelegraphRemote.OnClientEvent:Connect(function(attackerName, _duration)
	flashPvPMessage(attackerName .. " is attacking — parry!", Color3.fromRGB(255, 230, 60))
end)

pvpParryResultRemote.OnClientEvent:Connect(function(success, message)
	flashPvPMessage(message, success and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 120, 120))
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		attackAttemptRemote:FireServer(os.clock())
	elseif input.KeyCode == Enum.KeyCode.F then
		parryAttemptRemote:FireServer(os.clock())
	elseif input.KeyCode == Enum.KeyCode.I then
		inventoryFrame.Visible = not inventoryFrame.Visible
	end
end)

return true
