--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AttackSelector = require(Shared.AttackSelector)
local EnemyDefs = require(Shared.EnemyDefs)

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local NOW = 100.0

local DUMMY = EnemyDefs.TrainingDummy
local SHAMBLER = EnemyDefs.Shambler
local SPITTER = EnemyDefs.Spitter

describe("AttackSelector.movementIntent", function()
	it("ignores a player beyond aggro range", function()
		expect(AttackSelector.movementIntent(SHAMBLER, SHAMBLER.aggroRange + 1)).toBe("idle")
	end)

	it("holds when the enemy cannot move", function()
		-- The dummy is the one enemy that never repositions, so parry timing
		-- can be measured without chasing anything.
		expect(AttackSelector.movementIntent(DUMMY, 30)).toBe("hold")
	end)

	it("approaches when further than preferred range", function()
		expect(AttackSelector.movementIntent(SHAMBLER, SHAMBLER.preferredRange + 10)).toBe("approach")
	end)

	-- This is what makes the Spitter kite without any kiting-specific code:
	-- its preferredRange simply sits outside its own melee.
	it("retreats when closer than preferred range", function()
		expect(AttackSelector.movementIntent(SPITTER, 5)).toBe("retreat")
	end)

	it("holds inside the dead band rather than shuffling", function()
		expect(AttackSelector.movementIntent(SHAMBLER, SHAMBLER.preferredRange)).toBe("hold")
		expect(AttackSelector.movementIntent(SHAMBLER, SHAMBLER.preferredRange + 1)).toBe("hold")
		expect(AttackSelector.movementIntent(SHAMBLER, SHAMBLER.preferredRange - 1)).toBe("hold")
	end)
end)

describe("AttackSelector.legalAttacks", function()
	it("excludes attacks out of band", function()
		-- Point blank: Claw is legal, Lunge (minRange 9) is not.
		local legal = AttackSelector.legalAttacks(SHAMBLER, 2, {}, NOW)
		expect(legal).toEqual({ "Claw" })
	end)

	it("includes a gap-closer only from range", function()
		local legal = AttackSelector.legalAttacks(SHAMBLER, 15, {}, NOW)
		expect(legal).toEqual({ "Lunge" })
	end)

	it("excludes attacks still on cooldown", function()
		local legal = AttackSelector.legalAttacks(SHAMBLER, 15, { Lunge = NOW + 1 }, NOW)
		expect(legal).toEqual({})
	end)

	it("includes an attack whose cooldown has just expired", function()
		local legal = AttackSelector.legalAttacks(SHAMBLER, 15, { Lunge = NOW }, NOW)
		expect(legal).toEqual({ "Lunge" })
	end)

	it("returns a stable sorted order", function()
		-- Reproducibility matters: tuning sessions compare runs against each
		-- other, and table iteration order would make that meaningless.
		local legal = AttackSelector.legalAttacks(DUMMY, 5, {}, NOW)
		expect(legal).toEqual({ "GroundSlam", "Overhead" })
	end)
end)

describe("AttackSelector.chooseAttack", function()
	it("returns nil when nothing is legal", function()
		-- Walked down inside its own minimum range, with Spray on cooldown.
		expect(AttackSelector.chooseAttack(SPITTER, 3, { Spray = NOW + 5 }, NOW)).toBeNil()
	end)

	it("returns the only legal attack regardless of roll", function()
		expect(AttackSelector.chooseAttack(SHAMBLER, 2, {}, NOW, function()
			return 0
		end)).toBe("Claw")

		expect(AttackSelector.chooseAttack(SHAMBLER, 2, {}, NOW, function()
			return 0.999
		end)).toBe("Claw")
	end)

	-- Dummy at range 5: GroundSlam weight 1, Overhead weight 3, sorted
	-- ["GroundSlam", "Overhead"], total weight 4.
	it("respects weights when picking between legal attacks", function()
		local lowRoll = AttackSelector.chooseAttack(DUMMY, 5, {}, NOW, function()
			return 0.1 -- 0.4 of 4 -> inside GroundSlam's weight of 1
		end)
		expect(lowRoll).toBe("GroundSlam")

		local highRoll = AttackSelector.chooseAttack(DUMMY, 5, {}, NOW, function()
			return 0.9 -- 3.6 of 4 -> past GroundSlam, inside Overhead
		end)
		expect(highRoll).toBe("Overhead")
	end)

	it("never returns an out-of-band attack even at roll extremes", function()
		for _, roll in { 0, 0.25, 0.5, 0.75, 0.999999 } do
			local chosen = AttackSelector.chooseAttack(SHAMBLER, 15, {}, NOW, function()
				return roll
			end)
			expect(chosen).toBe("Lunge")
		end
	end)
end)

