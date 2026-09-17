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
Module functions are lowerCamelCase (`CombatServer.start`). Entries marked
*(planned)* do not exist yet — see the build order in DESIGN.md.

```
src/shared/            -> ReplicatedStorage.Shared
  CombatConstants.luau   -- shared combat tunables: timestamp authority, stamina,
                         -- stagger + punish bonus, strike grace, respawn, PvP
  ParryMath.luau         -- the whole parry decision: timestamp check, window,
                         -- readiness, target selection (pure)
  DamageMath.luau        -- damage resolution + hit-reg geometry (pure)
  AttackSelector.luau    -- enemy attack choice, movement intent, room leash (pure)
  Loadout.luau           -- equip validation + class-from-weapon derivation (pure)
  WeaponDefs.luau        -- weaponId -> class, parry profile, attack, payoff
  EnemyDefs.luau         -- enemyId -> stats, movement, rewards, attack timelines
  LootTables.luau        -- enemyId -> chest loot descriptor
  EconomyDefs.luau       -- upgrade cost curve, tiers, upgraded damage (pure).
                         -- Shared so the client can show a price; the server
                         -- always recomputes before charging
  PlayerDataSchema.luau  -- saved-progress shape: defaults, migration,
                         -- sanitising, session-lock rules (pure). Shared only
                         -- so it's testable; the client never uses it
  RigDefs.luau           -- the shared R15 skeleton + each rig's look (pure)
  AnimationDefs.luau     -- every rough animation, as keyframe data (pure)
  AnimationIds.luau      -- published replacements for those animations (pure)
  KeyframeMath.luau      -- sampling, easing, blending, strike timing (pure)
  RigAssembly.luau       -- builds rigs from RigDefs using an API it's handed,
                         -- so the game and the Lune workbench share it
  Remotes.luau           -- every RemoteEvent is created here, from a fixed list;
                         -- nothing created ad hoc elsewhere
  __tests__/             -- Jest specs, mounted by test.project.json only

src/server/            -> ServerScriptService.Server
  init.server.luau       -- bootstrap: combat, dungeon, stations, arena, then
                         -- players
  DataService.luau       -- loads and saves progress: session locks, autosave,
                         -- final save on leave and on shutdown
  SpawnService.luau      -- when characters exist: first spawn only once a
                         -- profile has loaded, start-room placement, respawn
  EquipService.luau      -- the only owner of equipped weapon + upgrade levels
  InventoryService.luau  -- the only owner of inventory
  WeaponPickups.luau     -- weapon stands in the start room (ProximityPrompt)
  Combat/
    CombatServer.luau    -- the authority: enemy state machines, PvE parry and
                         -- swing resolution, bleeds, burst heal. Owns the
                         -- ParryAttempt/AttackRequest listeners for PvP too,
                         -- routing duelists to PvPCombatServer
    EnemyAI.luau         -- enemy rigs, movement, leash, death hooks
    PlayerCombatState.luau -- per-player stamina, lockout, riposte, swing timing;
                         -- one record shared by PvE and PvP
    Characters.luau      -- character lookups + XZ projection + half-ping
  Dungeon/
    DungeonGenerator.luau -- straight chain of rooms + corridors; spawns each
                         -- room's guard through CombatServer
    RoomTemplates.luau   -- room geometry recipes (Empty/Pillars) returning the
                         -- enemy spawn, chest spot and leash bounds. One module,
                         -- not a folder — see DESIGN.md
    ChestService.luau    -- one barrier-locked chest per room, unlocked on its
                         -- guard's first death
  Economy/
    CurrencyService.luau -- the only owner of coins + class-keyed crystals; pays
                         -- the killer via each enemy's death hook
    BlacksmithService.luau -- the start-room anvil: prices an upgrade, takes
                         -- payment, hands off to EquipService
  PvP/
    ArenaService.luau    -- the arena room, the duel queue, who duels whom
    Duelist.luau         -- one side of a duel: state machine + virtual health
    PvPCombatServer.luau -- resolves duel swings and parries on the PvE rules;
                         -- listens on no remote itself

src/client/            -> StarterPlayer.StarterPlayerScripts.Client
  init.client.luau       -- bootstrap
  CombatClient.luau      -- combat input: parry timestamp, swing request, and
                         -- Studio-only 1/2/3 weapon swaps
  CameraLock.luau        -- toggleable shift-lock camera (Left Shift)
  RigAnimation.luau      -- plays AnimationDefs on one rig via Motor6D
                         -- Transforms, or a published version via Animator
  EnemyAnimation.luau    -- picks each enemy's animation from server events
  PlayerAnimation.luau   -- player swing/parry overlays; local ones predicted
  TelegraphVFX.luau      -- windup/stagger/death colours on enemy rigs, and
                         -- ground danger zones for all-around attacks
  WorldFeedback.luau     -- enemy health bars, damage numbers, hit and
                         -- parry flashes/sparks
  GameUI.luau            -- player-facing UI: flashes, weapon, currency, loot,
                         -- upgrades, inventory (I), duel status
  DebugHUD.luau          -- tuning readout (temporary; replaced at step 10)

tests/                 -> mounted only by test.project.json, never shipped
  jest.config.luau
  TestRunner.server.luau

lune/                  -> not mapped by Rojo; Lune scripts run from the repo root
  test.luau              -- `lune run test`: runs the same specs headless, with
                         -- pure modules sandboxed away from the Roblox API
  animation-workbench.luau -- `lune run animation-workbench`: every rig with its
                         -- rough animations as KeyframeSequences, self-checked
  lib/sharedModules.luau -- loads src/shared outside Roblox, sandboxed

workbench/             -> generated by the workbench script; gitignored
```

