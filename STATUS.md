# MechBattle — Project Status

This file tracks **what has shipped**. For what's planned and what to build next, see `ROADMAP.md`.

---

## Shipped

### Phase 3b — Leg system polish per mech class (2026-04-17)
- `BipedLegs.gd` constants `HIP_SWING`, `BODY_BOB`, `CYCLE_RATE` converted to `@export var` (`hip_sweep_amount`, `bob_magnitude`, `cycle_rate`)
- `MechDef` gains `leg_hip_sweep`, `leg_bob_magnitude`, `leg_cycle_rate` (defaults match prior hardcoded values)
- `Mech.configure_legs()` pushes values to legs node after spawn; Arena calls it for both player and bot
- Lynx: hip=0.16, bob=0.03, rate=2.4 (quick, tight); Warhog: hip=0.32, bob=0.12, rate=1.2 (heavy, slow)

### Phase 3a — Camera shake on weapon fire (2026-04-17)
- `WeaponBase.shake_magnitude` export (radians); 0 = no shake; per-weapon tunable
- `Mech.apply_camera_shake(magnitude)` decays over 0.15s using `_shake_timer`/`_shake_intensity`
- `Mech._process` owns `camera_arm.rotation.x` = `_camera_pitch` + live shake offset; `_handle_look` no longer sets it directly
- ProjectileGun: 0.03 rad; RaycastGun: 0.015 rad

### Phase 2 — Weapon system completion (commit c210cde, 2026-04-17)
- Hardpoint generalization: `Mech._get_hardpoints()` scans `Torso/Hardpoint*`; `get_weapons()` / `get_active_set()` public API; no fixed cap
- `MechDef.weapon_slots: Array` replaces `hardpoint_count`
- Firing model: left-click = all weapons; right-click = active subset; number keys 1-4 toggle slots; dimmed HUD icon = inactive
- Magazine types: `FIXED` (reload all-at-once, R key, auto-reload on empty) and `REFILLING` (constant regen); ammo bar greys during reload
- Input actions: `weapon_slot_1..4`, `reload`

### Phase 1 — Quick wins (commit 46e8593, 2026-04-17)
- Scratch files deleted (`test_damage.gd`, `temp_recover.md`)
- Win/loss tracking: `_on_match_ended` updates `Game.profile`, persisted to `user://profile.cfg`
- Bot difficulty: Easy/Normal/Hard presets in `AIInputSource.DIFFICULTY_PRESETS`, read from `Game.settings.bot_difficulty`
- Settings screen: `scenes/ui/Settings.tscn` — mouse sensitivity, difficulty buttons, master volume stub; saves to `user://settings.cfg`
- MechDef load failures: `push_error` + Hippogriff fallback in Arena; `push_error` + skip in Hangar
- Fixed em-dash comments in `AIInputSource.gd` that break the Godot 4.6 Linux parser

### Core Game Loop
- Full boot flow: TitleScreen → SignIn (call sign entry) → Hangar → Arena → Hangar on match end
- Beacon capture match: 5 pentagon beacons at r=25m; drain scoring, first team to 0 loses
- Player vs. bot match with win/loss result screen
- Mouse capture / release (Escape key)

### Mech System
- `MechDef` resource: name, speed, HP, shield flags, `body_scale`, weapon slots; `description` field added
- Named roster: **Lynx** (Light, 200hp, 6.3 m/s), **Hippogriff** (Medium, 500hp, 3.15 m/s), **Kestrel** (Medium, energy shield), **Warhog** (Heavy, 900hp, physical front shield, 1.8 m/s)
- Dual-weapon loadout: ProjectileGun (left, 50 dmg, 1/s) + RaycastGun (right, 10 dmg, 2/s hitscan)
- Step climbing: `_try_step_up` handles 0.40 m ledges; probes both input dir and velocity; gradual lift at 2.5 m/s
- Mech death: `died` signal, `take_damage()`, hidden on death

### Visuals
- Multi-part mech body: waist, torso, shoulder plates, head — all MeshInstance3D children auto-colored
- Three-segment digitigrade legs: LeftHip → LeftKnee1 → LeftKnee2; crouched S-curve silhouette
- `BipedLegs.gd` walk cycle: hip sweep (-cos), swing lift (sin), stance flex, body bob with camera inherit
- Player mech: blue tint with emission; bot mech: red tint with emission
- Arena One: Penrose data baked into Arena.gd as GDScript constants; pentagon bowl (4 step rings); columns and temple walls built (behind `DEBUG_PENROSE` flag, not yet playtested)

### HUD
- Crosshair: pixel-accurate, hit indicator (diagonal red lines flash on confirmed hit)
- Yellow bullet tracer from muzzle; red damage flash on player hit
- Player health bar: top-left ColorRect, 162x22px, green shrinks right
- Bot health bar: screen-space projection via `Camera3D.unproject_position()`, red 32x6px ColorRect
- Weapon HUD: bottom-right colored icon slots (yellow=hitscan, orange=projectile), green ammo bar, number key labels

