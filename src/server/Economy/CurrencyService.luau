-- The only place currency state lives, mirroring EquipService/InventoryService.
-- In-memory only — resets on rejoin until DataStore persistence lands in build
-- order step 10.
--
-- Two currencies, per DESIGN.md: coins drop from every kill, crystals only from
-- enemies whose EnemyDefs entry sets crystalReward. Crystals are keyed by class
-- id (Tank/Assassin/Healer) and you earn the class you were *playing* when the
-- kill landed — so switching weapon doesn't carry your upgrade materials over,
-- which is where respeccing's "real cost" actually comes from.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyDefs = require(Shared:WaitForChild("EnemyDefs"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local EquipService = require(script.Parent.Parent.EquipService)

local currencyUpdatedRemote = Remotes.Get(Remotes.Names.CurrencyUpdated)

local CurrencyService = {}

local balances = {}

local function getBalance(player)
	local balance = balances[player]
	if balance == nil then
		balance = { coins = 0, crystals = {} }
		balances[player] = balance
	end

	return balance
end

local function publish(player, balance)
	currencyUpdatedRemote:FireClient(player, balance.coins, balance.crystals)
end

function CurrencyService.GetBalance(player)
	return getBalance(player)
end

-- Spends only if the player can afford the whole cost — never partially.
-- `crystalType` is a class id; `crystals` of 0 means coins-only (the lower
-- blacksmith tiers), in which case crystalType is irrelevant.
function CurrencyService.TrySpend(player, coins, crystalType, crystals)
	local balance = getBalance(player)
	local heldCrystals = balance.crystals[crystalType] or 0

	if balance.coins < coins or heldCrystals < crystals then
		return false
	end

	balance.coins -= coins
	if crystals > 0 then
		balance.crystals[crystalType] = heldCrystals - crystals
	end

	publish(player, balance)
	return true
end

-- Pays out that enemy's EnemyDefs reward to whoever lands the killing blow.
-- Registered per enemy by DungeonGenerator, alongside its chest.
function CurrencyService.TrackEnemy(enemy, enemyType)
	local def = EnemyDefs[enemyType]

	enemy:OnDeath(function(killer)
		if killer == nil then
			return
		end

		local balance = getBalance(killer)
		balance.coins += def.coinReward

		if def.crystalReward > 0 then
			local weaponDef = EquipService.GetWeapon(killer)
			if weaponDef ~= nil then
				local crystalType = weaponDef.class
				balance.crystals[crystalType] = (balance.crystals[crystalType] or 0) + def.crystalReward
			end
		end

		publish(killer, balance)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	balances[player] = nil
end)

return CurrencyService
