--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConstants = require(Shared.CombatConstants)
local ParryMath = require(Shared.ParryMath)
local WeaponDefs = require(Shared.WeaponDefs)

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local TANK_PROFILE = WeaponDefs.SwordAndShield.parry

-- Fixed clock values keep these tests independent of wall time.
local IMPACT = 100.0
local NOW = 100.0

-- serverNow defaults to the attempt time, i.e. the message reached the server
-- the instant it was sent. That isolates the timing verdict from the timestamp
-- sanity checks — without it, a press in the late half of the window looks like
-- a claim about the future and gets rejected before its timing is ever judged.
-- Tests that care about the sanity checks override serverNow explicitly.
local function evaluateAt(attemptTime: number, overrides: { [string]: any }?): ParryMath.Evaluation
	local params = {
		attemptTime = attemptTime,
		serverNow = attemptTime,
		impactTime = IMPACT,
		parryProfile = TANK_PROFILE,
		attackParryable = true,
	}

	if overrides then
		for key, value in overrides do
			params[key] = value
		end
	end

	return ParryMath.evaluate(params :: any)
end

describe("ParryMath.evaluate", function()
	it("succeeds on a press exactly at impact", function()
		local result = evaluateAt(IMPACT)
		expect(result.verdict).toBe("parried")
		expect(result.success).toBe(true)
		expect(result.deltaMs).toBe(0)
	end)

	it("succeeds inside the early half of the window", function()
		local result = evaluateAt(IMPACT - TANK_PROFILE.earlyTolerance / 2)
		expect(result.verdict).toBe("parried")
		expect(result.success).toBe(true)
	end)

	it("succeeds inside the late half of the window", function()
		local result = evaluateAt(IMPACT + TANK_PROFILE.lateTolerance / 2)
		expect(result.verdict).toBe("parried")
	end)

	-- The window is inclusive at both ends, so a press landing exactly on a
	-- boundary is a success. Worth pinning: an off-by-one here silently costs
	-- players parries they earned.
	it("treats both window boundaries as inclusive", function()
		expect(evaluateAt(IMPACT - TANK_PROFILE.earlyTolerance).verdict).toBe("parried")
		expect(evaluateAt(IMPACT + TANK_PROFILE.lateTolerance).verdict).toBe("parried")
	end)

	it("reports early just outside the early bound", function()
		local result = evaluateAt(IMPACT - TANK_PROFILE.earlyTolerance - 0.001)
		expect(result.verdict).toBe("early")
		expect(result.success).toBe(false)
		expect(result.deltaMs < 0).toBe(true)
	end)

	it("reports late just outside the late bound", function()
		local result = evaluateAt(IMPACT + TANK_PROFILE.lateTolerance + 0.001)
		expect(result.verdict).toBe("late")
		expect(result.success).toBe(false)
		expect(result.deltaMs > 0).toBe(true)
	end)

	it("reports the miss distance in signed milliseconds", function()
		expect(evaluateAt(IMPACT - 0.5).deltaMs).toBeCloseTo(-500, 6)
		expect(evaluateAt(IMPACT + 0.5).deltaMs).toBeCloseTo(500, 6)
	end)
end)

describe("ParryMath.evaluate timestamp authority", function()
	-- These hold serverNow fixed and move the claimed attempt time around it.
	-- impactTime tracks the attempt so the timing would always be perfect —
	-- proving any rejection comes from the sanity checks, not the window.
	local function evaluateClaim(attemptTime: number): ParryMath.Evaluation
		return evaluateAt(attemptTime, { serverNow = NOW, impactTime = attemptTime })
	end

	it("rejects a timestamp from beyond the future tolerance", function()
		local result = evaluateClaim(NOW + CombatConstants.FUTURE_TOLERANCE + 0.01)
		expect(result.verdict).toBe("rejected_future")
		expect(result.success).toBe(false)
	end)

	it("accepts a slightly future timestamp within jitter tolerance", function()
		local result = evaluateClaim(NOW + CombatConstants.FUTURE_TOLERANCE / 2)
		expect(result.verdict).toBe("parried")
	end)

	it("rejects a timestamp older than the rewind bound", function()
		local result = evaluateClaim(NOW - CombatConstants.MAX_ACCEPTED_LATENCY - 0.01)
		expect(result.verdict).toBe("rejected_stale")
		expect(result.success).toBe(false)
	end)

	-- This is latency compensation working as intended: a laggy but honest
	-- player still gets their parry.
	it("accepts a stale-but-plausible timestamp inside the rewind bound", function()
		local result = evaluateClaim(NOW - CombatConstants.MAX_ACCEPTED_LATENCY + 0.01)
		expect(result.verdict).toBe("parried")
	end)

	it("checks the timestamp before the timing window", function()
		-- Perfect timing, untrustworthy clock: authority must win.
		expect(evaluateClaim(NOW + 5).verdict).toBe("rejected_future")
	end)
end)

