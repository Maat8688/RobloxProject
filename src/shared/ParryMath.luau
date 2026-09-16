--!strict
-- The parry decision, in full. Pure Luau: takes numbers, returns a verdict,
-- touches no Roblox API and holds no state. Every branch here is covered by
-- ParryMath.spec.luau, because this is the module where "server-authoritative"
-- either holds or quietly doesn't.

local CombatConstants = require(script.Parent.CombatConstants)
local WeaponDefs = require(script.Parent.WeaponDefs)

local ParryMath = {}

local BOUNDARY_EPSILON = 1e-9

export type Verdict =
	-- Timestamp failed sanity checks; the attempt never reaches the window.
	"rejected_future" | "rejected_stale"
	-- Attack cannot be parried at all, whatever the timing.
	| "unparryable"
	-- Timing verdicts.
	| "early" | "late" | "parried"

export type Evaluation = {
	verdict: Verdict,
	success: boolean,
	-- Signed offset from impact in milliseconds: negative early, positive late.
	-- Surfaced to the debug HUD, because tuning windows by feel without the
	-- actual miss distance is guesswork.
	deltaMs: number,
}

export type EvaluateParams = {
	-- Server time the client claims it pressed parry.
	attemptTime: number,
	-- Server time right now, from the authoritative clock.
	serverNow: number,
	-- Server time this attack lands.
	impactTime: number,
	parryProfile: WeaponDefs.ParryProfile,
	attackParryable: boolean,
}

-- Bounded rewind. The server trusts the client's timestamp, but only inside a
-- window it chose: far enough back to cover honest latency (~ping/2 plus
-- jitter), not far enough to let a client claim it parried something it has
-- already seen resolve.
local function isTimestampTrustworthy(attemptTime: number, serverNow: number): Verdict?
	if attemptTime > serverNow + CombatConstants.FUTURE_TOLERANCE then
		return "rejected_future"
	end

	if attemptTime < serverNow - CombatConstants.MAX_ACCEPTED_LATENCY then
		return "rejected_stale"
	end

	return nil
end

function ParryMath.evaluate(params: EvaluateParams): Evaluation
	local deltaSeconds = params.attemptTime - params.impactTime
	local deltaMs = deltaSeconds * 1000

	local rejection = isTimestampTrustworthy(params.attemptTime, params.serverNow)
	if rejection then
		return { verdict = rejection, success = false, deltaMs = deltaMs }
	end

	if not params.attackParryable then
		return { verdict = "unparryable", success = false, deltaMs = deltaMs }
	end

	-- Window is anchored to impact, not to the start of the windup, so it stays
	-- correct regardless of how long a given attack telegraphs for.
	--
	-- BOUNDARY_EPSILON keeps the window genuinely inclusive at both ends: the
	-- timestamps being compared are accumulated floats, so a press landing on
	-- the boundary can come out a few ulps outside it and lose a parry the
	-- player earned. A nanosecond of slack is far below anything a human can
	-- express, so it costs nothing and makes the boundary deterministic.
	if deltaSeconds < -(params.parryProfile.earlyTolerance + BOUNDARY_EPSILON) then
		return { verdict = "early", success = false, deltaMs = deltaMs }
	end

	if deltaSeconds > params.parryProfile.lateTolerance + BOUNDARY_EPSILON then
		return { verdict = "late", success = false, deltaMs = deltaMs }
	end

	return { verdict = "parried", success = true, deltaMs = deltaMs }
end

export type Readiness = {
	allowed: boolean,
	reason: string?,
}

-- Gating that happens before the timing question is even asked. Bounded rewind
-- alone does not stop a client mashing parry every frame until one lands, so
-- stamina and the whiff lockout are what actually make timing matter.
function ParryMath.checkReadiness(stamina: number, lockoutUntil: number, serverNow: number): Readiness
	if serverNow < lockoutUntil then
		return { allowed = false, reason = "recovering" }
	end

	if stamina < CombatConstants.PARRY_STAMINA_COST then
		return { allowed = false, reason = "exhausted" }
	end

	return { allowed = true }
end

-- Regen is time-based rather than tick-based so the result does not depend on
-- server framerate.
function ParryMath.regenerateStamina(current: number, elapsedSeconds: number): number
	local regenerated = current + CombatConstants.STAMINA_REGEN_PER_SECOND * elapsedSeconds
	return math.min(regenerated, CombatConstants.MAX_STAMINA)
end

return ParryMath
