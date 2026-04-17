# MechBattle — Remaining Work Roadmap

**Purpose.** Prioritized work queue for Claude Code. Ordering optimizes for (a) finishing what Claude does well first, (b) keeping risky/whirlwind-prone work in phases where the surrounding systems are stable, (c) batching human-only decisions at the top so Claude isn't blocked mid-task.

**How to use this doc.**
1. Jonathan answers the decisions in the top section first (most are pre-answered here).
2. Claude Code reads the "Godot 4.6 landmines" section before touching any code.
3. Work the phases in order. Each phase lists what Claude can do solo vs. what needs Jonathan.
4. Whirlwind warnings are called out inline. When you see one, read the mitigation before writing code.

**What's already shipped:** see `STATUS.md`. ROADMAP is the plan; STATUS is the ledger.

---

## Decisions already made (baked into the phases below)

| Decision | Value |
|---|---|
| **Shield systems** | Two architectures needed. **Physical shield:** actual collider mounted to mech front that blocks raycasts and catches projectiles; flanking physically defeats it; shield has HP; optional slow regen; at 0 HP the collider is disabled. **Energy shield:** damage-absorbing pool with regen delay + regen rate; hits route to shield first then HP; visual feedback via emissive body flash. Both systems live in parallel — a mech's `MechDef` declares which (or neither). |
| **Reload: two magazine types** | **Fixed magazine:** reload all-at-once when empty or on manual R press. **Refilling magazine:** ammo constantly regens at a fixed rate significantly slower than fire rate; sustained firing depletes, pausing refills. Per-weapon in design sheet (RWF column). |
| **Arena One tone** | Mathematical temple. Continue white/grey/blue palette. |
| **Weapon firing model** | **Left-click** = fire all equipped weapons simultaneously. **Right-click** = fire only the subset toggled active. **Number keys multi-select:** press `1` adds/removes slot 1 from the right-click set. Multiple weapons can be active on right-click at once. |
| **Mech hardpoints up to 4 (or more)** | Design sheet has mechs with 1-3 weapons; architecture should not cap at 2. Current dual-weapon hardcoding needs generalizing. |
| **Slot sizing** | Hardpoints are Light or Heavy. Strict fit: Heavy slot = Heavy weapon only, Light slot = Light weapon only. Weapons that come in both sizes ship as separate `.tres` files. Heavy version fires slower and does ~2x damage. |
| **Hangar preview** | Option B: in-scene 3D diorama. Lineup of 3-6 mechs visible simultaneously (= lives per match). |
| **Lives per match** | Stub at 5. Make configurable 3-6. |
| **Weapon icons** | Ship colored-rect placeholders; art pass later. |
| **Audio pack** | Claude Code scaffolds; Jonathan downloads specific CC0 assets when listed. |

---

## Godot 4.6 landmines (Claude Code: read before writing code)

These are the patterns that already cost hours on this project. Do not rediscover them.

### Rendering pipeline

- **Renderer is Compatibility (OpenGL ES 3.0).** Forward+ features are unavailable. In particular:
  - `GPUParticles3D` is unreliable. Use `CPUParticles3D` or scripted mesh effects.
  - Dynamic point-light shadows are limited. Keep point-light count low (<4 active).
  - Volumetric fog, SDFGI, SSAO, SSR are unavailable. Don't reach for them.
- **Never use `depth_test_disabled` on transparent materials.** Sort order is undefined and flickering is the result. For screen-space overlays, use CanvasLayer + `Camera3D.unproject_position()`.
- **Prefer opaque emissive meshes over transparent ones** for flashes, sparks, shield effects. A pulsing emissive cube beats a translucent quad every time.
- **Do not create `Shader.new()` at runtime.** Async GPU compile means early `set_shader_parameter` calls get dropped. Always `load("res://shaders/foo.gdshader")` from a file.

### GDScript 4.6 quirks

