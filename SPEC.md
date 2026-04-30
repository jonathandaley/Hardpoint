# SPEC

## §G GOAL

Mech arena FPS, single-player vs bots, beacon capture win condition. Fun solo first; multiplayer deferred.

## §C CONSTRAINTS

- Engine: Godot 4.6, GDScript. No other runtime.
- Renderer: Compatibility (OpenGL ES 3.0). ⊥ Forward+ features (no SDFGI, SSAO, volumetric fog, SSR, GPUParticles3D reliable).
- Target hardware: T3500-class. Viewport 640x360 → 1280x720 nearest-neighbor.
- OS: Linux x86_64 (Debian). Binary at `build/mechbattle.x86_64`.
- Budget: CC0/free assets only.
- Autoloads: `Game.gd`, `SoundManager.gd`, `VFX.gd`. ⊥ add more.
- Algorithms / one-time bake → `tools/*.py`. ⊥ runtime GDScript for offline computation.
- No paid tools.
- GDScript landmines (must re-read before new code):
  - `get_parent()` in `@onready` → unreliable; lazy-init cross-boundary refs on first call.
  - `max(0.0, -x)` → type error; use `maxf()` + `: float` annotation.
  - Em-dashes in `.gd` comments → parser crash on Linux; hyphens only.
  - Typed dict access with custom Resource → fragile; use untyped `var`.
  - `Shader.new()` at runtime → async GPU compile drops early `set_shader_parameter`; always `load("res://...")`.
  - `.tres` fields need default values or silent load failure.
  - `depth_test_disabled` transparent materials → undefined sort order → flicker; ⊥ use.
  - If approach fails 3x with variations → stop, report symptoms, ask to pivot.
- Lives per match: configurable 3-6; stub at 5.
- Visuals: opaque emissive meshes + Tween for FX. ⊥ transparent bubbles, ⊥ GPUParticles3D.

## §I INTERFACES

- run: `build/mechbattle.x86_64` → game window
- controls: WASD move | mouse look | LMB fire-all | RMB fire-active-subset | 1-4 toggle slots | R reload | Esc uncapture mouse
- persist: `user://settings.cfg` (sensitivity, difficulty) | `user://profile.cfg` (wins, losses, pilot_name)
- data: `MechDef` `.tres` in `resources/mechs/` → Arena reads & spawns mechs
- singleton: `Game.profile` & `Game.settings` read/write via `ConfigFile`
- architecture: `InputSource → Player → Mech → Weapons`; `AIInputSource` & `PlayerInputSource` interchangeable
- arena entry: `Arena.gd` reads `Game.loadout` (untyped dict) → instantiates player + bot mechs + weapons

## §V INVARIANTS

V1: ∀ control input → routes through `InputSource`; `Mech` ⊥ reads raw input directly
V2: `Player/Pawn` split ! exist from day 1; retrofitting is ⊥ acceptable
V3: `Mech` ignorant of weapon type; calls `fire()` on child nodes only
V4: new weapon = new `.tscn`; ⊥ mech code changes required
V5: only `Game.gd`, `SoundManager.gd`, `VFX.gd` as autoloads; ⊥ more added
V6: ⊥ `Shader.new()` at runtime; load from file only
V7: ⊥ `depth_test_disabled` on transparent mats; screen-space overlay → CanvasLayer + `Camera3D.unproject_position()`
V8: ∀ `.tres` field → has default value; ⊥ silent load failure
V9: heavy weapon fire rate slower & damage ~2x vs light counterpart
V10: REFILLING mag regen rate always < sustained fire rate; burst play feel required
V11: continuous-beam (Laser/Arc) damage ticks at fixed interval (e.g. 0.1s); ⊥ per-frame damage (TTK varies with framerate)
V12: physical shield collider front face ! clear of mech capsule front (∴ raycasts hit shield not capsule)
V13: algorithms & baked data → `tools/*.py`; ⊥ runtime GDScript for offline work
V14: `Game.loadout` dict access → untyped `var`; ⊥ typed Resource access
V15: bot AI target lock & homing → built once, shared by Rocket Launcher & Arc weapon; ⊥ duplicate system
V16: ⊥ em-dashes in `.gd` comments; hyphens only
V17: Heavy slot → Heavy weapon only; Light slot → Light weapon only; ⊥ cross-size fit

## §T TASKS

