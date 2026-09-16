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
    LootTables.luau              -- enemyType -> loot descriptor (itemId, name, flavor,
                                  -- rarity, classTag) — ChestService builds the actual
                                  -- ItemInstance from this plus upgradeLevel = 0
    CombatConstants.luau         -- parry windows, stagger values, timing
    EconomyDefs.luau             -- upgrade cost curve, max upgrade level, damage
                                  -- bonus per level. Shared so the client can show
                                  -- a price without a round trip; the server always
                                  -- recomputes before charging
    EnemyDefs.luau
    Remotes.luau                 -- name constants + Remotes.Get(name); creates/finds
                                  -- the actual RemoteEvents under ReplicatedStorage.Remotes
                                  -- at runtime (not a Rojo-mapped path — RemoteEvents
                                  -- are runtime Instances, not source files)
  server/                        -- -> ServerScriptService.Server
    EquipService.luau            -- the only place equipped-weapon state lives,
                                  -- including per-weapon upgrade levels; GetWeapon
                                  -- returns stats with the upgrade already applied,
                                  -- so combat never has to know about the blacksmith
                                  -- (in-memory only until step 10's DataStores)
    InventoryService.luau        -- the only place inventory state lives (same
                                  -- in-memory-only shape as EquipService)
    WeaponPickups.luau           -- physical weapon stands placed in the dungeon's start
                                  -- room (not a menu); ProximityPrompt.Triggered ->
                                  -- EquipService.SetWeapon
    Combat/
      CombatServer.luau          -- rate-limits attacks, wires remotes to enemy instances,
                                  -- reads the attacker's weapon from EquipService
      Enemy.luau                 -- generalized enemy AI: state machine + Workspace model,
                                  -- picks randomly among its EnemyDefs attacks each cycle.
                                  -- A separate EnemyAI.luau was planned but turned out
                                  -- unnecessary — see DESIGN.md's decision log.
    Dungeon/
      DungeonGenerator.luau      -- stitches a straight chain of rooms + corridors,
                                  -- spawns enemies at each combat room's marked point.
                                  -- Room count/kind/enemy-type are randomized per run.
      RoomTemplates.luau         -- floor+wall geometry recipes (Empty/Pillars) with an
                                  -- optional door gap; one file, not a RoomTemplates/
                                  -- folder as originally sketched — see DESIGN.md
      ChestService.luau          -- one barrier-locked chest per combat room, guarded 1:1
                                  -- by that room's enemy; unlocks permanently on its
                                  -- first death via Enemy:OnDeath, fires ChestOpened
    Economy/
      CurrencyService.luau       -- the only place currency state lives (coins +
                                  -- class-keyed crystals); pays the killer via each
                                  -- enemy's OnDeath. A LootService.luau was planned
                                  -- here instead — see DESIGN.md's decision log
      BlacksmithService.luau     -- the anvil in the start room: prices an upgrade,
                                  -- takes payment, then hands off to EquipService
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
| `EnemyTelegraphStart` | Server → Client | `{ enemyId, attackId, duration, parryable }` | Attack is winding up — VFX/audio cue; `parryable` lets the client show a must-dodge cue differently |
| `EnemyStateChanged` | Server → Client | `{ enemyId, state, hp }` | Enemy entered Idle/Telegraph/Staggered/Recover/Dead |
| `PlayerHit` | Server → Client | `{ amount, sourceId }` | Damage feedback |
| `WeaponEquipped` | Server → Client | `{ weaponId, upgradeLevel }` | Fired by EquipService when a player equips/switches weapon, and again when that weapon's upgrade level changes |
| `CurrencyUpdated` | Server → Client | `{ coins, crystals }` | Fired by CurrencyService whenever a balance changes; `crystals` is keyed by class id |
| `UpgradeResult` | Server → Client | `{ success, reason?, newLevel? }` | Outcome of a blacksmith upgrade attempt; `reason` is the player-facing refusal text |
| `ChestOpened` | Server → Client | `{ chestId, loot[] }` | Fired when a chest is opened; `loot[]` holds one `LootTables` descriptor (display info, not the stored `ItemInstance`) |
| `InventoryUpdated` | Server → Client | `{ items[] }` | Fired by InventoryService with the player's full current `ItemInstance` list whenever it changes |
| *(add new rows here as they're built)* | | | |

> `ParryAttempt`/`AttackAttempt` carry a client timestamp for future prediction
> use, but the server does not trust it for parry validation — client and
> server `os.clock()` aren't synchronized. Instead the server uses its own
> receipt time minus half the player's `GetNetworkPing()`, compared against
> the enemy's known telegraph resolve time (see `Combat/Enemy.luau`).

## Naming registry — Classes / weapon types

| Id | Weapon type | Notes |
|---|---|---|
| `Tank` | Sword + Shield | Wide/forgiving parry window, shield-bash counter (bash not built yet) |
| `Assassin` | Daggers | Tight parry window, high backstab payoff (backstab needs enemies to have a facing direction — not built yet, still open) |
| `Healer` | Staff / Mace | Lowest basic-attack damage of the three; parries near allies trigger burst heal (not built yet — build order step 8) |
| `Mage` | Staff / Wand | Exception — magic replaces basic combat, not just enhances it. Not implemented — needs its own combat model, deliberately not in `WeaponDefs.luau` yet |
| *(add new rows here as they're built)* | | |

> Exact per-weapon numbers (baseDamage, swingCooldown, parryWindow,
> swingRange) live in `WeaponDefs.luau` — this table is notes/flavor, that
> file is the source of truth.

## Naming registry — Enemy ids

| Id | Notes |
|---|---|
| `TrainingDummy` | Vertical-slice-only melee dummy, one parryable `Swing` attack |
| `SkeletonWarrior` | Tougher (80 hp), two attacks: parryable `Slash` and unparryable `GroundSlam` (must-dodge AoE, larger range) |
| *(add new rows here as they're built)* | |

> Every combat room's enemy also guards that room's chest 1:1 (see
> `ChestService.luau`) — `encounterGroupId` stays unused until a chest needs
> a real multi-enemy group.

## Naming registry — Encounter / loot tags

| Id | Meaning |
|---|---|
| `PracticeToken` | `LootTables` entry for a `TrainingDummy` chest |
| `BoneHiltShard` | `LootTables` entry for a `SkeletonWarrior` chest |
| *(add new rows here as they're built)* | |

## Naming registry — Currencies

| Id | Meaning |
|---|---|
| `coins` | Common currency, paid by every kill (`EnemyDefs.coinReward`) |
| `crystals` | Keyed by **class id** — `crystals.Tank`, `crystals.Assassin`, `crystals.Healer`. You earn the class you had equipped when the kill landed, so crystals do not carry across a respec |

> There is no separate crystal-type namespace: a crystal type *is* a Classes
> entry above. Adding a class adds its crystal type for free — don't invent a
> parallel `TankCrystal`-style id.

## Data schemas

```lua
-- PlayerData
{
  coins: number,
  crystals: { [crystalType]: number },
  equipped: { weapon: itemId, chest: itemId?, boots: itemId? },
  inventory: { ItemInstance },  -- a list, not keyed by itemId — a player can
                                -- hold more than one instance of the same
                                -- itemId (e.g. two Practice Tokens), and each
                                -- instance can have its own upgradeLevel
}

-- ItemInstance
{
  itemId: string,
  rarity: string,        -- "common" | "uncommon" | "rare" | "epic" ...
  upgradeLevel: number,
  classTag: string?,     -- must match a Classes entry above, or nil for a
                          -- class-neutral material/memento (see LootTables)
}

-- EnemyDef
{
  enemyId: string,
  hp: number,
  encounterGroupId: string?,   -- set if this enemy guards a chest
  coinReward: number,          -- paid to whoever lands the killing blow
  crystalReward: number,       -- 0 for trash mobs; only tougher enemies drop
                               -- crystals, which gate the higher upgrade tiers
  attacks: {
    [attackId]: {
      telegraphDuration: number,
      parryable: boolean,       -- false = must-dodge; no timing window can block it
      damage: number,
      range: number,            -- how close a player must be to take this specific attack
    },
  },
}
```