- **`get_parent()` in `@onready` expressions is unreliable.** Lazy-init cross-boundary node refs on first method call, not in `_ready()`.
- **`max(0.0, -someFloat)` fails type inference.** Use `maxf()` with an explicit `: float` annotation.
- **Typed-dict access with custom Resource types is fragile.** Use untyped `var` when reading from dicts like `Game.loadout`.
- **Em-dashes in GDScript comments break the parser on Linux.** Hyphens only in `.gd` files. Em-dashes are fine in `.md`.
- **`.tres` files:** check that any new `MechDef` / `WeaponDef` field has a default value or every existing `.tres` fails to load silently.

### When to step out of GDScript

- Algorithmic work (tile generation, pathfinding preprocess, Penrose-style substitution) goes in `tools/*.py`, not runtime GDScript. The Penrose generator is the pattern. Follow it.
- Anything computed once and baked into constants: Python.

### Stop-loss rule

If any approach fails three times with different variations, **stop and reassess.** Post the symptoms, ask whether to pivot to a fundamentally different approach (different Godot feature, offline pre-compute, scope reduction). Do not keep tweaking the same failing strategy.

---

## Phase 1 — Quick wins (Claude-solo, low risk)

Pure state/UI work that follows existing patterns. Clear these first: they're fast, reduce the todo list, and build momentum.

1. **Delete scratch files.** `test_damage.gd` and `temp_recover.md`. Confirm unreferenced, then remove.
2. **Win/loss tracking.** Hook `BeaconMatch.on_match_ended` into `Game.profile`. Persist via `ConfigFile` in `user://`. Hangar reads from `Game.profile` instead of showing 0/0.
3. **Configurable bot difficulty.** Externalize `aim_jitter` and `reaction_time` in `AIInputSource.gd`. Three presets (Easy/Normal/Hard) in `Game.settings`.
4. **Settings screen.** New `scenes/ui/Settings.tscn`. Mouse sensitivity, bot difficulty, master volume (stub for Phase 5). Reachable from Hangar.
5. **Error handling for MechDef / WeaponDef loads.** If a `.tres` fails to load, fall back to a hardcoded default and log to stdout.

**Claude risk:** low. Straight-through implementations.

**Jonathan's job:** none until review.

---

## Phase 2 — Weapon system completion

Three pieces: generalizing the hardpoint count, the new firing model, and the two magazine types.

### 2a. Generalize hardpoint count

Current code assumes 2 weapons (`ProjectileGun` left, `RaycastGun` right). Design sheet has mechs with 1, 2, or 3 weapons, with "maybe more" on the horizon.

- `MechDef.weapon_slots` becomes an array of slot descriptors (size: Light/Heavy, local position). No fixed cap.
- `Mech.gd` iterates the array on spawn, instantiating weapons from `Game.loadout` per slot.
- HUD weapon bar renders N slots instead of 2.
- Keep `ProjectileGun` + `RaycastGun` working as the testing pair.

### 2b. New firing model

- Left-click fires **all equipped weapons** simultaneously.
- Right-click fires **only the active subset**.
- Number keys `1..N` toggle membership in the active subset. Pressing a key that's already active removes it. Default subset: all active, matching left-click until toggled off.
- HUD shows which slots are in the right-click subset (border highlight or filled-in indicator).

### 2c. Two magazine types

- `WeaponBase` gets a `magazine_type` enum: `FIXED` (reload all-at-once) or `REFILLING` (constant regen).
- `FIXED`: existing plumbing, plus `reload_time` and R-key manual reload. Auto-reload on empty fire. Cannot fire during reload. HUD ammo bar pulses or greys during reload.
- `REFILLING`: `refill_rate` ammo/sec, starts regenerating immediately. No reload concept; just can't fire when empty. Rate is always slower than sustained fire rate, so burst-fire is the feel.

### Per-weapon magazine assignments (from design sheet RWF column)

| Weapon | Magazine type |
|---|---|
| Rifle | REFILLING |
| Laser Cannon | REFILLING |
| Arc weapon | FIXED |
| Machine Gun | FIXED (empties mag fast, reloads at once) |
| Shotgun | REFILLING |
| Rocket Launcher | FIXED (single-shot) |
| Sniper | FIXED |
| Missile Launcher | REFILLING |
| Aerial Strike | FIXED (single-shot) |
| Patience | FIXED (single-shot, with charge mechanic — see Phase 4) |

