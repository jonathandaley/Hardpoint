# MechBattle — Project Status

This file tracks **what has shipped**. For what's planned and what to build next, see `ROADMAP.md`.

---

## Shipped

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
- `MechDef` resource: name, speed, HP, shield flag, `body_scale`, weapon slots
- Named roster: **Lynx** (Light, 200hp, 6.3 m/s), **Hippogriff** (Medium, 500hp, 3.15 m/s), **Warhog** (Heavy, 900hp, shields, 1.8 m/s)
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
| MechDef type hints cause parse errors in Arena/Hangar | GDScript typed dict access with custom Resource types is fragile | Use untyped `var` when reading from `Game.loadout` dict |
| Projectile aim was wrong at close range | Barrel aimed along mech forward, not toward crosshair target | Cast ray from camera center → crosshair target, then aim barrel toward the hit point |
| Penrose generator in GDScript was impractical | Recursive substitution in GDScript too slow/complex for interactive tuning | Rewrote as `tools/penrose_gen.py` (pure Python, de Bruijn method); outputs GDScript consts directly |

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
