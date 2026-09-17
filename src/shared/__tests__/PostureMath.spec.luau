--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConstants = require(Shared.CombatConstants)
local PostureMath = require(Shared.PostureMath)

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local DELAY = CombatConstants.POSTURE_REGEN_DELAY
local RATE = CombatConstants.POSTURE_REGEN_PER_SECOND

describe("PostureMath.regenerate", function()
	it("holds during the delay after taking posture damage", function()
		expect(PostureMath.regenerate(50, 10, 10, 10 + DELAY)).toBe(50)
	end)

	it("drains at the configured rate after the delay", function()
		expect(PostureMath.regenerate(50, 10, 10, 10 + DELAY + 1)).toBeCloseTo(50 - RATE)
	end)

	it("never drains below zero", function()
		expect(PostureMath.regenerate(10, 0, 0, 100)).toBe(0)
	end)

	-- Posture read and re-stored mid-drain must continue from where it was,
	-- not drain the same time twice.
	it("drains only from the last update once past the delay", function()
		local midway = PostureMath.regenerate(80, 0, 0, DELAY + 1)
		expect(PostureMath.regenerate(midway, DELAY + 1, 0, DELAY + 2)).toBeCloseTo(80 - 2 * RATE)
	end)
end)

describe("PostureMath.block", function()
	it("fills posture by the blocked damage", function()
		local result = PostureMath.block(0, 10)
		expect(result.broken).toBe(false)
		expect(result.posture).toBeCloseTo(10 * CombatConstants.BLOCK_POSTURE_PER_DAMAGE)
	end)

	it("breaks and empties when full", function()
		expect(PostureMath.block(CombatConstants.MAX_POSTURE - 1, 10)).toEqual({ posture = 0, broken = true })
	end)

	-- A guard should survive a couple of ordinary hits: blocking is a real
	-- option, just not a permanent one.
	it("takes more than one typical enemy hit to break a fresh guard", function()
		expect(PostureMath.block(0, 18).broken).toBe(false)
	end)
end)

describe("PostureMath.afterParry", function()
	it("restores posture, down to zero", function()
		expect(PostureMath.afterParry(60)).toBe(60 - CombatConstants.PARRY_POSTURE_RESTORE)
		expect(PostureMath.afterParry(5)).toBe(0)
	end)
end)
