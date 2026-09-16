# Architecture — Roblox Dungeon Crawler

> Read this file (and DESIGN.md) at the start of every session before writing code.
> They exist so decisions made in one session don't get silently redone or
> contradicted in the next.

## Before adding anything new

1. **Search this file first** for the thing you're about to name — a RemoteEvent,
   a ModuleScript, a data field, a class/rarity/tag string. If it already has a
   name, reuse that exact name and casing. Do not invent a synonym.
2. If it's genuinely new, **add one line to the relevant table below before
   finishing this session.** Don't leave a new RemoteEvent, module, or constant
   undocumented — the next session has no other way to know it exists.
3. Never silently rename something already listed here. If a rename is truly
   needed, update every reference, then log the rename (old name → new name,
   and why) in DESIGN.md's decision log.

## Project layout (Rojo → Roblox services)

Source folders are mapped by `default.project.json`. Files are `.luau`.
Entries marked *(planned)* do not exist yet — see the build order in DESIGN.md.

```
src/shared/          -> ReplicatedStorage.Shared
  CombatConstants.luau   -- parry windows, stagger, stamina, latency bounds
  ParryMath.luau         -- parry window + timestamp validation (pure)
  DamageMath.luau        -- damage resolution + hit-reg geometry (pure)
  WeaponDefs.luau        -- weaponId -> class, parry profile, attack, payoff
  EnemyDefs.luau         -- enemyId -> stats, attack timelines
  Loadout.luau           -- equip validation + class-from-weapon derivation
  Remotes.luau           -- every RemoteEvent/RemoteFunction is created here,
                         -- nothing created ad hoc elsewhere
  LootTables.luau        -- (planned) encounterGroupId -> possible drops
  __tests__/             -- Jest specs, mounted by test.project.json

src/server/          -> ServerScriptService.Server
  init.server.luau       -- bootstrap
  Combat/
    CombatServer.luau    -- hit reg, parry validation, damage resolution
    EnemyAI.luau         -- enemy rigs + attack selection
  Dungeon/
    RoomBuilder.luau     -- code-generated test room (slice only)
    DungeonGenerator.luau  -- (planned)
    RoomTemplates/         -- (planned) pre-built Room models w/ spawn points
  Economy/               -- (planned) LootService, BlacksmithService
  DataService.luau       -- (planned) DataStore read/write, owns PlayerData

src/client/          -> StarterPlayer.StarterPlayerScripts.Client
  init.client.luau       -- bootstrap
  CombatClient.luau      -- input capture, parry timestamp send
  TelegraphVFX.luau      -- windup/stagger visuals
  DebugHUD.luau          -- tuning readout (temporary; replaced at step 10)
  UI/                    -- (planned)

tests/               -> mounted only by test.project.json, never shipped
  jest.config.luau
  TestRunner.server.luau
```

**Pure-module rule.** `CombatConstants`, `ParryMath`, `DamageMath`, `WeaponDefs`,
`EnemyDefs` and `Loadout` must not call any Roblox API. That is what keeps the combat math
unit-testable, and it is what will let a headless Lune CI tier run the same
specs without a rewrite. Anything needing `game`, `workspace` or `Instance`
belongs in the server or client layer, not in these five files.

## Naming registry — RemoteEvents / RemoteFunctions

