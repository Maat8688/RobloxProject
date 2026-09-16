--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DamageMath = require(Shared.DamageMath)

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ORIGIN: DamageMath.Vec2 = { x = 0, z = 0 }
-- Facing +Z, matching how the slice orients the enemy toward the player spawn.
local FACING_NORTH: DamageMath.Vec2 = { x = 0, z = 1 }

describe("DamageMath.resolveIncoming", function()
	it("passes full damage through when not parried", function()
		expect(DamageMath.resolveIncoming(15, false)).toBe(15)
	end)

	it("fully negates damage on a parry", function()
		expect(DamageMath.resolveIncoming(15, true)).toBe(0)
	end)
end)

describe("DamageMath.resolveOutgoing", function()
	it("passes base damage through with no riposte", function()
		expect(DamageMath.resolveOutgoing(6, false, 2.5)).toBe(6)
	end)

	it("amplifies damage during a riposte window", function()
		expect(DamageMath.resolveOutgoing(6, true, 2.5)).toBe(15)
	end)

	-- Classes without a riposte payoff carry a multiplier of 1, so an active
	-- flag must still be a no-op for them.
	it("is a no-op for a class whose multiplier is 1", function()
		expect(DamageMath.resolveOutgoing(12, true, 1)).toBe(12)
	end)
end)

describe("DamageMath.staggerDuration", function()
	it("scales the base stagger by the class multiplier", function()
		expect(DamageMath.staggerDuration(1.5, 1.5)).toBeCloseTo(2.25, 6)
		expect(DamageMath.staggerDuration(1.5, 0.8)).toBeCloseTo(1.2, 6)
	end)

	it("leaves the base untouched at a multiplier of 1", function()
		expect(DamageMath.staggerDuration(1.5, 1)).toBe(1.5)
	end)
end)

describe("DamageMath.applyHealing", function()
	it("heals up to but not past the maximum", function()
		expect(DamageMath.applyHealing(80, 100, 14)).toBe(94)
		expect(DamageMath.applyHealing(95, 100, 14)).toBe(100)
	end)

	it("never returns a negative health value", function()
		expect(DamageMath.applyHealing(5, 100, -50)).toBe(0)
	end)
end)

describe("DamageMath.isInHitVolume range", function()
	local function hitAt(x: number, z: number, range: number, arcDegrees: number): boolean
		return DamageMath.isInHitVolume({
			attackerPos = ORIGIN,
			attackerFacing = FACING_NORTH,
			targetPos = { x = x, z = z },
			range = range,
			arcDegrees = arcDegrees,
		})
	end

	it("hits a target inside range and directly ahead", function()
		expect(hitAt(0, 5, 10, 120)).toBe(true)
	end)

	it("misses a target beyond range", function()
		expect(hitAt(0, 11, 10, 120)).toBe(false)
	end)

	it("includes a target exactly at maximum range", function()
		expect(hitAt(0, 10, 10, 120)).toBe(true)
	end)

	-- Height is ignored on purpose: the slice's room is flat, and a jumping
	-- player should not dodge a sword swing for free.
	it("hits a target standing on top of the attacker", function()
		expect(hitAt(0, 0, 10, 120)).toBe(true)
	end)
end)

describe("DamageMath.isInHitVolume arc", function()
	local function hitAt(x: number, z: number, arcDegrees: number): boolean
		return DamageMath.isInHitVolume({
			attackerPos = ORIGIN,
			attackerFacing = FACING_NORTH,
			targetPos = { x = x, z = z },
			range = 100,
			arcDegrees = arcDegrees,
		})
	end

	it("misses a target directly behind within a frontal arc", function()
		expect(hitAt(0, -5, 120)).toBe(false)
	end)

	it("hits a target at the edge of the arc", function()
		-- 120 degree arc is +/-60 from facing; this target sits at exactly 60.
		expect(hitAt(math.sin(math.rad(60)) * 5, math.cos(math.rad(60)) * 5, 120)).toBe(true)
	end)

	it("misses a target just outside the arc", function()
		expect(hitAt(math.sin(math.rad(61)) * 5, math.cos(math.rad(61)) * 5, 120)).toBe(false)
	end)

	it("is symmetric on both sides of the facing direction", function()
		expect(hitAt(3, 3, 120)).toBe(hitAt(-3, 3, 120))
	end)

	-- The GroundSlam attack relies on this: no amount of repositioning dodges
	-- it, only leaving its range does.
	it("hits in every direction with a 360 degree arc", function()
		expect(hitAt(0, -5, 360)).toBe(true)
		expect(hitAt(5, 0, 360)).toBe(true)
		expect(hitAt(0, 5, 360)).toBe(true)
	end)
end)
