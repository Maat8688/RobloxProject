--!strict
-- Player-facing feedback: damage and heal flashes, equipped weapon, currency,
-- loot and upgrade messages, the inventory panel (I), and duel status.
--
-- Separate from DebugHUD on purpose. DebugHUD is a tuning instrument that
-- goes away at build-order step 10; this is the game's actual UI, kept as
-- plain labels until then. It renders what the server reports and never
-- computes an outcome itself.
--
-- Laid out to stay clear of DebugHUD, which owns the top-left corner.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local LootTables = require(Shared.LootTables)
local Loadout = require(Shared.Loadout)
local Remotes = require(Shared.Remotes)

local GameUI = {}

local INVENTORY_ACTION = "ToggleInventory"

local GOLD = Color3.fromRGB(255, 215, 0)
local GOOD = Color3.fromRGB(120, 255, 120)
local BAD = Color3.fromRGB(255, 120, 120)
local DUEL = Color3.fromRGB(200, 200, 255)

-- itemId -> display name, from the same shared LootTables the server built the
-- item from (an ItemInstance carries no name of its own).
local ITEM_NAMES: { [string]: string } = {}
for _, descriptor in LootTables do
	ITEM_NAMES[descriptor.itemId] = descriptor.name
end

local function makeLabel(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = textSize
	label.Parent = parent
	return label
end

-- A transparent label that fades in with a message and back out.
local function makeFlashLabel(parent: Instance, position: UDim2): (string, Color3, number) -> ()
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(420, 32)
	label.Position = position
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundTransparency = 1
	label.TextTransparency = 1
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 20
	label.TextWrapped = true
	label.Parent = parent

	return function(text: string, color: Color3, seconds: number)
		label.Text = text
		label.TextColor3 = color
		label.TextTransparency = 0
		TweenService:Create(label, TweenInfo.new(seconds), { TextTransparency = 1 }):Play()
	end
end

local function makeScreenFlash(parent: Instance, color: Color3): (number) -> ()
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1
	frame.ZIndex = 10
	frame.Parent = parent

	return function(strength: number)
		frame.BackgroundTransparency = 1 - strength
		TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	end
end

local function buildInventory(parent: Instance): (Frame, Frame)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(260, 300)
	panel.Position = UDim2.new(1, -276, 0, 16)
	panel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	panel.BackgroundTransparency = 0.3
	panel.Visible = false
	panel.Parent = parent

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 20
	title.Text = "Inventory (I)"
	title.Parent = panel

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -16, 1, -34)
	list.Position = UDim2.fromOffset(8, 30)
	list.BackgroundTransparency = 1
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Parent = list

	return panel, list
end

function GameUI.start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "GameUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local flashDamage = makeScreenFlash(gui, Color3.fromRGB(200, 0, 0))
	local flashHeal = makeScreenFlash(gui, Color3.fromRGB(0, 200, 80))

	-- Bottom-left status stack.
	local weaponLabel = makeLabel(gui, UDim2.fromOffset(260, 30), UDim2.new(0, 16, 1, -120), 18)
	weaponLabel.Text = "Weapon: none — pick one from a stand"

	local currencyLabel = makeLabel(gui, UDim2.fromOffset(260, 24), UDim2.new(0, 16, 1, -86), 16)
	currencyLabel.TextColor3 = GOLD
	currencyLabel.Text = "0 coins"

	local duelStatusLabel = makeLabel(gui, UDim2.fromOffset(260, 24), UDim2.new(0, 16, 1, -58), 16)
	duelStatusLabel.TextColor3 = DUEL
	duelStatusLabel.Visible = false

	local duelHealthLabel = makeLabel(gui, UDim2.fromOffset(260, 24), UDim2.new(0, 16, 1, -30), 16)
	duelHealthLabel.Visible = false

	-- Top-centre transient messages.
	local flashLoot = makeFlashLabel(gui, UDim2.new(0.5, 0, 0, 50))
	local flashUpgrade = makeFlashLabel(gui, UDim2.new(0.5, 0, 0, 90))
	local flashDuel = makeFlashLabel(gui, UDim2.new(0.5, 0, 0, 130))

	local inventoryPanel, inventoryList = buildInventory(gui)

	Remotes.get("PlayerHit").OnClientEvent:Connect(function(payload)
		-- Bleed ticks flash softer than the hit that caused them.
		flashDamage(if payload.bleed then 0.2 else 0.4)
	end)

	Remotes.get("HealBurst").OnClientEvent:Connect(function()
		flashHeal(0.3)
	end)

	Remotes.get("WeaponEquipped").OnClientEvent:Connect(function(payload)
		local def = Loadout.getDef(payload.weaponId)
		local text = `Weapon: {def.displayName} ({payload.classTag})`
		if payload.upgradeLevel > 0 then
			text ..= ` +{payload.upgradeLevel}`
		end
		weaponLabel.Text = text
	end)

	-- Only crystal types the player actually holds are listed, so an untouched
	-- class never shows up as "0" clutter.
	Remotes.get("CurrencyUpdated").OnClientEvent:Connect(function(payload)
		local text = string.format("%d coins", payload.coins)
		for class, amount in payload.crystals do
			if amount > 0 then
				text ..= string.format(" | %d %s", amount, class)
			end
		end
		currencyLabel.Text = text
	end)

	Remotes.get("UpgradeResult").OnClientEvent:Connect(function(payload)
		if payload.success then
			flashUpgrade(`Weapon upgraded to +{payload.newLevel}`, GOOD, 3)
		else
			flashUpgrade(payload.reason or "Upgrade failed", BAD, 3)
		end
	end)

	Remotes.get("ChestOpened").OnClientEvent:Connect(function(payload)
		local item = payload.loot[1]
		if item then
			flashLoot(`Found: {item.name} — {item.flavor}`, GOLD, 3)
		end
	end)

	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(payload)
		for _, child in inventoryList:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		for _, item in payload.items do
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 24)
			row.BackgroundTransparency = 1
			row.TextColor3 = Color3.fromRGB(255, 255, 255)
			row.Font = Enum.Font.SourceSans
			row.TextSize = 16
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Text = `{ITEM_NAMES[item.itemId] or item.itemId} ({item.rarity})`
			row.Parent = inventoryList
		end
	end)

	Remotes.get("PvPStatusChanged").OnClientEvent:Connect(function(payload)
		if payload.status == "queued" then
			duelStatusLabel.Text = "Queued for duel…"
			duelStatusLabel.Visible = true
			duelHealthLabel.Visible = false
		elseif payload.status == "dueling" then
			duelStatusLabel.Text = `Dueling: {payload.opponentName or "?"}`
			duelStatusLabel.Visible = true
		else
			duelStatusLabel.Visible = false
			duelHealthLabel.Visible = false
		end

		if payload.message then
			flashDuel(payload.message, DUEL, 2)
		end
	end)

	Remotes.get("PvPHealthChanged").OnClientEvent:Connect(function(payload)
		duelHealthLabel.Text = string.format("You: %d | Opponent: %d", payload.yours, payload.opponent)
		duelHealthLabel.Visible = true
	end)

	Remotes.get("PvPTelegraphStart").OnClientEvent:Connect(function(payload)
		flashDuel(`{payload.attackerName} is attacking — parry!`, Color3.fromRGB(255, 230, 60), payload.duration)
	end)

	Remotes.get("PvPParryResult").OnClientEvent:Connect(function(payload)
		flashDuel(payload.message, if payload.success then GOOD else BAD, 2)
	end)

	ContextActionService:BindAction(INVENTORY_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			inventoryPanel.Visible = not inventoryPanel.Visible
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.I)
end

return GameUI