describe("ParryMath.evaluate unparryable attacks", function()
	it("refuses a perfectly timed parry on an unparryable attack", function()
		local result = evaluateAt(IMPACT, { attackParryable = false })
		expect(result.verdict).toBe("unparryable")
		expect(result.success).toBe(false)
	end)
end)

describe("ParryMath.selectParryTarget", function()
	it("returns nil when nothing is incoming", function()
		expect(ParryMath.selectParryTarget({}, NOW)).toBeNil()
	end)

	it("picks the attack landing nearest the press", function()
		local target = ParryMath.selectParryTarget({
			{ enemyId = "Shambler_2", impactTime = NOW + 0.8, parryable = true },
			{ enemyId = "Spitter_3", impactTime = NOW + 0.05, parryable = true },
			{ enemyId = "TrainingDummy_1", impactTime = NOW + 1.4, parryable = true },
		}, NOW)

		expect(target).never.toBeNil()
		expect((target :: any).enemyId).toBe("Spitter_3")
	end)

	it("counts an attack that has just passed as nearer than a distant one", function()
		local target = ParryMath.selectParryTarget({
			{ enemyId = "Shambler_2", impactTime = NOW - 0.02, parryable = true },
			{ enemyId = "Spitter_3", impactTime = NOW + 0.9, parryable = true },
		}, NOW)

		expect((target :: any).enemyId).toBe("Shambler_2")
	end)

	-- Deliberate: if the thing about to hit you is unparryable, the parry must
	-- fail against it rather than quietly redirecting to a parryable attack
	-- elsewhere. Otherwise reading which attack lands first stops mattering.
	it("does not skip an unparryable attack in favour of a parryable one", function()
		local target = ParryMath.selectParryTarget({
			{ enemyId = "Spitter_3", impactTime = NOW + 0.05, parryable = false },
			{ enemyId = "Shambler_2", impactTime = NOW + 0.3, parryable = true },
		}, NOW)

		expect((target :: any).enemyId).toBe("Spitter_3")
		expect((target :: any).parryable).toBe(false)
	end)

	it("handles a single candidate", function()
		local target = ParryMath.selectParryTarget({
			{ enemyId = "Shambler_2", impactTime = NOW + 5, parryable = true },
		}, NOW)

		expect((target :: any).enemyId).toBe("Shambler_2")
	end)
end)

describe("ParryMath.checkReadiness", function()
	it("allows a parry with full stamina and no lockout", function()
		local readiness = ParryMath.checkReadiness(CombatConstants.MAX_STAMINA, 0, NOW)
		expect(readiness.allowed).toBe(true)
	end)

	it("blocks while the whiff lockout is active", function()
		local readiness = ParryMath.checkReadiness(CombatConstants.MAX_STAMINA, NOW + 0.1, NOW)
		expect(readiness.allowed).toBe(false)
		expect(readiness.reason).toBe("recovering")
	end)

	it("allows again once the lockout has elapsed", function()
		local readiness = ParryMath.checkReadiness(CombatConstants.MAX_STAMINA, NOW - 0.1, NOW)
		expect(readiness.allowed).toBe(true)
	end)

	it("blocks when stamina is below the parry cost", function()
		local readiness = ParryMath.checkReadiness(CombatConstants.PARRY_STAMINA_COST - 1, 0, NOW)
		expect(readiness.allowed).toBe(false)
		expect(readiness.reason).toBe("exhausted")
	end)

	it("allows when stamina exactly covers the parry cost", function()
		local readiness = ParryMath.checkReadiness(CombatConstants.PARRY_STAMINA_COST, 0, NOW)
		expect(readiness.allowed).toBe(true)
	end)
end)

describe("ParryMath.regenerateStamina", function()
	it("regenerates at the configured rate", function()
		expect(ParryMath.regenerateStamina(0, 1)).toBe(CombatConstants.STAMINA_REGEN_PER_SECOND)
	end)

	it("clamps at the maximum", function()
		expect(ParryMath.regenerateStamina(CombatConstants.MAX_STAMINA, 10)).toBe(CombatConstants.MAX_STAMINA)
	end)

	it("does not change with a zero timestep", function()
		expect(ParryMath.regenerateStamina(42, 0)).toBe(42)
	end)
end)