**Claude risk:** low-medium. Hardpoint generalization touches several files. Magazine types are clean state.

**Jonathan's job:** playtest reload timings and refill rates, report numbers to tweak.

---

## Phase 3 — Feel pass: camera, legs, shields

### 3a. Camera shake on weapon fire

- `Camera3D` child on mech. Small shake function: offset transform with decaying noise for ~0.15s.
- Expose `shake_magnitude` per weapon. Rocket shakes more than Rifle.
- Use `Tween` or manual decay in `_process`. No shaders.

### 3b. Leg system polish per mech class

- `BipedLegs.gd` already has the walk cycle. Add exported params: `step_cycle_duration`, `bob_magnitude`, `hip_sweep_amount`.
- `Mech.gd` sets these from `MechDef` on spawn. Slip fast/small, Vesuvius slow/big.

### 3c. Shield systems (two architectures)

Both must be supported since the roster has both kinds. Build the architecture now; individual mechs opt in via `MechDef`.

**Physical shield (Everest and future mechs):**
- `MechDef.physical_shield`: a dict or sub-resource with `shield_hp`, `regen_rate` (0 = no regen), `mount_position`, `mount_size`.
- Implemented as an actual `StaticBody3D` child with a `CollisionShape3D`, mounted on a `Node3D` attached to the mech front.
- Raycasts hit the shield's collider before hitting the mech body. Projectiles collide with shield first.
- Shield has its own HP pool. Damage decrements shield HP.
- At 0 HP: collider disabled, shield mesh hidden (or plays a break animation).
- Flanking works because the shield is a physical object — shots from the side/rear bypass it naturally.
- Visual: opaque mesh with a subtle emissive pulse when hit. Everest = white/silver paladin shield to match chassis.

**Energy shield (future mechs, architecture only for now):**
- `MechDef.energy_shield`: dict with `shield_max`, `regen_delay`, `regen_rate`.
- `Mech.take_damage()` routes to shield pool first, then HP.
- Any damage resets the regen timer. After `regen_delay` seconds with no damage, pool regens at `regen_rate`/sec.
- Visual: emissive body flash on absorb — **do not use transparent bubble meshes** (see landmines).
- HUD: blue shield bar above the red HP bar (player and bot views).
- No mech currently uses this, but stub a test mech to verify it works end-to-end.

**Claude risk:** low-medium. The physical shield has one gotcha: mounting the collider to follow mech rotation and making sure projectiles' collision layers actually interact with it. Test with a single ray before building the whole flanking loop.

**Jonathan's job:** playtest Everest shield, confirm flanking feels right, tune HP values.

---

## Phase 4 — Content expansion: mechs and weapons

Everything here follows the design sheet. Build incrementally so each addition exercises one new feature at a time.

### 4a. Weapon build order

Do weapons in dependency order — each new one adds one or two new features to the base pattern. **Start every weapon from the simplest form; don't pre-generalize a mega-superclass.**

| # | Weapon | New mechanic introduced |
|---|---|---|
| 1 | Rifle (L/H) | Baseline: straight projectile, refilling mag. Existing `ProjectileGun` can likely be renamed / extended. |
| 2 | Sniper (L/H) | Projectile, fixed mag, long range, low fire rate, high damage, fast projectile. |
| 3 | Machine Gun (L/H) | Fixed mag, accelerating fire rate while held, resets on release (cap at some max rate). |
| 4 | Shotgun (L/H) | Multi-projectile spread per shot. Damage varies with range (high point-blank, low at max). |
| 5 | Missile Launcher (L/H) | Fast-firing projectile with splash damage. Short range, refilling mag. |
| 6 | Rocket Launcher (L) | Single-shot, homing. Arcs up then tracks target down. Requires target lock. |
| 7 | Laser Cannon (L/H) | Continuous beam (instant hit). Damage-per-second model, not per-shot. Refilling mag acts as overheat budget. |
| 8 | Arc weapon (L/H) | Continuous homing beam with curved path. Requires target lock. Fixed mag. |
| 9 | Aerial Strike (H) | Single-shot, locked target, fires straight up, tracks and descends with AoE damage. |
| 10 | Patience (H) | Single-shot, charge-on-ready: "reload" brings it to charging state, charge builds slowly, damage scales with charge at fire time. Release fires. |

