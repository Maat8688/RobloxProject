-- The only place equipped-weapon state lives. Kept separate from
-- CombatServer so the weapon pickups can equip a player without reaching
-- into combat internals. In-memory only — resets on rejoin until DataStore
-- persistence lands in build order step 10.
--
-- Per-weapon upgrade levels live here too, for the same "one place" reason:
-- an upgrade is weapon state, and GetWeapon returning already-upgraded stats
-- means CombatServer never has to know the blacksmith exists. BlacksmithService
-- owns the economy side (cost, payment) and calls ApplyUpgrade once paid, so
-- the dependency only ever points blacksmith -> equip, never back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyDefs = require(Shared:WaitForChild("EconomyDefs"))
local WeaponDefs = require(Shared:WaitForChild("WeaponDefs"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local weaponEquippedRemote = Remotes.Get(Remotes.Names.WeaponEquipped)

local EquipService = {}

local equippedWeaponId = {}
local upgradeLevels = {}
local effectiveDefs = {}

-- A copy, never the shared WeaponDefs entry — scaling that table in place
-- would upgrade the weapon for every player on the server, permanently.
local function buildEffectiveDef(weaponId, level)
	local base = WeaponDefs[weaponId]
	local def = table.clone(base)
	def.upgradeLevel = level
	def.baseDamage = base.baseDamage * (1 + EconomyDefs.DAMAGE_BONUS_PER_UPGRADE_LEVEL * level)
	return def
end

function EquipService.GetUpgradeLevel(player, weaponId)
	local levels = upgradeLevels[player]
	if levels == nil then
		return 0
	end

	return levels[weaponId] or 0
end

function EquipService.SetWeapon(player, weaponId)
	if WeaponDefs[weaponId] == nil then
		return
	end

	local level = EquipService.GetUpgradeLevel(player, weaponId)
	equippedWeaponId[player] = weaponId
	effectiveDefs[player] = buildEffectiveDef(weaponId, level)
	weaponEquippedRemote:FireClient(player, weaponId, level)
end

-- Returns the player's current weapon stats with their upgrade level already
-- applied, or nil if they haven't equipped one yet.
function EquipService.GetWeapon(player)
	return effectiveDefs[player]
end

function EquipService.GetEquippedWeaponId(player)
	return equippedWeaponId[player]
end

-- Called by BlacksmithService *after* it has taken payment. Returns the new level.
function EquipService.ApplyUpgrade(player, weaponId)
	local levels = upgradeLevels[player]
	if levels == nil then
		levels = {}
		upgradeLevels[player] = levels
	end

	local newLevel = (levels[weaponId] or 0) + 1
	levels[weaponId] = newLevel

	if equippedWeaponId[player] == weaponId then
		effectiveDefs[player] = buildEffectiveDef(weaponId, newLevel)
		weaponEquippedRemote:FireClient(player, weaponId, newLevel)
	end

	return newLevel
end

Players.PlayerRemoving:Connect(function(player)
	equippedWeaponId[player] = nil
	upgradeLevels[player] = nil
	effectiveDefs[player] = nil
end)

return EquipService
