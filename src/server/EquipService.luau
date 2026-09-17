--!strict
-- The only place equipped-weapon state lives. Kept separate from CombatServer
-- so the weapon stands and the blacksmith can equip or upgrade a player
-- without reaching into combat internals. In-memory only — resets on rejoin
-- until DataStore persistence lands in build-order step 10.
--
-- Per-weapon upgrade levels live here too, for the same one-place reason: an
-- upgrade is weapon state. BlacksmithService owns the economy side (price,
-- payment) and calls applyUpgrade once paid, so the dependency only ever
-- points blacksmith -> equip, never back.
--
-- A player's class is never stored here: it is always derived from the
-- equipped weapon through Loadout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EconomyDefs = require(Shared.EconomyDefs)
local Loadout = require(Shared.Loadout)
local Remotes = require(Shared.Remotes)

local EquipService = {}

local equipped: { [Player]: string } = {}
local upgradeLevels: { [Player]: { [string]: number } } = {}

local function publish(player: Player, weaponId: string)
	Remotes.get("WeaponEquipped"):FireClient(player, {
		weaponId = weaponId,
		classTag = Loadout.classOf(weaponId),
		upgradeLevel = EquipService.getUpgradeLevel(player, weaponId),
	})
end

-- nil until the player picks a weapon from a stand. Combat ignores an
-- unequipped player's swings and parries.
function EquipService.getWeaponId(player: Player): string?
	return equipped[player]
end

function EquipService.getUpgradeLevel(player: Player, weaponId: string): number
	local levels = upgradeLevels[player]
	if not levels then
		return 0
	end

	return levels[weaponId] or 0
end

-- Damage for this player's copy of the weapon, with their upgrades applied.
-- Computed on demand rather than stored as a scaled copy of the weapon def,
-- since those defs are shared by every player (see EconomyDefs.upgradedDamage).
function EquipService.getDamage(player: Player, weaponId: string): number
	local base = Loadout.getDef(weaponId).attack.damage
	return EconomyDefs.upgradedDamage(base, EquipService.getUpgradeLevel(player, weaponId))
end

-- Returns whether the weapon was equipped. The id is validated rather than
-- trusted, since one path into here is a client-fired debug remote.
function EquipService.setWeapon(player: Player, weaponId: unknown): boolean
	local result = Loadout.resolve(weaponId)
	if not result.ok then
		return false
	end

	local resolvedId = result.weaponId :: string
	equipped[player] = resolvedId
	publish(player, resolvedId)
	return true
end

-- Called by BlacksmithService only after it has taken payment. Returns the new
-- level. Upgrades are per weapon, so a respec back to a weapon you already
-- upgraded keeps its level.
function EquipService.applyUpgrade(player: Player, weaponId: string): number
	local levels = upgradeLevels[player]
	if not levels then
		levels = {}
		upgradeLevels[player] = levels
	end

	local newLevel = (levels[weaponId] or 0) + 1
	levels[weaponId] = newLevel

	if equipped[player] == weaponId then
		publish(player, weaponId)
	end

	return newLevel
end

Players.PlayerRemoving:Connect(function(player)
	equipped[player] = nil
	upgradeLevels[player] = nil
end)

return EquipService
