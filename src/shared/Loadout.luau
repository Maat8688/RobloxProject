--!strict
-- Weapon equipping, and the derivation of class from weapon.
-- Pure Luau — no Roblox API, no player state held here.
--
-- Exists so "class = equipped weapon" has exactly one implementation. Anything
-- wanting a player's class asks for their weapon's classTag through here
-- rather than storing a class of its own, which is what stops the two from
-- ever drifting apart.

local WeaponDefs = require(script.Parent.WeaponDefs)

local Loadout = {}

-- There is deliberately no default weapon. Players start unequipped in the safe
-- start room and pick one from the weapon stands, which is the first step of
-- DESIGN.md's core loop ("choose a weapon at start").

export type EquipResult = {
	ok: boolean,
	weaponId: string?,
	classTag: string?,
	reason: string?,
}

-- Equip requests can originate on the client (the Studio-only debug hotkeys),
-- so the id is treated as untrusted input and checked against the definition
-- table rather than assumed valid.
function Loadout.resolve(weaponId: unknown): EquipResult
	if type(weaponId) ~= "string" then
		return { ok = false, reason = "invalid_weapon" }
	end

	local def = WeaponDefs[weaponId]
	if not def then
		return { ok = false, reason = "unknown_weapon" }
	end

	return { ok = true, weaponId = weaponId, classTag = def.classTag }
end

function Loadout.getDef(weaponId: string): WeaponDefs.WeaponDef
	local def = WeaponDefs[weaponId]
	assert(def, `No weapon def for "{weaponId}"`)
	return def
end

function Loadout.classOf(weaponId: string): string
	return Loadout.getDef(weaponId).classTag
end

-- Stable, sorted list so the debug keybinds and any future UI agree on order
-- regardless of table iteration order.
function Loadout.allWeaponIds(): { string }
	local ids = {}
	for weaponId in WeaponDefs do
		table.insert(ids, weaponId)
	end
	table.sort(ids)
	return ids
end

return Loadout
