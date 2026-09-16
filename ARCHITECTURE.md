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
  ReplicatedStorage/
    Shared/
      WeaponDefs.lua        -- weaponId -> class, stats, moveset, ability kit
      LootTables.lua        -- encounterGroupId -> possible drops
      CombatConstants.lua   -- parry windows, stagger values, stamina costs
      EnemyDefs.lua
    Remotes/                 -- every RemoteEvent/RemoteFunction lives here,
                              -- nothing created ad hoc elsewhere
  ServerScriptService/
    Combat/
      CombatServer.lua       -- hit reg, parry validation, damage resolution
      EnemyAI.lua
    Dungeon/
      DungeonGenerator.lua
      RoomTemplates/          -- pre-built Room models w/ marked spawn points
    Economy/
      LootService.lua
      BlacksmithService.lua
    DataService.lua           -- DataStore read/write, owns the PlayerData schema
  StarterPlayer/StarterPlayerScripts/
    CombatClient.lua          -- input capture, parry timestamp send, VFX
    UI/
```

## Naming registry — RemoteEvents / RemoteFunctions

| Name | Direction | Payload | Purpose |
|---|---|---|---|
| `ParryAttempt` | Client → Server | `{ timestamp }` | Player attempts a parry |
| `EnemyTelegraphStart` | Server → Client | `{ enemyId, attackId, duration }` | Attack is winding up — VFX/audio cue |
| `PlayerHit` | Server → Client | `{ amount, sourceId }` | Damage feedback |
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