**Whirlwind flags in this list:**
- **Rocket Launcher and Arc** both need target lock. Build the target-lock system once (camera-center ray → pick closest mech in cone → visual lock indicator), use for both. Don't rebuild.
- **Homing behavior** uses simple proportional steering (bullets move way faster than mechs, so naive "steer toward target's current position" reads fine). Don't pre-optimize with prediction until it actually misses.
- **Patience's charge mechanic** is unlike anything else in the list. Build it last so the rest of the magazine/fire system is stable. The "reload then charge" two-stage state machine is the tricky part — draw it out before coding.
- **Laser/Arc continuous beam:** damage tick interval must be consistent (e.g., damage every 0.1s) not per-frame or framerate changes TTK.

### 4b. Mech roster from design sheet

Replace current `Lynx` / `Hippogriff` / `Warhog` with the canonical roster. Keep the current three working as placeholders until new ones land, then retire them.

| Mech | Class | Slots | HP | Speed | Size | Ability / Feature | Visual |
|---|---|---|---|---|---|---|---|
| Slip | Light | 1 L | Low | Very fast | Small | — | Sleek silver |
| Cesh | Light | 1 L | Low | Medium | Small | **Stealth** (passive: hides nametag/HP bar, visual blend) | Dark green, unobtrusive |
| Seeker | Light | 1 H | Low | Medium-fast | Very small | — | Red |
| Hornet | Medium | 2 L (side-mounted) | Medium | Fast | Medium | — | Blue + yellow, F-18 Blue Angel styling |
| Hippogriff | Medium | 3 L | Medium | Medium | Medium | — | Beige, B-29 styling |
| Pegasus | Medium | 2 L | Low | Medium | Medium | **Jump + heal** (active ability) | White + pale blue, painted wings |
| Everest | Heavy | 2 H | High | Very slow | Large | **Physical front shield** (low regen) | White paladin/knight |
| Vesuvius | Heavy | 3 H | High | Slow | Large | — | Black/grey mountainous, crimson highlights |

**Per-weapon-class scaling rule:** Heavy weapons fire slower and deal ~2x damage vs. their Light counterparts.

**Claude risk:** low to medium per weapon. Weapons 1-5 are low. Weapons 6-10 are medium-high feature complexity. The main whirlwind risk is trying to build all 10 at once with a shared mega-class — don't. Incremental, one at a time, test each before the next.

**Jonathan's job:** visual review of each mech, balance pass on damage/fire rate/HP numbers after a few playtests.

---

## Phase 4b — Mech ability system

Pegasus has a jump+heal, Cesh has stealth, future pilots may add abilities too. The original architecture notes already specify `Ability` as first-class with trigger/cooldown/effect, contributed by both mechs and pilots.

- `Ability` resource: `name`, `trigger` (active-key / passive), `cooldown`, `effect` (Callable or sub-resource).
- `MechDef.abilities: Array[Ability]`.
- `Mech.gd` collects abilities from both `MechDef` and the active `Pilot` on possess.
- Active abilities bind to a key (Q / E / F for three slots).
- Passive abilities apply continuous modifiers or hooks on spawn.

**Specific implementations:**
- **Pegasus jump+heal:** active, press Q. Impulse upward (existing physics jump) + restore N HP. Cooldown ~8s.
- **Cesh stealth:** passive. Hides nametag and health bar from enemies. Visual: low-opacity body or shader-driven desaturation. Can still be shot and hit normally — stealth is an information game, not invulnerability. **Tricky bit:** the bot HP bar is 2D screen-space projection; stealth needs to hide it for enemy players but keep it visible for teammates. In single-player vs. bots, "enemy player" = the human. In team matches (Phase 8.5), this needs a team check.

