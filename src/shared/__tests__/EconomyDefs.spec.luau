--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConstants = require(Shared.CombatConstants)
local EconomyDefs = require(Shared.EconomyDefs)

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("EconomyDefs.getUpgradeCost", function()
	it("scales coin cost triangularly", function()
		local costs = {}
		for level = 0, EconomyDefs.MAX_UPGRADE_LEVEL - 1 do
			table.insert(costs, EconomyDefs.getUpgradeCost(level).coins)
		end

		expect(costs).toEqual({ 50, 150, 300, 500, 750 })
	end)

	it("charges no crystals up to the threshold", function()
		for level = 0, EconomyDefs.CRYSTAL_TIER_THRESHOLD - 1 do
			expect(EconomyDefs.getUpgradeCost(level).crystals).toBe(0)
		end
	end)

	-- The mechanism behind "trash-mob grinding alone can't reach max gear".
	it("charges crystals for every tier past the threshold", function()
		for level = EconomyDefs.CRYSTAL_TIER_THRESHOLD, EconomyDefs.MAX_UPGRADE_LEVEL - 1 do
			expect(EconomyDefs.getUpgradeCost(level).crystals > 0).toBe(true)
		end
	end)

	it("never gets cheaper as levels rise", function()
		for level = 1, EconomyDefs.MAX_UPGRADE_LEVEL - 1 do
			local previous = EconomyDefs.getUpgradeCost(level - 1)
			local current = EconomyDefs.getUpgradeCost(level)
			expect(current.coins >= previous.coins).toBe(true)
			expect(current.crystals >= previous.crystals).toBe(true)
		end
	end)
end)

describe("EconomyDefs.upgradedDamage", function()
	it("leaves damage untouched at level 0", function()
		expect(EconomyDefs.upgradedDamage(12, 0)).toBe(12)
	end)

	it("adds the per-level bonus", function()
		expect(EconomyDefs.upgradedDamage(10, 3)).toBeCloseTo(13, 9)
	end)

	-- The value is computed, not stored, so repeated calls can't compound.
	it("does not compound across calls", function()
		EconomyDefs.upgradedDamage(10, 5)
		expect(EconomyDefs.upgradedDamage(10, 5)).toBeCloseTo(15, 9)
	end)
end)

describe("Economy vs skill", function()
	-- DESIGN.md: "skill must count as much as level/gear". A fully upgraded
	-- weapon has to stay below what landing a parry is worth, or grinding
	-- beats timing.
	it("keeps the max upgrade below the stagger punish bonus", function()
		local maxUpgradeMultiplier = EconomyDefs.upgradedDamage(1, EconomyDefs.MAX_UPGRADE_LEVEL)
		expect(maxUpgradeMultiplier < CombatConstants.STAGGER_DAMAGE_MULTIPLIER).toBe(true)
	end)
end)