**Pure-module rule.** `CombatConstants`, `ParryMath`, `DamageMath`,
`AttackSelector`, `Loadout`, `WeaponDefs`, `EnemyDefs`, `LootTables`,
`EconomyDefs`, `PlayerDataSchema`, `RigDefs`, `AnimationDefs`,
`AnimationIds` and `KeyframeMath` must not call any Roblox API.
`RigAssembly` is the one shared module that creates instances, and it only
ever uses the API passed to it, never globals. That is what keeps the combat and
economy math unit-testable, and what lets the same specs run headless under
Lune. Anything needing `game`, `workspace` or `Instance` belongs in the server
or client layer, not in these files. `lune run test` enforces this for every
module a spec loads: those globals are traps in its sandbox.

**Spec rule.** A spec may only require pure shared modules, through
`ReplicatedStorage.Shared`, and may only use the Jest matchers the Lune runner
implements (`toBe`, `toEqual`, `toBeCloseTo`, `toBeNil`, and `never`). The
runner fails loudly on anything else — extend it rather than working around it.

**Single-owner rule.** Equipped weapon and upgrade levels live only in
`EquipService`, inventory only in `InventoryService`, currency only in
`CurrencyService`, per-player combat resources only in `PlayerCombatState`.
Everything else asks them.

**Persistence rule.** Each persisted service exposes `hydrate`, `snapshot`
and `release`, and only `DataService` calls them. **A persisted service must
never clear a player's state on `PlayerRemoving`:** Roblox doesn't guarantee
the order those handlers run in, so a cleanup could beat the final save and
write an empty profile. `DataService` calls `release` once that save is done.
A new persisted field needs all three hooks, a `PlayerDataSchema` field, and
(if its shape changes) a migration.

## Naming registry — RemoteEvents

All payloads are a single table.