**Claude risk:** low for the system; medium for Cesh stealth because of the team-awareness visual logic. Stub the team check as "always enemy" for now.

**Jonathan's job:** design more abilities over time; tune cooldown/magnitude.

---

## Phase 5 — Audio (medium risk)

Audio is where Godot projects stall on "why doesn't this play." Scaffold first, content pass second.

### Workflow

1. **Claude Code creates `audio/` scaffolding and bus layout.**
   - `default_bus_layout.tres`: Master, SFX, Music. Master volume in `Game.settings`.
   - Folders: `res://audio/weapons/`, `footsteps/`, `ui/`, `ambient/`, `impacts/`, `abilities/`.
   - `AudioStreamPlayer3D` for 3D world sounds; `AudioStreamPlayer` for UI.
2. **Claude Code wires playback hooks with placeholder empty streams first.**
   - `WeaponBase.fire()` → fire sound per weapon.
   - `BipedLegs.gd` step-cycle events (foot-down moments) → footstep (per-mech variant via `MechDef`).
   - `Mech.take_damage()` → impact sound.
   - `Beacon` state change → capture/lost/contested stinger.
   - `Match.on_match_ended` → victory/defeat stinger.
   - Ability activations (Pegasus jump, etc.) → ability sound.
   - UI buttons → click.
3. **Claude Code lists specific CC0 files to download** from Kenney.nl (Sci-Fi Sounds, Interface Sounds, Impact Sounds — CC0 zip downloads) and Sonniss GDC Game Audio Bundle (CC0, ambient/footsteps). Jonathan downloads and drops in folders.
4. **Claude Code updates placeholder `AudioStream` exports to point at real files.**

### Whirlwind warnings

- Don't debug silence without checking Master, bus, stream, and player volumes first. Print all four on first fire.
- `.wav` sometimes needs loop-mode corrected on import. `.ogg` usually works out of the box.
- `AudioStreamPlayer3D` needs a listener. The `Camera3D` is listener by default — verify if camera hierarchy has changed.

**Claude risk:** medium. Scaffolding is easy; the silence debug loop can burn hours if not disciplined.

**Jonathan's job:** download packs when Claude lists them.

---

## Phase 6 — Visual FX (high risk — read mitigation)

Muzzle flash, hit sparks, death explosion, shield visuals. Default to opaque emissive meshes + Tween. Not particles. Not transparency.

### Approach per effect

- **Muzzle flash.** Short-lived emissive `MeshInstance3D` at muzzle, tween emission 1.0 → 0.0 over 0.08s, free. Color by weapon type.
- **Bullet tracer.** Already exists. Keep.
- **Laser/Arc beam visual.** Opaque emissive cylinder (or a line of emissive cubes along the beam) rendered during fire. Arc weapon: bend along spline toward target. No transparency.
- **Hit spark.** 3-4 tiny emissive cubes at hit point, scale up + fade emission over 0.2s. Free on timer. No `GPUParticles3D`, no transparent quads.
- **Death explosion.** Emissive sphere scales up while fading over 0.3s. Optionally a few rigid-body chunk meshes that fly outward, despawn after 2s. Chunks are opaque — no sort-order problem.
- **Physical shield hit.** Brief emissive pulse on the shield mesh. If shield HP depletes, play a break animation: split into chunks, fade, disable collider.
- **Energy shield hit.** Emissive body flash on the mech (not a bubble).
- **Stealth visual (Cesh).** Lower the material's emission energy and desaturate albedo via material swap or shader uniform. No transparency tricks.
- **Recoil screen kick.** Already in Phase 3a as camera shake.

### Whirlwind warnings

- `GPUParticles3D` in Compatibility: don't.
- `CPUParticles3D` works with reduced features. Use only if scripted mesh tweens genuinely can't achieve the effect.
- Any transparent material with `depth_test_disabled`: forbidden.
- If a flash is flickering or popping behind other geometry: sort-order is back. Stop. Rebuild as opaque emissive. Don't reach for render priority.

