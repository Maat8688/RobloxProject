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
  WeaponDefs.luau        -- weaponId -> class, stats, parry profile
  EnemyDefs.luau         -- enemyId -> stats, attack timelines
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

**Pure-module rule.** `CombatConstants`, `ParryMath`, `DamageMath`, `WeaponDefs`
and `EnemyDefs` must not call any Roblox API. That is what keeps the combat math
unit-testable, and it is what will let a headless Lune CI tier run the same
specs without a rewrite. Anything needing `game`, `workspace` or `Instance`
belongs in the server or client layer, not in these five files.

## Naming registry — RemoteEvents / RemoteFunctions

| Name | Direction | Payload | Purpose |
|---|---|---|---|
| `ParryAttempt` | Client → Server | `{ timestamp }` | Player attempts a parry. `timestamp` is `workspace:GetServerTimeNow()` on the client |
| `EnemyTelegraphStart` | Server → Client | `{ enemyId, attackId, duration, impactTime, parryable }` | Attack is winding up — VFX/audio cue. `impactTime` is absolute so a delayed packet doesn't shift the cue |
| `PlayerHit` | Server → Client | `{ amount, sourceId, attackId }` | Damage feedback |
| `ParryResult` | Server → Client | `{ verdict, success, deltaMs, stamina }` | Parry outcome. `deltaMs` is signed distance from impact, for HUD tuning |
| `EnemyStaggered` | Server → Client | `{ enemyId, duration }` | Enemy interrupted by a successful parry |
| `RequestUpgrade` | Client → Server (returns) | `{ itemId }` → `{ success, newStats?, error? }` | Blacksmith upgrade attempt |
| `ChestOpened` | Server → Client | `{ chestId, loot[] }` | Fired when the guard encounter is cleared |
| *(add new rows here as they're built)* | | | |

## Naming registry — Classes / weapon types

| Id | Weapon type | Notes |
|---|---|---|
| `Tank` | Sword + Shield | Wide/forgiving parry window, shield-bash counter |
| `Assassin` | Daggers | Tight parry window, high backstab payoff |
| `Healer` | Staff / Mace | Parries near allies trigger burst heal |
| `Mage` | Staff / Wand | Exception — magic replaces basic combat, not just enhances it |
| *(add new rows here as they're built)* | | |

## Naming registry — Weapons

| Id | Class | Notes |
|---|---|---|
| `SwordAndShield` | `Tank` | The vertical slice's only weapon |
| *(add new rows here as they're built)* | | |

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