| Name | Direction | Payload | Purpose |
|---|---|---|---|
| `ParryAttempt` | Client → Server | `{ timestamp }` | Player attempts a parry. `timestamp` is `workspace:GetServerTimeNow()` on the client; the server checks it against its own receipt-time estimate (`ParryMath.plausibleSendWindow`) |
| `AttackRequest` | Client → Server | *(none)* | Player swings. Carries no timestamp — a swing isn't reactive, so the server resolves it on its own clock |
| `EquipWeapon` | Client → Server | `{ weaponId }` | **Studio only** — the 1/2/3 debug swap. Ignored by a live server; weapon stands are the real equip path |
| `EnemyTelegraphStart` | Server → Client | `{ enemyId, attackId, duration, impactTime, parryable }` | Attack is winding up. `impactTime` is absolute so a delayed packet doesn't shift the cue |
| `EnemyStaggered` | Server → Client | `{ enemyId, duration }` | Enemy interrupted by a successful parry. `duration` is already scaled by the parrying class's payoff |
| `EnemyHealthChanged` | Server → Client | `{ enemyId, health, maxHealth, alive }` | Enemy spawn, damage, death and respawn |
| `PlayerHit` | Server → Client | `{ amount, sourceId, attackId, bleed? }` | Damage feedback. `sourceId` is an enemy id, or the attacker's name in a duel. `bleed` marks a damage-over-time tick |
| `ParryResult` | Server → Client | `{ verdict, success, deltaMs, stamina, riposteUntil, enemyId? }` | Parry outcome, PvE and PvP. `deltaMs` is signed distance from impact. `enemyId` is what the press resolved against (the attacker's name in a duel) |
| `AttackResult` | Server → Client | `{ hit, reason, damage, riposte, enemyId? }` | Swing outcome. `reason` is from the attack-result registry below |
| `HealBurst` | Server → Client | `{ amount, healerName }` | Fired to each player actually healed by a parry-triggered burst heal |
| `PlayerCombatAction` | Server → Client (all) | `{ userId, action, weaponId, windup? }` | A player's swing or parry was accepted, so every client can animate it. `action` is `swing` \| `parry`; `windup` is how long the swing takes to land. Clients ignore their own, already animated on input |
| `ProfileLoaded` | Server → Client | `{ persistent }` | The player's progress is ready. `persistent` is false only in a Studio session running without DataStore access |
| `WeaponEquipped` | Server → Client | `{ weaponId, classTag, upgradeLevel }` | Fired on equip, on load, and whenever the equipped weapon's upgrade level changes |
| `ChestOpened` | Server → Client | `{ chestId, loot, inventoryFull? }` | `loot` is a list holding one `LootTables` descriptor (display info, not the stored `ItemInstance`). With `inventoryFull`, `loot` is empty and the chest stays shut |
| `InventoryUpdated` | Server → Client | `{ items }` | The player's full `ItemInstance` list whenever it changes |
| `CurrencyUpdated` | Server → Client | `{ coins, crystals }` | Whenever a balance changes; `crystals` is keyed by class |
| `UpgradeResult` | Server → Client | `{ success, reason?, newLevel? }` | Blacksmith outcome; `reason` is player-facing refusal text |
| `PvPStatusChanged` | Server → Client | `{ status, opponentName?, message? }` | `status` is `idle` \| `queued` \| `dueling`; `message` is set when a duel ends |
| `PvPTelegraphStart` | Server → Client | `{ attackerName, duration, impactTime }` | Sent to the defending duelist when their opponent swings |
| `PvPParryResult` | Server → Client | `{ success, message }` | Sent to both duelists when a duel swing is parried |
| `PvPHealthChanged` | Server → Client | `{ yours, opponent }` | Both duelists' virtual health, whenever either changes |
| *(add new rows here as they're built)* | | | |

### Retired remote names

Planned or built under these names at some point; none exist now. Don't reuse
them for something different.

| Name | Fate |
|---|---|
| `RequestUpgrade` | Planned RemoteFunction, never built — the blacksmith is a `ProximityPrompt`, and the outcome goes over `UpgradeResult` (see DESIGN.md) |
| `AttackAttempt` | Maat8688's fork name for `AttackRequest`; retired at the merge |
| `EnemyStateChanged` | Maat8688's fork; replaced at the merge by `EnemyTelegraphStart`, `EnemyStaggered` and `EnemyHealthChanged` |

## Naming registry — Classes

| Id | Weapon type | Status | Notes |
|---|---|---|---|
| `Tank` | Sword + Shield | built | Widest parry window; its payoff is the longest stagger, i.e. the longest double-damage window for the group. A distinct shield-bash counter isn't built |
| `Assassin` | Daggers | built | Tightest window, highest payoff — currently the riposte. Backstab is unblocked (enemies now have a facing) but not built |
| `Healer` | Staff / Mace | built | Parries trigger a burst heal that reaches allies |
| `Mage` | Staff / Wand | not built | Exception — magic replaces basic combat, not just enhances it. Needs its own combat model, deliberately not a `WeaponDefs` row yet |
| *(add new rows here as they're built)* | | | |

## Naming registry — Weapons

Class is derived from the weapon, so this table *is* the class roster. There is
deliberately no `ClassDefs` module. Exact numbers live in `WeaponDefs.luau`;
this table is the summary.

| Id | Class | Parry window | Parry payoff | PvP telegraph |
|---|---|---|---|---|
| `SwordAndShield` | `Tank` | 200/100 ms — widest | Control: 1.5× stagger duration | 0.50 s |
| `Daggers` | `Assassin` | 80/50 ms — tightest | Damage: 2.5× for 2.5 s (riposte) | 0.30 s |
| `Staff` | `Healer` | 140/80 ms | Sustain: 25 hp burst heal, 20-stud radius | 0.45 s |
| *(add new rows here as they're built)* | | | | |

**Class-derivation rule.** A player's class is never stored. It is always read
from their equipped weapon's `classTag` via `Loadout.classOf`, which makes
"switching weapon switches class" true by construction. Adding a class means
adding a row to `WeaponDefs` — there should never be an
`if classTag == "..."` branch anywhere in combat.

## Naming registry — Enemies / attacks

Behaviour is data, not code. An enemy is defined by its attack bands
(`minRange`/`maxRange`), where it wants to stand (`preferredRange`) and how it
weights its options — a charging melee type and a kiting ranged type come out of
the same `AttackSelector` with no per-enemy branches. **If a new enemy needs a
branch in `AttackSelector`, the behaviour belongs in `EnemyDefs` as data
instead.** Every enemy is leashed to its room, and any enemy type can guard a
chest, so a new enemy also needs a `LootTables` row. Enemies hold still through
a windup, so every attack's `maxRange` must be at most its `range` — a test
enforces it.

| Enemy id | Role | Rewards | Attack id | Parryable | Notes |
|---|---|---|---|---|---|
| `TrainingDummy` | stationary | 10 coins | `Overhead` | yes | Baseline parryable attack |
| | | | `GroundSlam` | **no** | Must-dodge; exists so combat isn't "parry everything" |
| `SkeletonWarrior` | melee, tough | 25 coins, 1 crystal | `Slash` | yes | Quick parryable swing |
| | | | `GroundSlam` | **no** | Hit volume (14) wider than its use range (10); leaves a bleed |
| `Shambler` | melee, closes | 15 coins | `Claw` | yes | Fast pressure at touching range |
| | | | `Lunge` | yes | Long reach, `minRange` 9 so it reads as a lunge, not a swing |
| `Spitter` | ranged, kites | 15 coins | `Spit` | yes | Narrow 25° cone at range |
| | | | `Spray` | **no** | Point-blank panic option, so closing the gap isn't a free win |
| *(add new rows here as they're built)* | | | | | |

Enemy models carry the attributes `EnemyId` and `EnemyDefId`.

## Naming registry — CollectionService tags

| Tag | On | Purpose |
|---|---|---|
| `Enemy` | every enemy model | Client lookup by `EnemyId` wherever the model is parented (`EnemyAI.TAG`). Clients also watch it for enemies streaming in, so they never assume a model exists yet |

**Client-only VFX instances.** `DangerZone` parts in Workspace,
`HealthBar_<enemyId>` BillboardGuis in PlayerGui, the `TelegraphGlow`
Highlight and hit/parry Highlights and spark attachments under enemy models
are created by each client for itself and never replicate. Nothing on the
server may look for them. All of it uses Roblox's built-in defaults — no
uploaded assets.

## Naming registry — Rigs

Every rig uses the R15 part and joint names below, the same as a default
Roblox R15 avatar. That shared vocabulary is what lets one animation play on
any rig and on players.

| Rig id | Used for | Look |
|---|---|---|
| `TrainingDummy` | the enemy | Wooden mannequin, target on the chest |
| `SkeletonWarrior` | the enemy | Bone spine and ribs, dark eye sockets, sword in the right hand |
| `Shambler` | the enemy | Green skin, torn shirt, glowing red eyes |
| `Spitter` | the enemy | Bloated body on thin limbs, glowing acid sac |
| `R15Player` | the workbench only | Plain grey figure standing in for a player avatar |
| *(add new rows here as they're built)* | | |

An enemy's rig id is its `EnemyDefs` id. **An enemy model** is:
`HumanoidRootPart` (the invisible 4×6×4 hitbox — the only part that collides,
and the one every combat position is read from), the 15 body parts on Motor6D
joints under it, welded decorations, and an `AnimationController` with an
`Animator`.

| Part | Joint (inside the part) | Parent |
|---|---|---|
| `LowerTorso` | `Root` | `HumanoidRootPart` |
| `UpperTorso` | `Waist` | `LowerTorso` |
| `Head` | `Neck` | `UpperTorso` |
| `RightUpperArm` / `LeftUpperArm` | `RightShoulder` / `LeftShoulder` | `UpperTorso` |
| `RightLowerArm` / `LeftLowerArm` | `RightElbow` / `LeftElbow` | the upper arm |
| `RightHand` / `LeftHand` | `RightWrist` / `LeftWrist` | the lower arm |
| `RightUpperLeg` / `LeftUpperLeg` | `RightHip` / `LeftHip` | `LowerTorso` |
| `RightLowerLeg` / `LeftLowerLeg` | `RightKnee` / `LeftKnee` | the upper leg |
| `RightFoot` / `LeftFoot` | `RightAnkle` / `LeftAnkle` | the lower leg |

## Naming registry — Animations

| Name | Rigs | Plays when |
|---|---|---|
| `idle` | every enemy | standing |
| `walk` | every enemy | the hitbox is moving; tempo follows speed |
| `stagger` | every enemy | `EnemyStaggered`, stretched over its duration |
| `death` | every enemy | `EnemyHealthChanged` with `alive` false; holds the last frame |
| `attack_<attackId>` | the enemy that owns the attack | `EnemyTelegraphStart`, strike timed to `impactTime` |
| `swing_<weaponId>` | `R15Player` | the player swings that weapon |
| `parry` | `R15Player` | the player parries |

**Impact keyframe.** Attack and swing animations carry an `impact` time and a
keyframe exactly there, which the workbench names `Impact`. Playback stretches
everything before it over the real windup, so the strike lands when the server
resolves the hit. A refined, published version must keep a keyframe named
`Impact`, or it plays at its own speed.

**Player overlay rule.** Player animations never pose `LowerTorso` or the
legs, so Roblox's own walk and run keep playing underneath. A test enforces
it.

**Refining.** `lune run animation-workbench` → drag
`workbench/AnimationWorkbench.rbxm` into Studio → load an animation from a
rig's `AnimSaves` in the Animation Editor → refine → publish → add the ID to
`AnimationIds.PUBLISHED`. That animation then plays through the Animator
everywhere, with no code change; the rough version stays as the fallback.

## Naming registry — Parry verdicts

Produced by `ParryMath` and the combat servers, sent over `ParryResult`, and
colour-mapped in `DebugHUD`. Adding a verdict means touching all three.

| Verdict | Meaning |
|---|---|
| `parried` | Inside the window — the only successful verdict |
| `early` / `late` | Outside the window on that side |
| `unparryable` | Attack cannot be parried at any timing |
| `rejected_future` | Claimed a later press than a message arriving now could have been sent |
| `rejected_stale` | Claimed an earlier press than the player's connection accounts for |
| `no_attack` | Nothing incoming within reach; still costs stamina and the lockout |
| `exhausted` / `recovering` | Blocked before timing was even evaluated |
| `unequipped` | No weapon picked up yet |

## Naming registry — Attack results

`AttackResult.reason` values.

| Reason | Meaning |
|---|---|
| `hit` | Landed |
| `missed` | Nothing inside the swing volume |
| `cooldown` | Still swinging, or the weapon's cooldown hasn't elapsed |
| `exhausted` | Not enough stamina |
| `unequipped` | No weapon picked up yet |
| `no_target` | No character to swing from |

## Naming registry — Loot

| Item id | Dropped by | Rarity |
|---|---|---|
| `PracticeToken` | `TrainingDummy` chest | common |
| `BoneHiltShard` | `SkeletonWarrior` chest | uncommon |
| `RottedClaw` | `Shambler` chest | common |
| `AcidGland` | `Spitter` chest | common |
| *(add new rows here as they're built)* | | |

Every combat room's enemy guards that room's chest 1:1 (`ChestService`).
`encounterGroupId` stays unused until a chest needs a real multi-enemy group.

## Naming registry — Currencies

| Id | Meaning |
|---|---|
| `coins` | Common currency, paid by every kill (`EnemyDefs.coinReward`) |
| `crystals` | Keyed by **class** — `crystals.Tank`, `crystals.Assassin`, `crystals.Healer`. You earn the class you had equipped when the kill landed, so crystals don't carry across a respec. Only tougher enemies pay them (`EnemyDefs.crystalReward`) |

There is no separate crystal-type namespace: a crystal type *is* a Classes
entry. Adding a class adds its crystal type for free — don't invent a parallel
`TankCrystal`-style id.

## Data schemas

```lua
-- Stored DataStore value, one per player. Store "PlayerData_v1"
-- ("PlayerData_v1_Studio" from Studio), key "player_<UserId>".
{
  data: PlayerData,
  session: SessionLock?,   -- absent when no server holds the profile
}

-- SessionLock (PlayerDataSchema.SessionLock)
{
  jobId: string,           -- game.JobId of the owning server
  heartbeat: number,       -- os.time() of its last save; stale after 180 s
}

-- PlayerData (PlayerDataSchema.PlayerData)
{
  version: number,         -- schema version; a newer one than the server
                           -- knows stops the load rather than being replaced
  coins: number,
  crystals: { [classTag]: number },
  equipped: { weapon: weaponId? },  -- a table so armour slots can join later
  upgradeLevels: { [weaponId]: number },
  inventory: { ItemInstance },      -- a list, not keyed by itemId: a player can
                                    -- hold several copies of one item, each
                                    -- with its own upgradeLevel. Capped at
                                    -- PlayerDataSchema.MAX_INVENTORY
}
-- Unknown class, weapon and item ids are preserved, never dropped: they may
-- belong to newer content, and a rollback must not delete that progress.

-- ItemInstance (InventoryService.ItemInstance)
{
  itemId: string,
  rarity: string,        -- "common" | "uncommon" | "rare" | "epic" ...
  upgradeLevel: number,
  classTag: string?,     -- a Classes entry, or nil for a class-neutral
                         -- material or memento (see LootTables)
}

-- EnemyDef (EnemyDefs.EnemyDef)
{
  displayName: string,
  maxHealth: number,
  attackInterval: number,
  preferredRange: number,  -- distance it tries to hold; drives approach/retreat
  moveSpeed: number,       -- 0 = stationary
  aggroRange: number,
  coinReward: number,      -- paid to whoever lands the killing blow
  crystalReward: number,   -- 0 for trash mobs; gates the higher upgrade tiers
  encounterGroupId: string?, -- (planned) for multi-enemy chest guards
  attacks: {
    [attackId]: {
      telegraphDuration: number,
      parryable: boolean,  -- false = must-dodge; no timing blocks it
      damage: number,
      range: number,       -- hit volume, and how close a player must be to parry it
      arcDegrees: number,
      minRange: number,    -- band in which the attack is a legal choice
      maxRange: number,
      weight: number,
      cooldown: number,
      dot: { tickDamage: number, tickInterval: number, ticks: number }?,
                           -- bleed applied on an unparried hit
    },
  },
}
```
