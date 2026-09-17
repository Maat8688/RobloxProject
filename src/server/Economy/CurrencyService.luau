--!strict
-- The only place currency state lives, mirroring EquipService and
-- InventoryService. In-memory only — resets on rejoin until DataStore
-- persistence lands in build-order step 10.
--
-- Two currencies (DESIGN.md): coins drop from every kill, crystals only from
-- enemies whose EnemyDefs entry sets crystalReward. Crystals are keyed by
-- class, and you earn the class you were *playing* when the kill landed — so
-- switching weapon doesn't carry your upgrade materials across. That is where
-- respeccing's real cost comes from.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Loadout = require(Shared.Loadout)
local Remotes = require(Shared.Remotes)

local EnemyAI = require(script.Parent.Parent.Combat.EnemyAI)
local EquipService = require(script.Parent.Parent.EquipService)

local CurrencyService = {}

export type Balance = {
	coins: number,
	-- classTag -> count
	crystals: { [string]: number },
}

local balances: { [Player]: Balance } = {}

local function getBalance(player: Player): Balance
	local balance = balances[player]
	if not balance then
		balance = { coins = 0, crystals = {} }
		balances[player] = balance
	end

	return balance
end

local function publish(player: Player, balance: Balance)
	Remotes.get("CurrencyUpdated"):FireClient(player, {
		coins = balance.coins,
		crystals = balance.crystals,
	})
end

function CurrencyService.getBalance(player: Player): Balance
	return getBalance(player)
end

-- Spends only if the player can afford the whole cost — never partially.
-- `crystalClass` is irrelevant when `crystals` is 0 (the coin-only tiers).
function CurrencyService.trySpend(player: Player, coins: number, crystalClass: string, crystals: number): boolean
	local balance = getBalance(player)
	local heldCrystals = balance.crystals[crystalClass] or 0

	if balance.coins < coins or heldCrystals < crystals then
		return false
	end

	balance.coins -= coins
	if crystals > 0 then
		balance.crystals[crystalClass] = heldCrystals - crystals
	end

	publish(player, balance)
	return true
end

-- Pays out an enemy's EnemyDefs reward to whoever lands the killing blow, every
-- time it dies. Registered per enemy by DungeonGenerator, alongside its chest.
function CurrencyService.trackEnemy(enemy: EnemyAI.Enemy)
	local def = enemy.def

	EnemyAI.onDeath(enemy, function(killer)
		if not killer or not killer.Parent then
			return
		end

		local balance = getBalance(killer)
		balance.coins += def.coinReward

		if def.crystalReward > 0 then
			local weaponId = EquipService.getWeaponId(killer)
			if weaponId then
				local class = Loadout.classOf(weaponId)
				balance.crystals[class] = (balance.crystals[class] or 0) + def.crystalReward
			end
		end

		publish(killer, balance)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	balances[player] = nil
end)

return CurrencyService