### Bot AI
- Tracks player, vertical aim, beacon capture behavior, burst fire + aim jitter
- Stuck detection and recovery
- Navigation around cover objects (imperfect but functional)

### Weapon System
- `WeaponBase`: `max_ammo` export (-1 = infinite), ammo counter, blocks fire when empty
- Projectile aim fix: ray from camera center finds crosshair target, barrel aims toward that point
- Hit confirmation signal back to HUD crosshair

### Infrastructure
- Godot 4.6 / GDScript; Linux x86_64 build at `build/mechbattle.x86_64`
- Viewport 640x360 stretched to 1280x720
- `Game.gd` singleton: profile (wins/losses/pilot_name, persisted) + settings (sensitivity/difficulty, persisted)
- `InputSource` interface: `PlayerInputSource` + `AIInputSource`; same `Mech._handle_fire()` path for both
- `Player.gd` / `Pilot.gd` separation; `possess()` pattern

---

## Issues Encountered (and How They Were Solved)

| Problem | Root Cause | Solution |
|---|---|---|
| Bot health bar black at idle | `Shader.new()` triggers async GPU compile; `set_shader_parameter` from `_ready()` discarded | Load shader from file (`load("res://shaders/foo.gdshader")`) so it's pre-compiled |
| World-space billboard health bars flickered | `depth_test_disabled` objects have undefined sort order in Godot 4 transparent pass | Abandoned world-space approach entirely; use `Camera3D.unproject_position()` + 2D CanvasLayer |
| `@onready var x = get_parent().get_node(...)` fails | `get_parent()` in `@onready` expressions is unreliable in Godot 4.6 | Lazy-init cross-boundary node refs on first method call, not in `_ready()` |
| `max(0.0, -someFloat)` type inference error | GDScript 4.6 can't infer return type of `max()` on negated variables | Use `maxf()` + explicit `: float` annotation |
| Em-dash in comments breaks script loading | Encoding/parser edge case in Godot 4.6 on Linux | Use plain hyphens only in `.gd` comments |
| Step climbing would miss ledges or over-trigger | Only probing input direction missed diagonal ledges; instant teleport felt wrong | Probe both `_desired_move_dir` and `velocity`; apply lift gradually at 2.5 m/s with `_step_up_remaining` |
| Step climbing broken from non-center spawn; legs rotated 90° at walls | `ConcavePolygonShape3D.backface_collision=false` (default) — shin raycast only hit front face; inner wall normals point inward, so mech approaching from outside hit back face silently | `backface_collision=true`; widen rays to 0.8 m; lower velocity threshold to 0.01; fire `_step_up_remaining` only once per step to prevent overshoot hop |
| Mouse sensitivity reverted on every session start | `min_value=0.001` assignment in `_ready()` clamped slider from 0→0.001 and fired `value_changed`, overwriting saved value before it was loaded | Block slider signals during init with `set_block_signals(true/false)` |
| MechDef type hints cause parse errors in Arena/Hangar | GDScript typed dict access with custom Resource types is fragile | Use untyped `var` when reading from `Game.loadout` dict |
| Projectile aim was wrong at close range | Barrel aimed along mech forward, not toward crosshair target | Cast ray from camera center → crosshair target, then aim barrel toward the hit point |
| Penrose generator in GDScript was impractical | Recursive substitution in GDScript too slow/complex for interactive tuning | Rewrote as `tools/penrose_gen.py` (pure Python, de Bruijn method); outputs GDScript consts directly |
| Shots bypassing Warhog's front shield | Mech capsule (radius 0.5) front face at z=-0.5 was 5 cm ahead of shield box front face (z=-0.45); raycast hit capsule first | Moved PhysicalShield z from -0.42 to -0.55; front face now at z=-0.58, clear of capsule |

---

## File Map (quick reference)

```
scenes/
  arena/     Arena.gd + Arena.tscn   -- match setup, Penrose geometry, step rings
  beacon/    Beacon.gd               -- capture zone logic
  mech/      Mech.tscn               -- mech hierarchy (body, legs, hardpoints, camera)
  ui/        Hangar, TitleScreen, SignIn, HUD, Settings
  weapons/   ProjectileGun, RaycastGun scenes

scripts/
  Mech.gd             -- movement, step climb, fire dispatch, death
  BipedLegs.gd        -- walk cycle (hip sweep, swing lift, body bob)
  AIInputSource.gd    -- bot brain; DIFFICULTY_PRESETS for Easy/Normal/Hard
  PlayerInputSource.gd
  WeaponBase.gd       -- ammo, fire rate, hit signal
  ProjectileGun.gd / RaycastGun.gd
  WeaponHUD.gd / HUD.gd / Crosshair.gd
  Settings.gd         -- settings screen logic
  MechDef.gd          -- Resource: stats, weapons, body_scale
  BeaconMatch.gd / Match.gd / Player.gd / Pilot.gd
  Game.gd             -- singleton: profile + settings (both persisted via ConfigFile)

autoloads/
  Game.gd             -- see above

tools/
  penrose_gen.py      -- de Bruijn Penrose generator; outputs GDScript consts
```
