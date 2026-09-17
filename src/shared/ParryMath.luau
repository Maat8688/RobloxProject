--!strict
-- The parry decision, in full. Pure Luau: takes numbers, returns a verdict,
-- touches no Roblox API and holds no state. Every branch here is covered by
-- ParryMath.spec.luau, because this is the module where "server-authoritative"
-- either holds or quietly doesn't.
--
-- Used identically for PvE and PvP: a duel parry is the same decision with a
-- player's swing standing in for an enemy's attack.

local CombatConstants = require(script.Parent.CombatConstants)
local WeaponDefs = require(script.Parent.WeaponDefs)

local ParryMath = {}

local BOUNDARY_EPSILON = 1e-9

export type Verdict =
	-- Timestamp failed the authority checks; the attempt never reaches the window.
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
	-- Half the player's round-trip ping, as measured by the server.
	halfPing: number,
	-- Server time this attack lands.
	impactTime: number,
	parryProfile: WeaponDefs.ParryProfile,
	attackParryable: boolean,
}

-- The span of claimed send times the server will believe, given when the
-- message arrived and how laggy this player is.
--
-- This combines two approaches. The client's own timestamp is precise, so an
-- honest player gets judged on exactly when they pressed. But the client also
-- knows when the attack lands — it has to, to draw the telegraph — so on its
-- own a timestamp could be set to impactTime and sent at leisure. Receipt time
-- minus half the ping is an estimate the client cannot choose, so the claim is
-- only believed when it sits close to that estimate.
function ParryMath.plausibleSendWindow(serverNow: number, halfPing: number): (number, number)
	-- Clamped so a spoofed or absurd ping reading can't drag the estimate
	-- outside the hard limits below.
	local clampedHalfPing = math.clamp(halfPing, 0, CombatConstants.MAX_ACCEPTED_LATENCY)

	local expectedSend = serverNow - clampedHalfPing
	local tolerance = CombatConstants.MIN_TIMESTAMP_TOLERANCE
		+ clampedHalfPing * CombatConstants.TIMESTAMP_TOLERANCE_PING_FRACTION

	local earliest = math.max(expectedSend - tolerance, serverNow - CombatConstants.MAX_ACCEPTED_LATENCY)
	local latest = math.min(expectedSend + tolerance, serverNow + CombatConstants.FUTURE_TOLERANCE)

	return earliest, latest
end

local function checkTimestamp(attemptTime: number, serverNow: number, halfPing: number): Verdict?
	local earliest, latest = ParryMath.plausibleSendWindow(serverNow, halfPing)

	-- Claims a later press than could have produced a message arriving now.
	if attemptTime > latest then
		return "rejected_future"
	end

	-- Claims an earlier press than the connection accounts for.
	if attemptTime < earliest then
		return "rejected_stale"
	end

	return nil
end

function ParryMath.evaluate(params: EvaluateParams): Evaluation
	local deltaSeconds = params.attemptTime - params.impactTime
	local deltaMs = deltaSeconds * 1000

	local rejection = checkTimestamp(params.attemptTime, params.serverNow, params.halfPing)
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

-- Gating that happens before the timing question is even asked. The timestamp
-- check alone does not stop a client mashing parry every frame until one
-- lands, so stamina and the whiff lockout are what actually make timing
-- matter.
function ParryMath.checkReadiness(stamina: number, lockoutUntil: number, serverNow: number): Readiness
	if serverNow < lockoutUntil then
		return { allowed = false, reason = "recovering" }
	end

	if stamina < CombatConstants.PARRY_STAMINA_COST then
		return { allowed = false, reason = "exhausted" }
	end

	return { allowed = true }
end

export type ParryCandidate = {
	enemyId: string,
	impactTime: number,
	parryable: boolean,
	-- How far the parrying player is from the attacker, and how far this
	-- attack can reach. When both are given, an attack that couldn't reach the
	-- player isn't a candidate at all.
	distance: number?,
	reach: number?,
}

-- With more than one enemy winding up, a single parry press has to resolve to
-- exactly one incoming attack. The server decides, not the client — the client
-- never names a target.
--
-- Only attacks that could reach the player are considered. Without that, once
-- several rooms are running, a press could resolve against an enemy swinging
-- at someone else entirely.
--
-- Among those, the rule is "whichever lands nearest the moment you pressed".
-- Deliberately NOT "whichever parryable attack is nearest": if an unparryable
-- attack is the thing about to hit you, parrying should fail against it rather
-- than quietly redirect to a different enemy. Otherwise the player learns
-- nothing from the miss, and reading which attack lands first stops mattering
-- — which is the skill the telegraph system is supposed to be testing.
function ParryMath.selectParryTarget(candidates: { ParryCandidate }, attemptTime: number): ParryCandidate?
	local best: ParryCandidate? = nil
	local bestGap = math.huge

	for _, candidate in candidates do
		local distance = candidate.distance
		local reach = candidate.reach
		if distance and reach and distance > reach then
			continue
		end

		local gap = math.abs(candidate.impactTime - attemptTime)
		if gap < bestGap then
			best = candidate
			bestGap = gap
		end
	end

	return best
end

-- Regen is time-based rather than tick-based so the result does not depend on
-- server framerate.
function ParryMath.regenerateStamina(current: number, elapsedSeconds: number): number
	local regenerated = current + CombatConstants.STAMINA_REGEN_PER_SECOND * elapsedSeconds
	return math.min(regenerated, CombatConstants.MAX_STAMINA)
end

return ParryMath
