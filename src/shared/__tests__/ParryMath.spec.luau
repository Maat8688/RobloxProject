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

-- By default the message reached the server the instant it was sent, from a
-- zero-ping player. That isolates the timing verdict from the timestamp
-- authority checks, which get their own section below with explicit ping and
-- receipt times.
local function evaluateAt(attemptTime: number, overrides: { [string]: any }?): ParryMath.Evaluation
	local params = {
		attemptTime = attemptTime,
		serverNow = attemptTime,
		halfPing = 0,
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

describe("ParryMath.evaluate timing", function()
	it("succeeds on a press exactly at impact", function()
		local result = evaluateAt(IMPACT)
		expect(result.verdict).toBe("parried")
		expect(result.success).toBe(true)
		expect(result.deltaMs).toBe(0)
	end)

	it("succeeds inside the early half of the window", function()
		expect(evaluateAt(IMPACT - TANK_PROFILE.earlyTolerance / 2).verdict).toBe("parried")
	end)

	it("succeeds inside the late half of the window", function()
		expect(evaluateAt(IMPACT + TANK_PROFILE.lateTolerance / 2).verdict).toBe("parried")
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

	it("refuses a perfectly timed parry on an unparryable attack", function()
		local result = evaluateAt(IMPACT, { attackParryable = false })
		expect(result.verdict).toBe("unparryable")
		expect(result.success).toBe(false)
	end)
end)

describe("ParryMath.plausibleSendWindow", function()
	it("centres a zero-ping player's window on the receipt time", function()
		local earliest, latest = ParryMath.plausibleSendWindow(NOW, 0)
		expect(earliest).toBeCloseTo(NOW - CombatConstants.MIN_TIMESTAMP_TOLERANCE, 9)
		expect(latest).toBeCloseTo(NOW + CombatConstants.MIN_TIMESTAMP_TOLERANCE, 9)
	end)

	it("shifts back and widens with ping", function()
		local lowEarliest, lowLatest = ParryMath.plausibleSendWindow(NOW, 0)
		local highEarliest, highLatest = ParryMath.plausibleSendWindow(NOW, 0.1)

		expect(highLatest < lowLatest).toBe(true)
		expect(highLatest - highEarliest > lowLatest - lowEarliest).toBe(true)
	end)

	-- A spoofed or absurd ping must never widen the band past the hard limits.
	it("never extends past the hard limits, whatever the ping", function()
		for _, halfPing in { 0, 0.2, 0.4, 5, 1e9, -3 } do
			local earliest, latest = ParryMath.plausibleSendWindow(NOW, halfPing)
			expect(earliest >= NOW - CombatConstants.MAX_ACCEPTED_LATENCY - 1e-9).toBe(true)
			expect(latest <= NOW + CombatConstants.FUTURE_TOLERANCE + 1e-9).toBe(true)
			expect(earliest <= latest).toBe(true)
		end
	end)
end)

describe("ParryMath.evaluate timestamp authority", function()
	-- These hold the receipt time fixed and move the claimed press time around
	-- it. impactTime tracks the claim so the timing would always be perfect —
	-- proving any rejection comes from authority, not from the window.
	local function evaluateClaim(attemptTime: number, halfPing: number): ParryMath.Evaluation
		return evaluateAt(attemptTime, { serverNow = NOW, halfPing = halfPing, impactTime = attemptTime })
	end

	it("accepts an honest zero-ping claim", function()
		expect(evaluateClaim(NOW, 0).verdict).toBe("parried")
	end)

	it("accepts an honest high-ping claim sent half a round trip ago", function()
		expect(evaluateClaim(NOW - 0.15, 0.15).verdict).toBe("parried")
	end)

	it("rejects a claim later than the message could have been sent", function()
		local result = evaluateClaim(NOW + CombatConstants.FUTURE_TOLERANCE + 0.01, 0)
		expect(result.verdict).toBe("rejected_future")
		expect(result.success).toBe(false)
	end)

	it("rejects a claim older than the rewind bound", function()
		local result = evaluateClaim(NOW - CombatConstants.MAX_ACCEPTED_LATENCY - 0.01, 0.2)
		expect(result.verdict).toBe("rejected_stale")
		expect(result.success).toBe(false)
	end)

	-- The bot case. A client that knows impactTime can claim a press at exactly
	-- that moment. Bounded rewind alone would believe it anywhere in a 450ms
	-- span; checked against receipt time minus ping, a low-ping client can't
	-- backdate much at all.
	it("rejects a low-ping client backdating a claim", function()
		local result = evaluateClaim(NOW - 0.3, 0.01)
		expect(result.verdict).toBe("rejected_stale")
	end)

	it("rejects a high-ping claim that pretends to be instant", function()
		-- Half a round trip is 200ms, yet the claim says it was sent just now.
		local result = evaluateClaim(NOW, 0.2)
		expect(result.verdict).toBe("rejected_future")
	end)

	it("checks authority before the timing window", function()
		-- Perfect timing, untrustworthy claim: authority must win.
		expect(evaluateClaim(NOW + 5, 0).verdict).toBe("rejected_future")
		expect(evaluateClaim(NOW - 5, 0).verdict).toBe("rejected_stale")
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
	end)

	-- With several rooms running, the nearest-impact attack may be aimed at
	-- someone else entirely.
	it("ignores an attack that can't reach the player, however soon it lands", function()
		local target = ParryMath.selectParryTarget({
			{ enemyId = "FarRoom_9", impactTime = NOW, parryable = true, distance = 60, reach = 12 },
			{ enemyId = "Shambler_2", impactTime = NOW + 0.4, parryable = true, distance = 5, reach = 13 },
		}, NOW)

		expect((target :: any).enemyId).toBe("Shambler_2")
	end)

	it("returns nil when every attack is out of reach", function()
		local target = ParryMath.selectParryTarget({
			{ enemyId = "FarRoom_9", impactTime = NOW, parryable = true, distance = 60, reach = 12 },
		}, NOW)

		expect(target).toBeNil()
	end)

	it("includes an attack exactly at the edge of its reach", function()
		local target = ParryMath.selectParryTarget({
			{ enemyId = "Edge_1", impactTime = NOW, parryable = true, distance = 12, reach = 12 },
		}, NOW)

		expect((target :: any).enemyId).toBe("Edge_1")
	end)
end)

describe("ParryMath.checkReadiness", function()
	it("allows a parry with full stamina and no lockout", function()
		expect(ParryMath.checkReadiness(CombatConstants.MAX_STAMINA, 0, NOW).allowed).toBe(true)
	end)

	it("blocks while the whiff lockout is active", function()
		local readiness = ParryMath.checkReadiness(CombatConstants.MAX_STAMINA, NOW + 0.1, NOW)
		expect(readiness.allowed).toBe(false)
		expect(readiness.reason).toBe("recovering")
	end)

	it("allows again once the lockout has elapsed", function()
		expect(ParryMath.checkReadiness(CombatConstants.MAX_STAMINA, NOW - 0.1, NOW).allowed).toBe(true)
	end)

	it("blocks when stamina is below the parry cost", function()
		local readiness = ParryMath.checkReadiness(CombatConstants.PARRY_STAMINA_COST - 1, 0, NOW)
		expect(readiness.allowed).toBe(false)
		expect(readiness.reason).toBe("exhausted")
	end)

	it("allows when stamina exactly covers the parry cost", function()
		expect(ParryMath.checkReadiness(CombatConstants.PARRY_STAMINA_COST, 0, NOW).allowed).toBe(true)
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
