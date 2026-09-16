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

```
src/
  shared/                        -- -> ReplicatedStorage.Shared
    WeaponDefs.luau              -- weaponId -> class, stats, moveset, ability kit
    LootTables.luau              -- encounterGroupId -> possible drops (not built yet)
    CombatConstants.luau         -- parry windows, stagger values, timing
    EnemyDefs.luau
    Remotes.luau                 -- name constants + Remotes.Get(name); creates/finds
                                  -- the actual RemoteEvents under ReplicatedStorage.Remotes
                                  -- at runtime (not a Rojo-mapped path — RemoteEvents
                                  -- are runtime Instances, not source files)
  server/                        -- -> ServerScriptService.Server
    Combat/
      CombatServer.luau          -- rate-limits attacks, wires remotes to enemy instances
      Enemy.luau                 -- one enemy's state machine + Workspace model
                                  -- (EnemyAI.luau will generalize this across enemy
                                  -- types in build order step 3)
    Dungeon/                     -- not built yet
      DungeonGenerator.luau
      RoomTemplates/
    Economy/                     -- not built yet
      LootService.luau
      BlacksmithService.luau
    DataService.luau             -- not built yet — DataStore read/write, PlayerData schema
  client/                        -- -> StarterPlayer.StarterPlayerScripts.Client
    CombatClient.luau            -- input capture, remote feedback (color flash for now)
    UI/                          -- not built yet
```

## Naming registry — RemoteEvents / RemoteFunctions

| Name | Direction | Payload | Purpose |
|---|---|---|---|
| `ParryAttempt` | Client → Server | `{ timestamp }` | Player attempts a parry |
| `AttackAttempt` | Client → Server | `{ timestamp }` | Player attempts a basic weapon swing |
| `EnemyTelegraphStart` | Server → Client | `{ enemyId, attackId, duration }` | Attack is winding up — VFX/audio cue |
| `EnemyStateChanged` | Server → Client | `{ enemyId, state, hp }` | Enemy entered Idle/Telegraph/Staggered/Recover/Dead |
| `PlayerHit` | Server → Client | `{ amount, sourceId }` | Damage feedback |
| `RequestUpgrade` | Client → Server (returns) | `{ itemId }` → `{ success, newStats?, error? }` | Blacksmith upgrade attempt |
| `ChestOpened` | Server → Client | `{ chestId, loot[] }` | Fired when the guard encounter is cleared |
| *(add new rows here as they're built)* | | | |

> `ParryAttempt`/`AttackAttempt` carry a client timestamp for future prediction
> use, but the server does not trust it for parry validation — client and
> server `os.clock()` aren't synchronized. Instead the server uses its own
> receipt time minus half the player's `GetNetworkPing()`, compared against
> the enemy's known telegraph resolve time (see `Combat/Enemy.luau`).

## Naming registry — Classes / weapon types

| Id | Weapon type | Notes |
|---|---|---|
| `Tank` | Sword + Shield | Wide/forgiving parry window, shield-bash counter |
| `Assassin` | Daggers | Tight parry window, high backstab payoff |
| `Healer` | Staff / Mace | Parries near allies trigger burst heal |
| `Mage` | Staff / Wand | Exception — magic replaces basic combat, not just enhances it |
| *(add new rows here as they're built)* | | |

## Naming registry — Enemy ids

| Id | Notes |
|---|---|
| `TrainingDummy` | Vertical-slice-only melee dummy, one parryable `Swing` attack, no `encounterGroupId` (doesn't guard a chest) |
| *(add new rows here as they're built)* | |

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