**Claude risk:** medium-high. Mitigated by sticking to opaque emissive + Tween. If that approach fails, stop and ask before reaching for particles or shaders.

**Jonathan's job:** visual review of each effect.

---

## Phase 7 — Arena polish

Three pieces, all optional for gameplay but big for feel.

### 7a. Floor art (hat tile pattern)

- `tools/hat_tile_gen.py` outputs either a GDScript const with tile positions or a baked mesh resource. Follow `penrose_gen.py` exactly.
- Mesh approach probably beats texture at mech-scale.
- White/grey/blue palette continues.

### 7b. Lighting pass

- `DirectionalLight3D` sun, cool blue-white.
- 2-3 point lights at center bowl + corners. Keep count low.
- Try baked lightmaps for static geometry. If baking fails twice, fall back to dynamic + ambient. Don't burn hours.

### 7c. Fractal wall/ceiling art (mathematical temple)

- Python tool in `tools/` generates relief geometry or textures. Could be a recursive geometric pattern (Koch-style, or simple subdivided triangles) baked into mesh data.
- Walls first; ceilings optional.

**Claude risk:** low for 7a/7c if Python-generated; medium for 7b.

**Jonathan's job:** review art passes.

---

## Phase 8 — Hangar 3D diorama

Per decision table: Option B, in-scene 3D. And: show a **lineup of 3-6 mechs** matching the player's lives-per-match (stubbed at 5).

- Hangar is a 3D scene. Camera looks at a row of mech positions on a turntable-like platform.
- N mech positions, slowly rotating in place. Hovering or selecting a mech pulls it forward or highlights it.
- UI in CanvasLayer: mech stats, weapon loadout, match-start button.
- When player changes loadout, the mech in the lineup swaps chassis live.
- On match start, the selected starting mech is the one the player spawns as; the rest are the hangar queue.

**Claude risk:** low. Composition work.

**Jonathan's job:** visual review, tune turntable speed and lighting.

---

## Phase 8.5 — Offline team vs team

Inserts before multiplayer. 5v5 or 6v6 (TBD) with bots on both teams. Arena sized for the team count.

### Scope

- Bigger arena (new or re-scaled Arena One, or a new arena) sized for 10-12 mechs.
- `Match` spawns configurable team counts. Each bot has a `Pilot` and a `MechDef`.
- Team identifiers already exist in the architecture — verify they propagate correctly to bots.
- HUD: team score, kill feed, minimap showing teammates and visible enemies.

### Bot AI improvements (the hard part)

This is where the whirlwind risk is highest outside multiplayer. The current `AIInputSource` is a single-bot target-tracker + beacon-grabber. For team play it needs:

- **Role assignment.** Bots get roles at match start: attacker, defender, flanker, etc. Role biases behavior (beacon priority, positioning, weapon use).
- **Coordination.** Bots share lightweight "intent" signals — "I'm pushing beacon A" — so allies don't all converge on the same objective. Simple blackboard pattern in an `AIDirector` autoload per team.
- **Smarter cover pathing.** Current cover-avoidance gets stuck occasionally. Bake a NavigationMesh for each arena; let bots path via `NavigationAgent3D` instead of raw steering. This alone fixes most stuck-on-wall cases.
- **Threat assessment.** Bots should retreat when low HP, focus fire weak enemies, etc.

### Whirlwind warnings

- **"Fun to play against" bot AI is a tall order** — Jonathan called this out. Don't try to build a grand unified AI in one pass. Build in increments: role assignment first (easy win), then blackboard coordination (medium), then navmesh pathing (medium), then threat assessment (hard). Ship after each.
- **NavigationMesh baking** has its own Godot quirks. Budget it as its own sub-task; if auto-baking fails on the arena geometry, hand-author nav volumes.
- Bot tuning needs playtesting. A lot. This phase is iterative by nature, not a build-once-and-done.