describe("AttackSelector bounds", function()
	local ROOM: AttackSelector.Bounds = { minX = -17, maxX = 17, minZ = 33, maxZ = 67 }

	it("contains a point inside the room", function()
		expect(AttackSelector.isWithinBounds(ROOM, 0, 50)).toBe(true)
	end)

	it("treats the leash edge as inside", function()
		expect(AttackSelector.isWithinBounds(ROOM, 17, 67)).toBe(true)
		expect(AttackSelector.isWithinBounds(ROOM, -17, 33)).toBe(true)
	end)

	-- The case the leash exists for: a player in the next room over.
	it("excludes a point in the neighbouring room", function()
		expect(AttackSelector.isWithinBounds(ROOM, 0, 100)).toBe(false)
		expect(AttackSelector.isWithinBounds(ROOM, 0, 0)).toBe(false)
	end)

	it("leaves a point inside the room untouched when clamping", function()
		local x, z = AttackSelector.clampToBounds(ROOM, 4, 52)
		expect(x).toBe(4)
		expect(z).toBe(52)
	end)

	-- Enemies move by CFrame, which ignores walls; the clamp is what stops them
	-- walking through one.
	it("clamps a step that would leave the room back to its edge", function()
		local x, z = AttackSelector.clampToBounds(ROOM, 40, 20)
		expect(x).toBe(17)
		expect(z).toBe(33)
	end)
end)

describe("EnemyDefs invariants", function()
	-- Guards the design rather than the code: an enemy whose attacks leave a
	-- gap in its own band will stand there doing nothing, which reads as a bug
	-- rather than as behaviour.
	it("gives every enemy something legal at its preferred range", function()
		for enemyId, def in EnemyDefs do
			local legal = AttackSelector.legalAttacks(def, def.preferredRange, {}, NOW)
			expect({ enemyId, #legal > 0 }).toEqual({ enemyId, true })
		end
	end)

	it("gives every enemy at least one parryable attack", function()
		-- Otherwise that enemy silently opts out of the entire parry system.
		for enemyId, def in EnemyDefs do
			local hasParryable = false
			for _, attack in def.attacks do
				if attack.parryable then
					hasParryable = true
				end
			end
			expect({ enemyId, hasParryable }).toEqual({ enemyId, true })
		end
	end)

	it("keeps every attack band and weight coherent", function()
		for _, def in EnemyDefs do
			for _, attack in def.attacks do
				expect(attack.minRange <= attack.maxRange).toBe(true)
				expect(attack.weight > 0).toBe(true)
				expect(attack.telegraphDuration > 0).toBe(true)
			end
		end
	end)

	-- Enemies hold still through a windup, so an attack chosen from further
	-- away than it reaches is a guaranteed miss.
	it("never lets an attack be chosen from beyond its own reach", function()
		for enemyId, def in EnemyDefs do
			for attackId, attack in def.attacks do
				local label = `{enemyId}.{attackId}`
				expect({ label, attack.maxRange <= attack.range }).toEqual({ label, true })
			end
		end
	end)

	it("keeps every bleed well-formed", function()
		for _, def in EnemyDefs do
			for _, attack in def.attacks do
				local dot = attack.dot
				if dot then
					expect(dot.tickDamage > 0).toBe(true)
					expect(dot.tickInterval > 0).toBe(true)
					expect(dot.ticks >= 1).toBe(true)
				end
			end
		end
	end)

	-- Rooms are 40 studs across and enemies are leashed inside them, so an
	-- enemy that wants to stand further away than the room allows would pin
	-- itself to a wall and never reach its preferred spacing.
	it("keeps every preferred range inside a single room", function()
		local ROOM_DIAGONAL_HALF = 40 / 2 * math.sqrt(2)
		for enemyId, def in EnemyDefs do
			expect({ enemyId, def.preferredRange <= ROOM_DIAGONAL_HALF }).toEqual({ enemyId, true })
		end
	end)
end)

describe("Enemy economy invariants", function()
	local LootTables = require(Shared.LootTables)

	-- Any enemy type can end up guarding a chest, so a missing loot row would
	-- fail the moment a player tried to open one.
	it("gives every enemy type a loot row", function()
		for enemyId in EnemyDefs do
			expect({ enemyId, LootTables[enemyId] ~= nil }).toEqual({ enemyId, true })
		end
	end)

	it("pays every enemy type some coins", function()
		for enemyId, def in EnemyDefs do
			expect({ enemyId, def.coinReward > 0 }).toEqual({ enemyId, true })
		end
	end)

	-- DESIGN.md: crystals only come from tougher enemies, which is what keeps
	-- trash-mob grinding away from the top blacksmith tiers.
	it("keeps crystals away from the weakest enemy", function()
		local weakestId, weakestHealth = nil, math.huge
		for enemyId, def in EnemyDefs do
			if def.maxHealth < weakestHealth then
				weakestId, weakestHealth = enemyId, def.maxHealth
			end
		end

		expect(EnemyDefs[weakestId :: string].crystalReward).toBe(0)
	end)

	it("has at least one crystal source, or the top tiers are unreachable", function()
		local anyCrystals = false
		for _, def in EnemyDefs do
			if def.crystalReward > 0 then
				anyCrystals = true
			end
		end
		expect(anyCrystals).toBe(true)
	end)
end)
