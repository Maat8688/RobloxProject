--!strict
-- Damage resolution and server-side hit-reg geometry. Pure Luau — the
-- positional checks take plain vectors rather than Roblox instances so they
-- stay testable outside the engine.

local DamageMath = {}

export type Vec2 = { x: number, z: number }

-- Damage a parried attack still deals. Zero for now: a clean parry fully
-- negates, which makes the vertical slice's feedback unambiguous while the
-- window itself is being tuned. If chip damage on parry is introduced later,
-- log it in DESIGN.md first.
local PARRIED_DAMAGE_MULTIPLIER = 0

function DamageMath.resolveIncoming(baseDamage: number, wasParried: boolean): number
	if wasParried then
		return baseDamage * PARRIED_DAMAGE_MULTIPLIER
	end

	return baseDamage
end

-- Damage the player deals. The riposte window is the Assassin's parry payoff:
-- a tight parry converts into a burst of amplified damage, which is how
-- "skill must count as much as level/gear" is expressed for that class rather
-- than through stat scaling.
function DamageMath.resolveOutgoing(baseDamage: number, riposteActive: boolean, riposteMultiplier: number): number
	if riposteActive then
		return baseDamage * riposteMultiplier
	end

	return baseDamage
end

-- Per-class scaling of the base stagger. The Tank's payoff is control: a
-- longer stagger opening rather than extra damage.
function DamageMath.staggerDuration(baseDuration: number, staggerMultiplier: number): number
	return baseDuration * staggerMultiplier
end

function DamageMath.applyHealing(currentHealth: number, maxHealth: number, healing: number): number
	return math.clamp(currentHealth + healing, 0, maxHealth)
end

-- Flattened to the XZ plane: the slice's room is flat, and ignoring height
-- avoids an attack whiffing because a player hopped.
local function horizontalDistance(from: Vec2, to: Vec2): number
	local dx = to.x - from.x
	local dz = to.z - from.z
	return math.sqrt(dx * dx + dz * dz)
end

-- Signed angle between the attacker's facing and the direction to the target,
-- in degrees, always 0-180.
local function angleToTarget(attackerPos: Vec2, attackerFacing: Vec2, targetPos: Vec2): number
	local dx = targetPos.x - attackerPos.x
	local dz = targetPos.z - attackerPos.z
	local distance = math.sqrt(dx * dx + dz * dz)

	-- Target is exactly on top of the attacker; treat as directly in front
	-- rather than dividing by zero.
	if distance == 0 then
		return 0
	end

	local facingLength = math.sqrt(attackerFacing.x * attackerFacing.x + attackerFacing.z * attackerFacing.z)
	if facingLength == 0 then
		return 0
	end

	local dot = (dx * attackerFacing.x + dz * attackerFacing.z) / (distance * facingLength)
	-- Guard against floating-point drift pushing the cosine outside [-1, 1],
	-- which would make math.acos return NaN.
	dot = math.clamp(dot, -1, 1)

	return math.deg(math.acos(dot))
end

export type HitTestParams = {
	attackerPos: Vec2,
	attackerFacing: Vec2,
	targetPos: Vec2,
	range: number,
	arcDegrees: number,
}

-- Evaluated on the server against server-side positions at the moment of
-- impact. The client is never asked whether it was hit.
function DamageMath.isInHitVolume(params: HitTestParams): boolean
	if horizontalDistance(params.attackerPos, params.targetPos) > params.range then
		return false
	end

	-- arcDegrees is the full cone width, so a 360 arc means omnidirectional.
	local halfArc = params.arcDegrees / 2
	return angleToTarget(params.attackerPos, params.attackerFacing, params.targetPos) <= halfArc
end

return DamageMath
