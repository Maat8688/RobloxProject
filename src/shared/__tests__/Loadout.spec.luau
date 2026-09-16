--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loadout = require(Shared.Loadout)
local WeaponDefs = require(Shared.WeaponDefs)

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("Loadout.resolve", function()
	it("accepts a known weapon and returns its class", function()
		local result = Loadout.resolve("Daggers")
		expect(result.ok).toBe(true)
		expect(result.weaponId).toBe("Daggers")
		expect(result.classTag).toBe("Assassin")
	end)

	-- Weapon ids arrive from the client, so these are the anti-tamper cases.
	it("rejects an unknown weapon id", function()
		local result = Loadout.resolve("Excalibur")
		expect(result.ok).toBe(false)
		expect(result.reason).toBe("unknown_weapon")
	end)

	it("rejects a non-string payload", function()
		expect(Loadout.resolve(42).reason).toBe("invalid_weapon")
		expect(Loadout.resolve(nil).reason).toBe("invalid_weapon")
		expect(Loadout.resolve({}).reason).toBe("invalid_weapon")
	end)
end)

describe("Loadout class derivation", function()
	it("derives class from the weapon, never stored separately", function()
		expect(Loadout.classOf("SwordAndShield")).toBe("Tank")
		expect(Loadout.classOf("Daggers")).toBe("Assassin")
		expect(Loadout.classOf("Staff")).toBe("Healer")
	end)

	it("has a valid default weapon", function()
		expect(WeaponDefs[Loadout.DEFAULT_WEAPON]).never.toBeNil()
	end)

	it("lists every defined weapon in stable order", function()
		local ids = Loadout.allWeaponIds()
		local count = 0
		for _ in WeaponDefs do
			count += 1
		end

		expect(#ids).toBe(count)
		-- Sorted, so debug keybinds map to the same weapon every session.
		expect(ids).toEqual({ "Daggers", "Staff", "SwordAndShield" })
	end)
end)

describe("WeaponDefs invariants", function()
	-- These guard the design rather than the code: DESIGN.md ties class
	-- identity and skill expression to these fields, so a weapon missing one
	-- is a design bug, not just a nil index.
	it("gives every weapon a class, a parry profile and an attack profile", function()
		for weaponId, def in WeaponDefs do
			expect(def.classTag).never.toBeNil()
			expect(def.parry.earlyTolerance > 0).toBe(true)
			expect(def.parry.lateTolerance > 0).toBe(true)
			expect(def.attack.damage > 0).toBe(true)
			expect(def.attack.staminaCost > 0).toBe(true)
			expect(typeof(weaponId)).toBe("string")
		end
	end)

	it("keeps the early half of every window wider than the late half", function()
		-- Players anticipate the hit, so pressing early is the common honest
		-- mistake; this asymmetry is deliberate and applies to every class.
		for _, def in WeaponDefs do
			expect(def.parry.earlyTolerance > def.parry.lateTolerance).toBe(true)
		end
	end)

	it("gives the Assassin a tighter window than the Tank", function()
		local tank = WeaponDefs.SwordAndShield.parry
		local assassin = WeaponDefs.Daggers.parry
		local tankWidth = tank.earlyTolerance + tank.lateTolerance
		local assassinWidth = assassin.earlyTolerance + assassin.lateTolerance

		expect(assassinWidth < tankWidth).toBe(true)
	end)

	-- "Skill must count as much as level/gear": every class needs its parry to
	-- buy something, or parrying becomes optional for that class.
	it("gives every class a non-trivial parry payoff", function()
		for _, def in WeaponDefs do
			local payoff = def.payoff
			local hasPayoff = payoff.staggerMultiplier > 1
				or payoff.selfHeal > 0
				or payoff.riposteDuration > 0
			expect(hasPayoff).toBe(true)
		end
	end)
end)