id|status|task|cites
T1|x|delete scratch files (`test_damage.gd`, `temp_recover.md`)|-
T2|x|win/loss tracking: hook `BeaconMatch.on_match_ended` → `Game.profile`, persist `user://profile.cfg`|-
T3|x|bot difficulty: Easy/Normal/Hard/Medium/Elite presets in `AIInputSource.DIFFICULTY_PRESETS`|-
T4|x|settings screen `scenes/ui/Settings.tscn` (sensitivity, difficulty, volume stub)|-
T5|x|MechDef load error handling: fallback + `push_error`|V8
T6|x|hardpoint generalization: `MechDef.weapon_slots` array, `Mech._get_hardpoints()` scans `Torso/Hardpoint*`|V3,V4
T7|x|firing model: LMB=all, RMB=active-subset, 1-4 toggle slots, HUD dimmed icon|V3
T8|x|magazine types: `FIXED` (reload all-at-once, R key) & `REFILLING` (regen/sec)|V10
T9|x|camera shake: `WeaponBase.shake_magnitude`, `Mech.apply_camera_shake()`, 0.15s decay|-
T10|x|leg params per mech: `hip_sweep_amount`, `bob_magnitude`, `cycle_rate` exports on `BipedLegs.gd`|-
T11|x|physical shield: `StaticBody3D` child on mech, HP pool, collider disable on break|V12
T12|x|energy shield: `EnergyShield` node, absorb pool, regen delay + rate, emissive body flash|V7
T13|x|Rifle L/H: straight projectile, REFILLING mag|V9
T14|x|Sniper L/H: long range, fixed mag, high dmg, fast projectile|V9
T15|x|Machine Gun L/H: FIXED mag, accel fire rate while held, spread|V9
T16|x|Shotgun L/H: pellet spread, range falloff damage_close → damage_far|V9
T17|x|Missile Launcher L/H: splash damage on impact, REFILLING mag|V9
T18|x|target lock system: `Mech.locked_target`, `lock_progress`, `_LOCK_TIME=3.0s`|V15
T19|x|Rocket Launcher L: single-shot, homing, arc up then track target down, requires lock|V15
T20|x|Laser Cannon L/H: continuous beam, fixed-interval DPS, REFILLING = overheat budget|V11,V9
T21|x|Arc weapon L/H: continuous homing beam, curved path, requires lock, FIXED mag|V11,V15,V9
T22|x|Aerial Strike H: single-shot, locked target, fires up, descends + AoE|V15
T23|x|Patience H: two-stage (reload → charge → fire), damage scales with charge, FIXED|-
T24|.|canonical mech roster: Slip/Cesh/Seeker/Hornet/Hippogriff/Pegasus/Everest/Vesuvius `.tres` -- visuals: Slip=sleek silver; Cesh=dark green; Seeker=red; Hornet=blue+yellow (F-18); Hippogriff=beige (B-29); Pegasus=white+pale blue; Everest=white paladin; Vesuvius=black/grey+crimson|V8
T25|x|mech ability system: `Ability` resource (trigger, cooldown, effect), `MechDef.abilities`|V2
T26|.|Pegasus jump+heal: active Q, impulse up + restore HP, ~8s cooldown|T25
T27|.|Cesh stealth: passive, hide nametag/HP bar from enemies, desaturate (stub team check = always enemy)|T25,V7
T28|.|audio scaffolding: bus layout (Master/SFX/Music), folders (`audio/weapons/footsteps/ui/ambient/impacts/abilities`), `AudioStreamPlayer3D` hooks (WeaponBase.fire, BipedLegs step, Mech.take_damage, Beacon state change, Match.on_match_ended, ability activations, UI clicks) with placeholder streams|-
T29|.|audio content: list CC0 files (Kenney/Sonniss), wire after Jonathan downloads|T28
T30|.|visual FX: muzzle flash (0.08s decay), hit sparks (3-4 emissive cubes, 0.2s), death explosion (emissive sphere 0.3s + optional opaque chunks), shield hit -- opaque emissive + Tween|V7
T31|.|floor art: `tools/hat_tile_gen.py` → baked mesh or GDScript consts|V13
T32|.|lighting pass: directional + 2-3 points, try baked lightmap (2 fail → fall back)|-
T33|.|fractal wall/ceiling art: `tools/fractal_wall_gen.py` → relief geometry|V13
T34|.|hangar 3D diorama: lineup 3-6 mechs, turntable platform, CanvasLayer UI, swap on loadout change|-
T35|.|team vs team: 5v5/6v6 bots, scaled arena, `Match` configurable team counts|-
T36|.|bot role assignment: attacker/defender/flanker, role biases beacon priority & positioning|T35
T37|.|bot blackboard coordination: `AIDirector` autoload per team, intent signals (pushing beacon A etc.)|T35,T36
T38|.|navmesh pathing: `NavigationAgent3D` + baked `NavigationMesh` per arena|T35
T39|.|bot threat assessment: retreat low HP, focus-fire weak enemies|T35
T40|.|multiplayer: `MultiplayerAPI`, server-authoritative, client prediction [DEFERRED until 1-8.5 fun]|V1,V2

## §B BUGS

id|date|cause|fix
B1|2026-04-17|`Shader.new()` async compile → `set_shader_parameter` in `_ready()` discarded → bot HP bar black|V6
B2|2026-04-17|`depth_test_disabled` world-space billboard sort undefined → flickering health bars|V7
B3|2026-04-17|`get_parent()` in `@onready` unreliable → node ref null at startup|-
B4|2026-04-17|`max(0.0, -x)` type inference fail → use `maxf()` + `: float`|-
B5|2026-04-17|em-dash in `.gd` comment → parser crash Linux|V16
B6|2026-04-17|step climb `_step_up_remaining` fired every frame → overshoot hop; fix: fire once per step|-
B7|2026-04-17|`min_value=0.001` in `_ready()` fired `value_changed` before saved value loaded → sensitivity reset; fix: `set_block_signals(true/false)` during init|-
B8|2026-04-17|typed dict access with custom Resource → parse errors in Arena/Hangar|V14
B9|2026-04-17|projectile barrel aimed along mech forward, not crosshair → aim wrong close range; fix: camera center ray → aim_point|-
B10|2026-04-17|Penrose substitution in GDScript too slow → moved to `tools/penrose_gen.py` (de Bruijn)|V13
B11|2026-04-21|Warhog capsule front (z=-0.5) ahead of shield face (z=-0.45) → raycast hit capsule, bypassed shield; fix: shield z → -0.55|V12
