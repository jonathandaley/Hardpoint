# SPEC

## §G GOAL

Mech arena FPS, single-player vs bots, beacon-drain + kill-domination dual win condition. Fun solo first; multiplayer next after mech/weapon art + smarter AI. Art direction: Matrix 3 post-apocalyptic steam/cyberpunk ("guns, grease, grit, gears").

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
- Lives per match: 5 (fixed); each life uses next mech from pre-selected squad.
- Visuals: opaque emissive meshes + Tween for FX. ⊥ transparent bubbles, ⊥ GPUParticles3D.
- Art direction: Matrix 3 post-apocalyptic steam/cyberpunk. Rust, neon, grime, mechanical bulk.
- Abilities: ⊥ every mech requires one; optional. Pool: jump, dash, area-heal, flight, energy shield (passive). Shields count as passive ability slot.
- Maps: all maps have 5 beacons; geometry via Perlin noise; scale/cover/theme vary per map.
- Progression: ELO + XP; pilot level unlocks bonus tree (speed/reload/ability duration/damage/health); cosmetics via XP or coins; coins earned from wins, spent on progression or cosmetics.
- Accounts: online (email signup) when multiplayer ships; local profile only until then.

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
V18: ∀ maps → exactly 5 beacons; ⊥ map ships with different count
V19: win condition = beacon drain to 0; ⊥ time limit as primary win condition; ⊥ game ends on last-player death while squad lives remain

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
T24|x|canonical mech roster: Slip/Cesh/Seeker/Hornet/Hippogriff/Pegasus/Everest/Vesuvius `.tres` -- visuals: Slip=sleek silver; Cesh=dark green; Seeker=red; Hornet=blue+yellow (F-18); Hippogriff=beige (B-29); Pegasus=white+pale blue; Everest=white paladin; Vesuvius=black/grey+crimson|V8
T25|x|mech ability system: `Ability` resource (trigger, cooldown, effect), `MechDef.abilities`|V2
T26|x|Pegasus jump+heal: active Q, impulse up + restore HP, ~8s cooldown|T25
T27|x|Cesh stealth: passive, hide nametag/HP bar from enemies, desaturate (stub team check = always enemy)|T25,V7
T28|x|audio scaffolding: bus layout (Master/SFX/Music), folders (`audio/weapons/footsteps/ui/ambient/impacts/abilities`), `AudioStreamPlayer3D` hooks (WeaponBase.fire, BipedLegs step, Mech.take_damage, Beacon state change, Match.on_match_ended, ability activations, UI clicks) with placeholder streams|-
T29|.|audio content: background music pending; SFX wired|T28
T30|x|visual FX: muzzle flash (0.08s decay), hit sparks (3-4 emissive cubes, 0.2s), death explosion (emissive sphere 0.3s + optional opaque chunks), shield hit -- opaque emissive + Tween|V7
T31|x|floor art: `tools/hat_floor_tex.py` → hat_floor.png (1024px) UV-mapped to bowl mesh|V13
T32|x|lighting pass: directional + 2-3 points, try baked lightmap (2 fail → fall back)|-
T33|x|fractal wall/ceiling art: `tools/fractal_wall_gen.py` → exterior circular walls only (archived for interior); interior walls use `_PENROSE_SVG_EDGES` directly|V13
T34|.|hangar 3D diorama: lineup 3-6 mechs, turntable platform, CanvasLayer UI, swap on loadout change|-
T35|x|team vs team: 5v5/6v6 bots, scaled arena, `Match` configurable team counts (`Game.loadout["team_size"]`)|−
T36|.|bot role assignment: attacker/defender/flanker, role biases beacon priority & positioning|T35
T37|.|bot blackboard coordination: `AIDirector` autoload per team, intent signals (pushing beacon A etc.)|T35,T36
T38|x|navmesh pathing: `NavigationAgent3D` + baked `NavigationMesh` per arena; LOS raycast gates bot firing|T35
T39|.|bot threat assessment: retreat low HP, focus-fire weak enemies|T35
T40|.|multiplayer: `MultiplayerAPI`, server-authoritative, client prediction [DEFERRED until 1-8.5 fun]|V1,V2
T41|x|beacon capture: world-space capture-progress bar above each beacon (unproject_position, shows during capture/contested)|-
T42|x|beacon HUD widget: colored dot row (top-center) per beacon showing neutral/A/B/contested state|-
T43|x|beacon visual: 30m tall team-colored emissive beam + ground capture-radius circle (emissive CylinderMesh, r=3m)|-
T44|x|reload SFX: `reload_start_sound_key` / `reload_done_sound_key` exports on WeaponBase; wired in `_start_reload` and reload completion|T28
T45|x|cooldown indicator: gray overlay bar on Sniper weapon icon in WeaponHUD, driven by `get_cooldown_fraction()`|T7
T46|x|impact sound distance gate: `hit_impact` now played as 3D at hit position via `SoundManager.play_sfx`; uses existing attenuation|T28
T47|x|arc continuous beam: beam stays while trigger held; hides on `on_fire_release` / no lock / empty ammo; audio restarts only on beam-visible transition|V11
T48|x|beacon drain always-on: each captured beacon drains opponent by `points_per_tick * 0.25` per tick (was zero-sum advantage-based)|-
T49|x|match-end screen: "YOU WIN" / "YOU LOSE" shown; stats panel + return-to-hangar button (already existed in HUD.gd)|T2,T28
T50|x|aerial strike damage: 3x -- direct 1.6→4.8, splash 0.8→2.4|V9
T51|x|patience tuning: projectile speed 180→360 m/s; fading tracer beam via `VFX.tracer()` on fire|T23
T52|x|heavy sniper rebalance: clip 3→5, damage 80→60|V9
T53|.|weapon clip balancing pass: align L/H clip sizes across all weapon pairs then re-balance damage/RoF|V9,V10
T54|x|jump forward bias: horizontal impulse = facing_dir * walk_speed * 3 added on Pegasus jump|T26
T55|x|pegasus nerf: cooldown 8→16s|T26
T56|x|jump landing hurt flash removed: `damaged.emit()` no longer called from `jump_heal` activation|−
T57|.|spawnpoints multi-life: spawnpoint logic activates only once lives > 1; no-op until T35 lives system|T35
T58|x|spectate on death: `Arena.gd` switches camera to ally mech on player death, cycles on next ally death; `HUD.start_spectating()` hides crosshair/weapon HUD, shows "SPECTATING: <NAME>" label|T35
T59|.|ally bot health bars: `setup_bot_bars` currently receives `_team_mechs[1]` only; pass `_team_mechs[0][1..]` with distinct color (e.g. green) so friendly bots show world-space HP bars|T35
T60|.|beacon HUD dot X positions match beacon physical XZ layout in arena (proportional horizontal spread), not fixed center strip|T42
T61|.|weapon range system: `range` export already set per weapon in `.tscn`; enforce hitscan cutoff + projectile self-destruct at range in `WeaponBase`|V9
T62|.|arena column repositioning: redistribute white pillar meshes to match current bowl scale and cover outer ring (positions not updated when arena grew)|−
T63|.|leg rotation smoothing: legs rotate toward move direction gradually at rate scaled by `walk_speed`, no snap|T10
T64|.|multi-mech loadout: hangar lets player select squad of up to 5 mechs before match; on death, player chooses next mech from remaining squad before respawning|T34,T57
T65|.|team color perspective: client always renders own team blue, enemy red regardless of server team assignment|T40
T66|.|tutorial: first-run overlay on hangar screen explains controls; dismissed permanently per account; deferred until per-account system|T40
T67|.|multi-life game-end guard: `BeaconMatch` ⊥ ends match on last-player death if squad lives remain (V19); gate on T64|T64,V19
T68|x|mech visual art pass: all 8 mechs get Matrix-3-style geometry (rust/neon/mechanical bulk); block-primitive placeholders replaced|−
T69|x|weapon visual art pass: all weapon scenes get Matrix-3-style models; light ×2 size, heavy ×4 (Patience ×2)|T68
T70|.|multi-map system: Perlin-noise arena generator parameterized by seed/theme; all maps 5 beacons (V18); cover and scale vary|V18
T71|.|ELO system: track opponent ELO at match start; update player ELO on result using standard formula; persist in profile|T2
T72|.|XP + pilot level: XP awarded per match weighted by opponent ELO; level thresholds unlock progression tree nodes|T71
T73|.|pilot progression tree: speed/reload/ability-duration/damage/health bonuses; submenu under Pilot tab in hangar|T72
T74|.|in-game coins: earned from wins; spent on progression nodes or cosmetics; tracked in profile|T72
T75|.|online accounts: email signup/login; profile server-backed; prerequisite for ELO/cosmetics cross-device|T40,T71
T76|.|walk animation stride fix: small mechs animate too fast; tune `leg_cycle_rate`/`leg_hip_sweep` per mech so stride visually matches ground speed|T10
T77|.|player eject on death: cockpit pod launches upward on player `_die()`; skip for bots (check `input_source` type or `is_player` flag in `Mech._die()`)|T68
T78|.|normal-map arena edges: evaluate replacing Math Temple physical edge greebles with normal-mapped flat planes; reduce draw calls if viable|T70

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
B12|2026-05-02|Laser/Arc called `_emit_hit_if_visible` → played `hit_impact` on every damage tick; added `impact_sound_enabled` export, set false on both|V11
B13|2026-05-02|`MachineGun.fire()` overrides `super.fire()` without calling `VFX.muzzle_flash`; flash never shown; added explicit VFX call in `MG.fire()`|-
B14|2026-05-02|energy shield flash material used `TRANSPARENCY_ALPHA` → invisible in Compatibility renderer; fixed to opaque emissive|V7
B15|2026-05-02|`LaserCannon` beam drawn along weapon local -Z, not toward camera hit point; added `_beam_pivot.look_at(hit_pos)`|B9
B16|2026-05-02|`material_overlay` not reliably rendered in Compatibility renderer; energy shield flash uses `material_override` instead (whole-mesh color replace for flash duration)|-
B17|2026-05-03|`body_test_motion` crashes with null space after bot killed; root cause: `_on_match_ended` sets `process_mode=DISABLED` synchronously inside physics callback chain, removing body from physics space before `move_and_slide()` returns; fix: `set_deferred("process_mode", ...)` in `_on_match_ended` (Arena.gd)|−
B18|2026-05-05|`HUD.show_result` sets `result_label.visible=true` then `_build_stats_panel` adds opaque fullscreen `ColorRect` backdrop, burying winner text behind it; fix: embed "YOU WIN"/"YOU LOSE" as header row in stats panel, hide standalone `result_label`|T49
B19|2026-05-05|Pegasus jump arc wrong: no smooth arc, weird deceleration at peak; root cause unknown — suspect jump velocity curve or gravity-suppression timing in Pegasus ability script|T54