| Name | Direction | Payload | Purpose |
|---|---|---|---|
| `ParryAttempt` | Client → Server | `{ timestamp }` | Player attempts a parry. `timestamp` is `workspace:GetServerTimeNow()` on the client |
| `EnemyTelegraphStart` | Server → Client | `{ enemyId, attackId, duration, impactTime, parryable }` | Attack is winding up — VFX/audio cue. `impactTime` is absolute so a delayed packet doesn't shift the cue |
| `PlayerHit` | Server → Client | `{ amount, sourceId, attackId }` | Damage feedback |
| `ParryResult` | Server → Client | `{ verdict, success, deltaMs, stamina, riposteUntil }` | Parry outcome. `deltaMs` is signed distance from impact, for HUD tuning |
| `EnemyStaggered` | Server → Client | `{ enemyId, duration }` | Enemy interrupted by a successful parry. `duration` is already scaled by the parrying class's payoff |
| `AttackRequest` | Client → Server | *(none)* | Player swings. Carries no timestamp — a swing isn't reactive, so the server resolves it on its own clock |
| `AttackResult` | Server → Client | `{ hit, reason, damage, riposte }` | Swing outcome. `reason` is one of `hit`, `missed`, `cooldown`, `exhausted`, `no_target` |
| `EquipWeapon` | Client → Server | `{ weaponId }` | Requests a weapon (and therefore class) change. Id is validated against `WeaponDefs` |
| `WeaponEquipped` | Server → Client | `{ weaponId, classTag }` | Confirms the equipped weapon; also sent on join so the client never assumes a default |
| `EnemyHealthChanged` | Server → Client | `{ enemyId, health, maxHealth, alive }` | Enemy damage and death/respawn |
| `RequestUpgrade` | Client → Server (returns) | `{ itemId }` → `{ success, newStats?, error? }` | Blacksmith upgrade attempt |
| `ChestOpened` | Server → Client | `{ chestId, loot[] }` | Fired when the guard encounter is cleared |
| *(add new rows here as they're built)* | | | |

## Naming registry — Classes / weapon types

| Id | Weapon type | Status | Notes |
|---|---|---|---|
| `Tank` | Sword + Shield | built | Wide/forgiving parry window; shield-bash counter is currently the extended stagger |
| `Assassin` | Daggers | built | Tight parry window, high payoff — currently the riposte window, backstabs still to come |
| `Healer` | Staff / Mace | partial | Self-heal on parry built; "parry near allies triggers burst heal" needs allies (step 8) |
| `Mage` | Staff / Wand | not built | Exception — magic replaces basic combat, not just enhances it |
| *(add new rows here as they're built)* | | | |

## Naming registry — Weapons

Class is derived from the weapon, so this table *is* the class roster. There is
deliberately no `ClassDefs` module — see the class-derivation rule below.

| Id | Class | Parry window | Parry payoff |
|---|---|---|---|
| `SwordAndShield` | `Tank` | 200/100 ms — widest | Control: 1.5× stagger duration |
| `Daggers` | `Assassin` | 80/50 ms — tightest | Damage: 2.5× for 2.5 s (riposte) |
| `Staff` | `Healer` | 140/80 ms | Sustain: 14 hp self-heal |
| *(add new rows here as they're built)* | | | |

**Class-derivation rule.** A player's class is never stored. It is always read
from their equipped weapon's `classTag` via `Loadout.classOf`, which is what
makes "switching weapon switches class" true by construction rather than by
remembering to keep two fields in sync. Adding a class means adding a row to
`WeaponDefs` — it should not require new code.

## Naming registry — Enemies / attacks

| Enemy id | Attack id | Parryable | Notes |
|---|---|---|---|
| `TrainingDummy` | `Overhead` | yes | Baseline parryable attack |
| `TrainingDummy` | `GroundSlam` | **no** | Must-dodge; exists so combat isn't "parry everything" |
| *(add new rows here as they're built)* | | | |

## Naming registry — Parry verdicts

Returned by `ParryMath.evaluate` / `ParryMath.checkReadiness`, sent over
`ParryResult`, and colour-mapped in `DebugHUD`. Adding a verdict means touching
all three.

| Verdict | Meaning |
|---|---|
| `parried` | Inside the window — the only successful verdict |
| `early` / `late` | Outside the window on that side |
| `unparryable` | Attack cannot be parried at any timing |
| `rejected_future` / `rejected_stale` | Timestamp failed server sanity checks |
| `no_attack` | Pressed with nothing incoming; still costs stamina |
| `exhausted` / `recovering` | Blocked before timing was even evaluated |

## Naming registry — Encounter / loot tags

| Id | Meaning |
|---|---|
| *(empty — populate as encounter groups and loot pools are built)* | |

## Data schemas

```lua
-- PlayerData
{
  coins: number,
  crystals: { [crystalType]: number },
  equipped: { weapon: itemId, chest: itemId?, boots: itemId? },
  inventory: { [itemId]: ItemInstance },
}

-- ItemInstance
{
  itemId: string,
  rarity: string,        -- "common" | "rare" | "epic" ...
  upgradeLevel: number,
  classTag: string,      -- must match a Classes entry above
}

-- EnemyDef
{
  enemyId: string,
  encounterGroupId: string?,   -- set if this enemy guards a chest
  attacks: {
    [attackId]: { telegraphDuration: number, parryable: boolean },
  },
}
```