**Claude risk:** high overall, broken into smaller medium-risk chunks.

**Jonathan's job:** playtest every bot change, report what feels dumb.

---

## Phase 9 — Multiplayer (deferred)

Server-authoritative with client prediction, via `MultiplayerAPI` and `MultiplayerSynchronizer`. `InputSource` split is already in place — bots are fake clients, so the architecture is ready.

**This is the hardest remaining work on the project.** Do not start Phase 9 until Phases 1-8.5 are shipped and the single-player + team-vs-bots loops are fun.

**Whirlwind risk:** high across the board. Network code, authority model, prediction/reconciliation, lag compensation — each is a multi-hour debugging surface. Budget accordingly.

---

## Risk summary (one-glance table)

| Phase | Task | Claude risk | Jonathan involvement |
|---|---|---|---|
| 1 | Scratch cleanup / win-loss / bot difficulty / settings / error handling | Low | Review |
| 2a | Generalize hardpoint count | Low-med | Review |
| 2b | New firing model (left-all, right-subset, number-key toggle) | Low | Playtest |
| 2c | Two magazine types | Low | Tune values |
| 3a | Camera shake | Low | Tune magnitudes |
| 3b | Leg polish per class | Low | Tune per mech |
| 3c | Physical shield system (Everest) | Low-med | Playtest flanking |
| 3c | Energy shield system (future-proof) | Low | — |
| 4a | Weapons 1-5 (Rifle/Sniper/MG/Shotgun/Missile) | Low each | Tune, playtest |
| 4a | Rocket + Arc (target lock + homing) | Med | Tune |
| 4a | Laser (continuous beam) | Med | Tune |
| 4a | Aerial Strike | Med | Tune |
| 4a | Patience (charge mechanic) | Med-high | Tune |
| 4b | Full mech roster | Low | Visual review |
| 4b | Mech ability system + Pegasus jump-heal | Low-med | Tune |
| 4b | Cesh stealth | Med (team-aware visual) | Playtest |
| 5 | Audio scaffolding + content pass | Med | Download packs |
| 6 | Visual FX (emissive mesh approach) | Med-high | Visual review |
| 7a | Floor hat-tile art | Low | Review |
| 7b | Lighting pass | Med | Review |
| 7c | Fractal art pass | Low-med | Confirm direction |
| 8 | Hangar 3D lineup | Low | Review |
| 8.5 | Team vs team arena + match logic | Med | Playtest |
| 8.5 | Bot role assignment | Low-med | Playtest |
| 8.5 | Bot blackboard coordination | Med | Playtest |
| 8.5 | Navmesh pathing | Med | — |
| 8.5 | Bot threat assessment | High | Playtest heavily |
| 9 | Multiplayer | High throughout | Heavy |

---

## What Jonathan can do faster than Claude

- **Sourcing audio assets.** Two minutes of human download work beats Claude describing files it can't hear.
- **Visual judgment on feel** (camera shake magnitude, reload timing, shield feedback, leg cycle speed, bot difficulty). Claude can't see the screen. Set param, spawn, look, report a number.
- **Playtesting.** All of it. Especially Penrose walls, bot behavior, team-vs-team dynamics.
- **Tone/visual decisions** (mech color variations, weapon icon style if/when art pass happens).
- **Priority calls within a phase** when Claude asks what's next.

Everything else: offload to Claude.

---

## Rules for Claude Code while working this doc

1. Read "Godot 4.6 landmines" before every new feature. Those patterns already cost this project hours.
2. If an approach fails three times with different variations, stop and ask about pivoting.
3. Prefer opaque emissive meshes with Tweens over particles or transparent materials. Always.
4. Algorithmic/generator work goes in `tools/*.py`, not runtime GDScript.
5. Plain hyphens only in `.gd` comments. Em-dashes fine in `.md`.
6. When building Phase 4 weapons, do them one at a time in the listed order. Do not pre-generalize a mega-superclass.
7. Commit after each task in a phase completes. Small, frequent commits.
8. Update `STATUS.md` as items ship.
