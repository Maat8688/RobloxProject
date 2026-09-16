# Design decisions — Roblox Dungeon Crawler

> Decisions and the reasoning behind them, so they don't get silently
> re-litigated across sessions. Add to this file — don't edit history away.
> If a decision changes, keep the old line, note the new one, and say why.

## Status

Vertical slice built (Sept 2026) — build-order step 1 is code-complete and
lints/builds clean, but **has not yet had its tuning pass**. The constants in
`CombatConstants.luau` are first guesses, not settled values. Steps 2–10 are
untouched.

## Core loop

Choose a weapon at start → weapon determines class → run a procedurally
generated dungeon → kill enemies for XP/coins → find enemy-guarded chests
(barrier drops once the guarding encounter group is cleared) → loot gear or
spend coins/crystals at the blacksmith to upgrade existing gear → repeat.

## Locked-in decisions

- **Class = equipped weapon**, not a separate stat or picker. Switching
  weapon switches class. Upgrade materials are class/weapon-type specific,
  so respeccing has a real cost and specialization is the natural path.
- **Combat is server-authoritative.** Parry input is validated server-side
  against the enemy's telegraph timeline, with a latency-compensation buffer
  (~ping/2). No full client-side prediction planned initially.
- **Skill must count as much as level/gear** — enforced through the
  parry/telegraph system, not stat-scaling tricks. Some attacks are
  deliberately unparryable (must-dodge AoEs) so it isn't "parry everything."
- **Healer must be near-indispensable.** Achieved via: (a) healing itself
  tied to the skill loop — e.g. a parry near allies triggers burst heal —
  rather than a passive HoT bot, and (b) dungeon mechanics with unavoidable
  chip damage / DoTs / execute thresholds that specifically require a healer
  to counter. Do not erode this via solo-balance changes without logging the
  change here first.
- **Magic enhances combat, it doesn't replace it** — except Mage, which is
  the explicit, deliberate exception.
- **Dungeon generation is room-prefab + connector based**, not noise/terrain
  generation. Hand-built Room models with marked enemy spawns and
  chest-vault rooms, stitched together by a layout algorithm.
- **Economy has two currencies**: coins (common, any kill) and rare crystals
  (tougher enemies/guards only), gating the higher blacksmith tiers so
  trash-mob grinding alone can't reach max gear.
- **Combat is primarily PvE** (zombies/monsters); PvP exists but reuses the
  same combat system rather than a separate one.

## Decisions made while building the vertical slice (Sept 2026)

These implement the locked-in decisions above; they are new commitments, not
changes to them.

- **The parry window is anchored to impact, not to the start of the windup** —
  `[impact - earlyTolerance, impact + lateTolerance]`. Anchoring to impact keeps
  the window correct no matter how long a given attack telegraphs for, so
  attacks with different windups don't each need their own hand-tuned window.
- **The early half is wider than the late half** (Tank: 0.20s vs 0.10s).
  Players anticipate the hit, so pressing slightly early is the common honest
  mistake and shouldn't be punished as hard as pressing after the fact.
- **Latency compensation is a bounded rewind, not prediction.** The server
  trusts the client's timestamp only if it falls within `MAX_ACCEPTED_LATENCY`
  (0.4s) of now and no further into the future than `FUTURE_TOLERANCE` (0.05s).
  This honours "no full client-side prediction" while still being fair to
  players on bad connections.
- **Strike resolution is held open past impact** by `STRIKE_RESOLUTION_GRACE`
  (0.15s), so a parry pressed in the late half of the window has time to reach
  the server. **This is the slice's main open tradeoff:** damage feedback lands
  that much after the visual impact, and a player whose round trip exceeds it
  loses late-half parries they legitimately earned. The debug HUD shows ping
  beside the parry delta specifically so this can be set on evidence. Revisit
  before step 2.
- **A parry fully negates damage** (no chip). Keeps slice feedback unambiguous
  while the window is being tuned. If chip damage on parry is ever wanted, log
  it here before implementing.
- **Parry costs stamina and a whiff costs a lockout**, both server-enforced.
  Without this, mashing the key every frame beats the timing system outright,
  which would hollow out "skill must count as much as level/gear". A press with
  no attack incoming counts as a whiff for the same reason.
- **`GroundSlam` (unparryable) shipped in the slice**, not deferred. DESIGN.md
  requires that combat not become "parry everything"; building the parryable and
  unparryable paths together is cheaper than retrofitting and re-tuning later.
- **Combat math is pure Luau**, segregated from anything touching the Roblox
  API, so it can be unit-tested. See the pure-module rule in ARCHITECTURE.md.

## Open / not yet decided

- Is solo play fully supported, or is this group-first content? This changes
  how hard healer-necessity can be tuned.
- Fixed class roster (Tank/Assassin/Healer/Mage/...) or open to add more later?
- PvP: does a simultaneous parry cause a clash/neutral outcome, or does one
  side win?

## Build order

1. Vertical slice: one room, one enemy, one weapon — get parry, hit-reg, and
   stagger feeling right, fully server-authoritative.
2. Weapon/class data framework (2–3 classes).
3. Enemy AI + telegraph system, generalized across enemy types.
4. Room-based dungeon generator.
5. Chest/encounter gating.
6. Loot + inventory/equip system.
7. Blacksmith/economy.
8. Healer-specific mechanics + a real balance pass.
9. PvP arena mode.
10. Persistence (DataStores), polish, VFX.
