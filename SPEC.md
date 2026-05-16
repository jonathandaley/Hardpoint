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
- Progression: ELO + XP; each pilot level grants 1 skill point used to unlock a skill (level 1 of that skill); coins spent to upgrade skills levels 2-12 (Fibonacci * 100 cost schedule); cosmetics via XP or coins.
- Accounts: local profiles only first MP cut (`user://profile.cfg`); pilot metadata (name, ELO, level) exchanged peer-to-peer via lobby RPC; ELO computed locally per peer from broadcast match-result; ⊥ central auth first cut (T75 backend deferred).
- MP hosting: listen-server first ship (host = peer_id 1, plays + holds authority). Dedicated build = same code with `--server` flag (no local PlayerInputSource, no Hangar entry); shipped P16, ⊥ blocking. NAT punch / matchmaking / relay ⊥ first cut; direct-IP LAN/friend mode only.
- MP transport: ENet via Godot MultiplayerAPI; default port 8910; `reliable` for state changes, `unreliable_ordered` for high-freq transforms.
- MP movement: server snapshots 20Hz `unreliable_ordered`; remote-owned mechs interpolated (2-snapshot buffer); host's own mech direct simulation (zero lag); remote peers' own mechs lag by RTT + snapshot interval (acceptable LAN, T131 adds prediction if T129 demands).
- MP bot fill: server-side at match start using deterministic seed (V29/T104); client ⊥ spawns/counts bots.

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
V5: only `Game.gd`, `SoundManager.gd`, `VFX.gd` as autoloads; ⊥ more added; bot-coordination (fmr AIDirector) lives in `Game.ai_director_*`; MovementLogger instantiated by Arena
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
V20: dedicated server model; server = peer_id 1; ∀ game-state mutation (damage, beacon capture, score, match-end) → runs only on server; clients receive replicated state via `@rpc("authority")` stubs; `multiplayer.has_multiplayer_peer() and not multiplayer.is_server()` guard pattern used at each authority seam
V21: pilot skills split into two classes. (a) baked stat multipliers -- health, walk_speed, lock_time, damage, projectile_speed, reload_time, inaccuracy, shield_capacity -- applied once in `Mech.apply_pilot_skills()` at spawn; ⊥ re-polled. (b) per-event modifiers -- repair_rate (Mech._process), ability_recharge (Mech._activate_ability/_deactivate_ability), beacon_capture + contested_hold (Beacon._update_capture) -- polled live but gated on `is_human_input()` or `_player_team_in_zone()` so bots never see them. xp_bonus + coin_pickup awarded once in `Game.update_after_match`. bot mechs ⊥ receive `apply_pilot_skills` regardless of class.
V22: gameplay input reads (`Input.is_action_*`, `get_axis`, `get_vector`, action events) only in `PlayerInputSource.gd`; ⊥ raw gameplay input in `Mech`, weapons, HUD, AI; mouse_mode/cursor toggles are window-state and exempt (UI scenes + `Mech.set_input_source`)
V23: ∀ cached `Node3D` ref → `is_instance_valid()` guard before deref; applies to lock targets, AI targets, projectile target/owner, beacon capturers
V24: in MP-replicated paths `randf*`/`randi*` ⊥; SP-only spread RNG in `ProjectileGun`/`MachineGun`/`Shotgun`/`Patience`/`AerialStrike` exempt today (local-authoritative) but must move to server-only `_do_fire` when T40 lands; cosmetic RNG marked `# cosmetic`; AI behavior RNG → seeded `RandomNumberGenerator` instance
V25: damage flows through `Mech._take_damage_rpc` only; ⊥ direct `health` writes; ⊥ bypass RPC seam even SP
V26: one-shot VFX/audio (muzzle flash, hit sparks, death explosion, damage hit, weapon fire, reload, mech death, ui clicks) → `VFX.*` / `SoundManager.*` autoload methods only; ⊥ inline one-shot `AudioStreamPlayer3D.new()` or effect `MeshInstance3D.new()` outside autoloads. weapon-owned persistent helpers (continuous-beam loop audio in `ArcWeapon`/`MachineGun`/`LaserCannon`; beam/tracer mesh in `ArcWeapon`/`LaserCannon`/`RaycastGun`/`Patience`) may be created inline by the weapon node that owns their lifetime.
V27: `Beacon._capturers` entries validated each capture tick (`is_instance_valid` + `is_alive`); dead/freed mechs purged before capture math
V28: damage requests routed through `Mech.request_damage(amount, source)` chokepoint; SP = direct call, MP = RPC seam at this fn
V29: AI behavior RNG = per-bot seeded `RandomNumberGenerator`; MP seed = `bot_id ^ match_seed`; ⊥ global `randf` in AI tick
V30: projectile collision + damage authoritative on server; client projectiles = visual-only ghosts; ⊥ client-side hit confirmation
V31: when MP replication crosses peer boundaries, cross-mech refs use peer/node ID, not direct `Node` ref; AI target + projectile target ID-resolved at spawn-ghost RPC seam. lock target ID-resolution deferred until T40 multi-peer wiring exercises it (see T102).
V32: server clamps `request_damage` to weapon-defined max + range gate before applying; ⊥ trust client damage value
V33: beacon capture progress visible to all peers within 200ms (periodic `unreliable_ordered` sync, not just end-state)
V34: VFX/audio pools (if introduced) bounded; ⊥ unbounded growth; per-pool capacity declared
V35: every `Mech` has `owner_peer_id: int` set at spawn from match roster (0 = bot, 1 = listen-host, 2+ = remote client); immutable for life of mech; authority for that mech's input + simulation = server-only (V20 still holds)
V36: profile metadata (`pilot_name`, `elo`, `level`, `xp`, `coins`, `skills`) local-only in `user://profile.cfg`; ⊥ central authority first cut; on lobby join peer broadcasts `{pilot_name, elo, level}` via `Game._rpc_peer_meta`; ELO recomputed locally per peer from `_rpc_match_end` payload (winner_team + per-peer pre-match ELO list); peers may drift if tampered, no enforcement first cut (T75 deferred)
V37: remote-owned mech transforms = interpolated from server `_rpc_snapshot` (20Hz, `unreliable_ordered`, 2-snapshot buffer); host's own mech = direct `CharacterBody3D` simulation; ⊥ client-side prediction for own mech in T109-T130 batch; T131 layers prediction if T129 feel test demands
V38: on non-server peer, `Mech._physics_process` applies interpolated transform from snapshot buffer only; ⊥ direct movement, ⊥ direct ability activation, ⊥ direct fire on client; visuals driven by server broadcast (T101 fire VFX/SFX, `_sync_health`, `_sync_shield`, `_rpc_ability_activated`)
V39: lobby state = server-authoritative `Game.mp_lobby` dict (roster, per-peer squad, ready flags, bot_fill toggle, match_seed); clients receive replicated copy via `_rpc_sync_lobby` (reliable on change); ∀ mutation → `@rpc("any_peer")` to server then broadcast; ⊥ direct client write
V40: scene transitions Hangar→Lobby→Arena→Lobby while peer attached → coordinated via `Game._rpc_change_scene(path)` (server-only origin); clients change scene on receipt only; ⊥ unilateral client scene change; exception = local disconnect or join-fail → tear down peer first, then return to title locally
V41: ∀ `@rpc("any_peer")` handler → read `multiplayer.get_remote_sender_id()` + validate against permitted source before mutation; reject malformed (drop + `push_error`); covers `_rpc_input` (sender owns target mech), `_rpc_set_squad`/`_rpc_set_ready`/`_rpc_pick_next_mech` (sender owns the slot), `_take_damage_rpc` (T103 already clamps amount + range)

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
T29|.|audio content: two CC0 tracks -- ambient loop (always playing) + combat loop (crossfade in when player takes damage or fires within 5s, crossfade out after 5s quiet); two AudioStreamPlayer nodes, volume crossfade via Tween; both loops seamlessly looping|T28
T30|x|visual FX: muzzle flash (0.08s decay), hit sparks (3-4 emissive cubes, 0.2s), death explosion (emissive sphere 0.3s + optional opaque chunks), shield hit -- opaque emissive + Tween|V7
T31|x|floor art: `tools/hat_floor_tex.py` → hat_floor.png (1024px) UV-mapped to bowl mesh|V13
T32|x|lighting pass: directional + 2-3 points, try baked lightmap (2 fail → fall back)|-
T33|x|fractal wall/ceiling art: `tools/fractal_wall_gen.py` → exterior circular walls only (archived for interior); interior walls use `_PENROSE_SVG_EDGES` directly|V13
T34|x|hangar 3D diorama: lineup 3-6 mechs, turntable platform, CanvasLayer UI, swap on loadout change|-
T35|x|team vs team: 5v5/6v6 bots, scaled arena, `Match` configurable team counts (`Game.loadout["team_size"]`)|−
T36|x|bot role assignment: attacker/defender/flanker, role biases beacon priority & positioning|T35
T37|x|bot blackboard coordination: `AIDirector` autoload per team, intent signals (pushing beacon A etc.)|T35,T36
T38|x|navmesh pathing: `NavigationAgent3D` + baked `NavigationMesh` per arena; LOS raycast gates bot firing|T35
T39|x|bot threat assessment: retreat low HP, focus-fire weak enemies|T35
T40|.|multiplayer umbrella: listen-server-authoritative (V35), `MultiplayerAPI`, interpolation-only first cut (V37); authority seams pre-built (V20, T92-T108); beacon progress sync closed by T105; T40 closes when T129 LAN smoke passes; integration tasks live in T109-T132; prediction T131, dedicated build T130, late-join T132 all deferred-future|V1,V2,V20,V35,V36,V37,V38,V39,V40,V41
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
T53|.|weapon balance pass: damage/RoF/clip tuning across all weapons; requires PvP or high-quality bots to test meaningfully -- defer until after T40 (multiplayer) or significantly smarter bots|V9,V10,T40
T54|x|jump forward bias: horizontal impulse = facing_dir * walk_speed * 3 added on Pegasus jump|T26
T55|x|pegasus nerf: cooldown 8→16s|T26
T56|x|jump landing hurt flash removed: `damaged.emit()` no longer called from `jump_heal` activation|−
T57|.|spawnpoints multi-life: spawnpoint logic activates only once lives > 1; no-op until T64 lives system|T64
T58|x|spectate on death: `Arena.gd` switches camera to ally mech on player death, cycles on next ally death; `HUD.start_spectating()` hides crosshair/weapon HUD, shows "SPECTATING: <NAME>" label|T35
T59|x|ally bot health bars: `setup_bot_bars` currently receives `_team_mechs[1]` only; pass `_team_mechs[0][1..]` with distinct color (e.g. green) so friendly bots show world-space HP bars|T35
T60|x|beacon HUD dot X positions match beacon physical XZ layout in arena (proportional horizontal spread), not fixed center strip|T42
T61|x|weapon range system: `range` export already set per weapon in `.tscn`; enforce hitscan cutoff + projectile self-destruct at range in `WeaponBase`|V9
T62|x|arena column repositioning: redistribute white pillar meshes to match current bowl scale and cover outer ring (positions not updated when arena grew)|−
T63|x|leg rotation smoothing: legs rotate toward move direction gradually at rate scaled by `walk_speed`, no snap|T10
T64|.|multi-mech loadout: hangar lets player select ordered squad of up to 5 mechs before match (order fixed at match start, no mid-match reorder); on death, full-screen UI overlay shows remaining squad mechs -- player taps to choose next, no timer, then spawns; on exhausting last mech player switches to spectate until match ends|T34,T57
T65|.|team color perspective: client always renders own team blue, enemy red regardless of server team assignment|T40
T66|.|tutorial: first-run overlay on hangar screen explains controls; dismissed permanently per account; deferred until per-account system|T40,T75
T67|.|multi-life game-end guard: `BeaconMatch` ⊥ ends match on last-player death if squad lives remain (V19); gate on T64|T64,V19
T68|x|mech visual art pass: all 8 mechs get Matrix-3-style geometry (rust/neon/mechanical bulk); block-primitive placeholders replaced|−
T69|x|weapon visual art pass: all weapon scenes get Matrix-3-style models; light ×2 size, heavy ×4 (Patience ×2)|T68
T70|x|multi-map system: Perlin-noise arena generator parameterized by seed/theme; all maps 5 beacons (V18); cover and scale vary|V18
T71|~|ELO system: track opponent ELO at match start; update player ELO on result using standard formula; persist in profile|T2
T72|~|XP + pilot level: XP awarded per match weighted by opponent ELO; level thresholds unlock progression tree nodes|T71
T73|~|pilot progression tree: speed/reload/ability-duration/damage/health bonuses; submenu under Pilot tab in hangar|T72
T74|~|in-game coins: earned from wins; spent on progression nodes or cosmetics; tracked in profile|T72
T75|.|online accounts: email signup/login; profile server-backed; prerequisite for ELO/cosmetics cross-device|T40,T71
T76|x|walk animation stride fix: small mechs animate too fast; tune `leg_cycle_rate`/`leg_hip_sweep` per mech so stride visually matches ground speed|T10
T77|x|player eject on death: cockpit pod launches upward on player `_die()`; skip for bots (check `input_source` type or `is_player` flag in `Mech._die()`)|T68
T78|x|normal-map arena edges: evaluate replacing Math Temple physical edge greebles with normal-mapped flat planes; reduce draw calls if viable|T70
T79|.|hangar art pass: interior industrial hangar bay, Matrix-3 aesthetic (grays/blacks/brown, rust, grime); geometry: concrete/steel walls, grated floor, overhead girders and pipes; lighting: harsh overhead flood points + sparse neon strip accents + welding-flash emissive pops; turntable platform gets worn polished-metal material; maintenance bots visible in hangar view only (hidden in detail view) -- simple opaque-emissive geometry, scripted 30-60s looping tasks (welding arcs, rolling carts, oiling arms), varied enough that loop is not obvious; bots ignore player actions entirely|T34
T80|.|scene-based maps: add `scene_path: String` to MapDef; Arena loads the MapDef's scene instead of always using Arena.tscn; each map is a self-contained scene with its own geometry, beacon placement, and floor pattern; migrate Math Temple only -- Badlands/Ironworks .tres stubs kept (so map selector works) but have no geometry and are not migrated; new maps built from scratch (T82)|T70
T81|x|controls reference tab: add "Controls" read-only tab to Settings.tscn listing all key bindings (WASD move, mouse look, LMB fire-all, RMB fire-active, 1-4 slot toggle, R reload, Q ability, Tab spectate-cycle, Esc uncapture); no rebinding required; implementable before multiplayer|-
T82|.|new maps: build Badlands and Ironworks as real self-contained scenes following T80 system; each has own geometry, beacon placement, and floor pattern; 5 beacons each (V18); no geometry shared with Math Temple|T80,V18
T83|x|spectate cycle: Tab key cycles spectate target round-robin through alive teammates while spectating; works alongside existing auto-switch on spectatee death|T58
T86|x|skill tree data layer: replace `Game.gd` progression system (`_PROG_*` consts, `profile["progression"]`, all `get_progression_*`/`buy_progression` helpers) with 15-skill tree; `profile["skills"]` dict maps skill_key -> level (1-12; absent = locked); skill points available = `profile.level - profile.skills.size()`; `SKILL_TREE` const defines per-skill parents (empty = root), any_parent flag, label; unlock costs 1 skill point (level goes 0->1), upgrade costs Fibonacci*100 coins for levels 2-12 (costs: 100,200,300,500,800,1300,2100,3400,5500,8900,14400); expose: `skill_level(key)->int`, `skill_points_available()->int`, `can_unlock(key)->bool` (checks any_parent rule + points available), `can_upgrade(key)->bool` (checks coins), `unlock_skill(key)->bool`, `upgrade_skill(key)->bool`, `get_skill_effect(key)->float` (returns level*per_level_value); skill keys + per-level values: damage=0.015, health=0.02, projectile_speed=0.01, spread_reduction=0.06, repair_rate=0.5 HP/s, shield_capacity=0.05, move_speed=0.01, beacon_capture=0.05, contested_hold=0.5s, ability_recharge=0.05, powerup_duration=0.05 (STUB), coin_pickup=0.03, xp_bonus=0.03, reload_speed=0.04, lock_speed=0.05; tree edges: damage->projectile_speed->spread_reduction; health->repair_rate; health->shield_capacity; [damage|health]->move_speed->beacon_capture->contested_hold; [damage|health]->ability_recharge->powerup_duration,coin_pickup,xp_bonus; [damage|ability_recharge]->reload_speed; [damage|ability_recharge]->lock_speed|V21
T87|x|weapon inaccuracy system: add `@export var inaccuracy_angle: float = 0.0` to `ProjectileGun.gd`; in `_do_fire()` apply same spread logic as MachineGun (perp offset + tan of angle) when inaccuracy_angle > 0; set base values in weapon `.tscn` scenes: Rifle L 0.4 deg / H 0.3 deg; Missile Launcher L 0.8 deg / H 0.6 deg; Sniper L 0.05 deg / H 0.04 deg; Patience H 0.05 deg; all others 0.0; Shotgun retains own pellet spread unaffected by spread_reduction skill|T86,V21
T88|x|Mech.apply_pilot_skills(): new method on `Mech.gd`, called by Arena only for player mech after spawn; reads `Game.skill_level()` for each skill and multiplies stats in-place: max_health *= (1+health_effect), walk_speed *= (1+move_speed_effect), _LOCK_TIME *= (1-lock_speed_effect), all child WeaponBase: damage *= (1+damage_effect), if ProjectileGun: projectile_speed *= (1+proj_speed_effect), reload_time *= (1-reload_speed_effect), inaccuracy_angle *= (1-spread_reduction_effect); EnergyShield child if present: _max_pool *= (1+shield_cap_effect); simplify Pilot.gd: remove walk_speed_modifier/reload_rate_modifier exports + apply_modifier calls (replaced by skill system)|T86,T87,V21
T89|x|per-tick skill effects: (1) Repair Rate -- add `_no_damage_timer: float` to Mech.gd; reset on take_damage(); in _process() if is_player_controlled increment; if >= 3.0s and repair_rate level > 0 regen Game.get_skill_effect("repair_rate") HP/s clamped to max_health; (2) Ability Recharge -- when setting active ability cooldown in Mech, multiply by (1.0 - Game.get_skill_effect("ability_recharge")) if is_player_controlled; (3) Beacon capture speed -- in Beacon._update_capture() when player team sole capturer, multiply delta by (1.0 + Game.get_skill_effect("beacon_capture")); player team detected by checking _capturers for body whose input_source is PlayerInputSource; (4) Contested hold time -- in Beacon._update_capture() when both teams present and player team has mech in zone, delay CONTESTED transition by Game.get_skill_effect("contested_hold") seconds via _contested_hold_timer float; timer starts on enemy entry, resets if enemy leaves before expiry|T86,T88,V21
T90|x|meta skill effects + stubs: (1) XP bonus -- in Game.update_after_match() multiply xp_gain by (1.0 + get_skill_effect("xp_bonus")); (2) coin bonus -- multiply coin award by (1.0 + get_skill_effect("coin_pickup")); add Game.apply_coin_pickup_bonus(base:int)->int helper = roundi(base*(1+get_skill_effect("coin_pickup"))) for future in-match use; (3) power-up duration -- get_skill_effect("powerup_duration") data present, no call site yet|T86,V21
T91|x|hangar skill tree UI: replace _build_progression_nodes() + _on_prog_buy() in Hangar.gd with skill tree list; pilot stats line gains "SP: N" counter; ScrollContainer below stats shows all 15 skills as rows (locked/unlocked/maxed state, level N/12, cost or LOCKED label, BUY/UPGRADE button); rows indented by tree depth; locked rows show which parent(s) needed; BUY calls Game.unlock_skill() (costs SP), UPGRADE calls Game.upgrade_skill() (costs coins); buttons disabled when requirements unmet; refresh on purchase; visual tree layout deferred to later task|T86,T88,T89,T90
T92|x|P0: codify current behavior -- add V22-V26 invariants (done in §V), run /check, catalog drift baseline; ⊥ code change in this task; baseline 2026-05-10: 20 hold / 5 violate / 7 unverifiable (after V22 narrowed to gameplay-input only, mouse_mode toggles reclassified non-violation); violations map to tracked tasks (V21→T88, V23→T93/T94, V24→T98/T99, V26→T97+); V28-V34 unverifiable until P2-P4 wiring lands|V22,V23,V24,V25,V26
T93|x|P1: Beacon `_capturers` stale ref guard -- `is_instance_valid` + `is_alive` filter each capture tick (`Beacon.gd:104-120`); fixes B28|V27
T94|x|P1: defensive `is_instance_valid` pass on cached refs -- `Mech.locked_target`, `Mech.lock_eligible_target`, `AIInputSource._target`, `Projectile.target`, `Projectile.owner_body`, `HomingProjectile.target`; null-skip on stale, no behavior change when valid|V23
T95|x|P2: weapon fire chokepoint -- `Mech.fire_weapon(slot, aim)` wraps current scattered fire paths in `WeaponBase.gd`/`ProjectileGun.gd`; SP behavior identical, MP later wraps in @rpc at this seam|V3
T96|x|P2: damage routing through `Mech.request_damage(amount, source)` chokepoint; wraps current `_apply_damage` (`Mech.gd:213-224`); no clamp yet (deferred to T103)|V25,V28
T97|x|P2: VFX/SFX broadcast hooks -- add optional `broadcast: bool = false` param to `VFX.spawn_*` and `SoundManager.play_*`; SP path unchanged (param unused); MP flips to true at fire callsites|V26
T98|x|P3: AIInputSource uses seeded `RandomNumberGenerator` instance (replace global `randf` calls in aim jitter, strafe, escape); SP seed = time-based for variance, MP seed deferred to T104|V29
T99|x|P3: tag cosmetic RNG callsites with `# cosmetic` -- pod ejection (`Mech.gd:315-316`), VFX particle spread (`VFX.gd:42-86`); cosmetic RNG keeps global `randf`|V24
T100|x|P4: projectile spawn RPC -- server authoritative for `Projectile.gd` + `HomingProjectile.gd`; client projectile = visual-only ghost; hit detection server-only|V30,T40
T101|x|P4: weapon fire RPC broadcast -- flip `broadcast=true` from T97 at fire callsites in `WeaponBase.gd`; remote players hear/see fire SFX/VFX|V26,T97
T102|.|P4: lock state sync -- replicate `Mech.locked_target` as instance id, resolve via lookup at ArcWeapon/AerialStrike/RocketLauncher use sites; deferred until T40 because SP has no cross-peer ref problem; earlier stub field removed 2026-05-13|V31,T40
T103|x|P4: server-side damage validation in `request_damage` -- clamp amount to weapon-defined max, gate by range, reject malformed; server-only enforcement|V32,T96
T104|x|P4: bot RNG → deterministic seed broadcast by server at match start; bots replicate as MultiplayerSpawner children w/ matching seeds|V29,T98
T105|x|P4: beacon capture progress periodic RPC (`unreliable_ordered`); clients see progress bar real-time, not just end-state|V33,T40
T106|x|P5 (gated): bench arena under sustained fire (4 bots vs player, 30s); profile w/ Godot profiler; if frame-time stable <16ms → skip T107/T108; result 2026-05-13: Physics Time ~2ms, Physics Frame Time 16.66ms (tick interval, not cost) → stable, T107/T108 skipped|-
T107|~|P5 (conditional T106): VFX object pool for top hitch source identified by T106 only -- SKIPPED: T106 showed no hitch|V34,T106
T108|~|P5 (conditional T106): SoundManager `AudioStreamPlayer3D` pool -- SKIPPED: T106 showed no hitch|V34,T106
T109|x|P7: MP transport core in `Game.gd` -- `host(port:int=8910)`, `join(ip:String, port:int=8910)`, `disconnect()` via `ENetMultiplayerPeer.create_server/create_client`; expose signals `mp_peer_connected(id)/mp_peer_disconnected(id)/mp_join_failed/mp_server_lost`; wire `multiplayer.peer_connected/disconnected/connection_failed/server_disconnected` once at autoload _ready; ⊥ new autoload (V5)|V5,V20
T110|x|P7: TitleScreen MP entry -- add "Multiplayer" button alongside single-player flow; new `scenes/ui/MPEntry.tscn` with Host (port field) / Join (IP+port fields) tabs; Host calls `Game.host()` then `change_scene_to_file(Lobby)`; Join calls `Game.join()` and waits on `mp_peer_connected` (success) or `mp_join_failed` (back to MPEntry with error label)|T109
T111|x|P8: Lobby scene `scenes/ui/Lobby.tscn` -- server-authoritative `Game.mp_lobby` dict (V39); rows show pilot_name, ELO, ready dot, team color, squad summary; bot-fill checkbox (host-only); team-size picker (host-only, mirrors `Game.loadout["team_size"]`); map picker (host-only); start button (host-only, gated on all-ready unless bot-fill enabled); clients render replicated state read-only|V39
T112|x|P8: peer profile metadata RPC -- on `mp_peer_connected` server requests via `_rpc_request_meta`; client replies `_rpc_send_meta({pilot_name, elo, level})`; server stores in `Game.mp_lobby.peers[id]`; broadcasts updated lobby via `_rpc_sync_lobby` (V39, V36)|V36,V39
T113|x|P8: per-peer squad RPC -- embed shrunken Hangar widget in Lobby for picking own squad (5 mech paths + per-mech weapon overrides); on change client sends `_rpc_set_squad(squad: Array)` `@rpc("any_peer")` to server; server validates (resolves resource paths, 5 entries, weapons fit slot sizes per V17, sender owns slot per V41); stores in `mp_lobby.peers[sender].squad`; broadcasts (V39)|V17,V39,V41
T114|x|P8: lobby ready toggle -- per-peer ready button → `_rpc_set_ready(bool)` `@rpc("any_peer")`; sender validation (V41); server flips and broadcasts; host start-button enabled when (bot-fill AND >=1 peer) OR all peers ready AND >=2 peers|V39,V41
T115|x|P9: match start RPC -- host clicks start; server validates lobby, generates `match_seed` (V29 reuse), fills bots if enabled (V40 = V39+T104 bot seed broadcast), builds roster `Array[{slot_idx, peer_id|0_for_bot, team, squad_paths, weapon_paths}]`; broadcasts `_rpc_match_start(map_path, roster, match_seed)`; all peers call `change_scene_to_file(Arena)` on receipt (V40)|V40,T104,T114
T116|x|P9: Arena per-peer mech spawn from roster -- Arena._ready reads `Game.mp_active_match.roster` set by T115; spawns one mech per slot with `owner_peer_id` set (V35); local peer's first-alive slot gets `PlayerInputSource`, remote peers' slots get `NetworkInputSource` (T117), bot slots get `AIInputSource`; team assignment follows roster; spawn point = team spawn cluster, slot index spreads within cluster|V35,T115,T117
T117|x|P10: `NetworkInputSource.gd` -- new `scripts/NetworkInputSource.gd` extends `InputSource`; mirrors `PlayerInputSource` interface (`get_move_direction`, `get_look_delta`, `is_firing_primary`, `is_firing_secondary`, `get_slot_toggle`, `is_reload_pressed`, `is_ability_pressed`, `is_human_input()->true`); reads from per-peer input buffer populated by `_rpc_input` (T118); one instance per remote peer's mech, server-only|V1,V35
T118|x|P10: client input forwarding -- on non-server peer, owner mech's `Mech._physics_process` samples local `PlayerInputSource` and `rpc_id(1, &"_rpc_input", seq, payload)` at 30Hz (every 2nd tick at 60fps); `payload` dict = `{move:Vector2, look:Vector2, fire_prim:bool, fire_sec:bool, slot_toggle:int, reload:bool, ability:bool}`; server `_rpc_input` handler validates sender owns target mech (V41), updates that mech's `NetworkInputSource` buffer, T125 rate-limits|V1,V41,T125
T119|x|P10: mech transform snapshot RPC -- server runs `_snapshot_tick` at 20Hz via timer node on Arena; collects `Array[{peer_id_or_slot, pos:Vector3, basis_quat:Quaternion, lin_vel:Vector3}]` for all alive mechs; `_rpc_snapshot.rpc(snapshots)` `@rpc("authority","unreliable_ordered")`; clients buffer last 2 snapshots per mech, interpolate at render between `now - 100ms` and `now`; energy_shield pool also synced via new `_sync_shield(pool:float)` event-RPC on absorb mutation (mirror of `_sync_health` T40)|V37
T120|x|P10: mech client-side gating -- on non-server peer, `Mech._physics_process` for a mech not owned by local peer = apply interpolated transform from T119 buffer ONLY; ⊥ `move_and_slide`, ⊥ ability activation, ⊥ weapon fire on client; legs/visual animation reads `linear_velocity` from interp delta (already supported by BipedLegs); fire/reload/ability VFX+SFX arrive via T101 broadcast and `_rpc_ability_activated(slot:int)` (new); for OWN mech on remote peer: same gating (no prediction first cut per V37), interpolation buffer drives transform; HUD reads local input source still for crosshair/UI feedback|V37,V38,T101
T121|x|P9: match-end RPC + return-to-lobby -- server broadcasts `_rpc_match_end(winner_team, stats: Array[{peer_id, kills, damage, captures, pre_elo}])`; HUD shows result + scoreboard; "back to lobby" button → `_rpc_ready_for_next` `@rpc("any_peer")`; server tracks confirmations; when all confirm OR 30s timeout, server `_rpc_change_scene(Lobby)` (V40); lobby state preserved across return|V40
T122|x|P11: HUD multi-peer perspective -- unblocks T65; HUD/Mech visuals render local peer's team as blue (own) and opposite as red regardless of server team id; scoreboard panel shows all human players with pilot_name + ELO + kills/damage; bots rendered with `[BOT]` prefix; spectator state grayed; ally health bars filter by team relative to local peer (T59 generalization)|T65,T59
T123|x|P12: peer disconnect mid-match -- on server `multiplayer.peer_disconnected(id)`: (a) if in lobby, remove peer from `mp_lobby.peers`, broadcast updated lobby; (b) if in match and that peer's currently-active mech is alive, swap `_input_source` from `NetworkInputSource` to `AIInputSource` (seeded from `match_seed ^ id` per V29); remaining squad slots become bot-controlled too; match continues; HUD shows `[DISCONNECTED]` on that peer's scoreboard row|V29,V40
T124|x|P12: server-side `@rpc("any_peer")` sender validation pass -- audit every `@rpc("any_peer")` handler; each reads `multiplayer.get_remote_sender_id()` and validates against permitted source per V41; covered: `_take_damage_rpc` (T103 already clamps; add sender = projectile/weapon owner check), `_rpc_input` (sender owns target mech, T118), `_rpc_set_squad` (T113), `_rpc_set_ready` (T114), `_rpc_pick_next_mech` (T127), `_rpc_send_meta` (T112), `_rpc_ready_for_next` (T121); malformed → drop + push_error|V41
T125|x|P12: server input rate-limit -- per-peer sliding window in `_rpc_input` handler; drop calls exceeding 60Hz over 1s; emit `push_warning` once per peer per breach window; defensive against malformed clients (V41)|V41,T118
T126|.|P13: MP ELO/XP/coins update at match end -- `_rpc_match_end` payload (T121) includes per-peer `pre_elo` array; each client locally computes own ELO delta vs each opponent's pre_elo via existing T71 formula (averaged); applies XP/coins via existing `Game.update_after_match` weighted by avg opponent ELO; persists `user://profile.cfg`; ⊥ central enforcement (V36)|V36,T71,T72,T74
T127|.|P14: MP squad lives -- extends T64 to MP; on own-mech death, client shows existing squad picker overlay; selection sends `_rpc_pick_next_mech(slot_idx:int)` `@rpc("any_peer")` to server; server validates sender owns slot (V41), slot not already used, lives > 0; server spawns next mech at team spawn cluster with `owner_peer_id` and new `NetworkInputSource`/`PlayerInputSource`; broadcasts roster update via `_rpc_sync_lobby` shape (or `_rpc_sync_match`); match-end guard T67 still applies|V35,V41,T64,T67
T128|.|P14: MP spectate-on-squad-exhausted -- when local peer's last alive squad mech dies and no lives remain, switch to existing T58 spectate path; cycle through alive teammates (own team filter, includes bot teammates); HUD shows `SPECTATING: <NAME>` (T58); spectate camera continues until `_rpc_match_end` broadcast|T58,T83,T127
T129|.|P15: 2-peer LAN smoke test -- gate task; host + join over LAN; full beacon-drain match to completion with 1 human + 1 human + bot-fill; verify: capture progress visible <200ms (V33), kills/damage replicated, ELO updates on both peers, disconnect mid-match continues (T123), no desync over 10min, no script errors; bench frame-time on host vs client (target <16ms host, <16ms client); record result; if remote-mech feel unacceptable on LAN → unblock T131|V33,T123
T130|.|P16 deferred: dedicated server build -- `Game.gd._ready` reads `OS.get_cmdline_args()` for `--server [port]`; if present: auto-host on port, skip Title/SignIn/Hangar/Lobby flow (server holds the lobby), no local PlayerInputSource spawn at match start (V35); export preset `mechbattle.server.x86_64` builds headless (rendering disabled at engine init); deferred until T129 passes|V35,T129
T131|.|P16 deferred: client-side prediction for own mech -- on remote peer's own-mech path, apply input locally each tick (prediction) + reconcile against server snapshot; snap on divergence > 1m, smooth otherwise; input ringbuffer for reconciliation; gated on T129 -- only build if interpolation feel is unacceptable in T129 LAN test|V37,T129
T132|.|P16 deferred: reconnect / late-join -- on `peer_disconnected` server reserves slot 30s before bot-swap; reconnect within window resumes as spectate (no respawn into existing squad); fresh late-join allowed only between matches; full design + implementation deferred; tracked here so it does not surprise on first MP feedback|T123,T129

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
B17|2026-05-03|`body_test_motion` crashes with null space after bot killed; root cause: `_on_match_ended` sets `process_mode=DISABLED` synchronously inside physics callback chain, removing body from physics space before `move_and_slide()` returns; fix: `set_deferred("process_mode", ...)` in `_on_match_ended` (Arena.gd)|-
B18|2026-05-05|`HUD.show_result` sets `result_label.visible=true` then `_build_stats_panel` adds opaque fullscreen `ColorRect` backdrop, burying winner text behind it; fix: embed "YOU WIN"/"YOU LOSE" as header row in stats panel, hide standalone `result_label`|-
B19|2026-05-05|Pegasus jump arc wrong: no smooth arc, weird deceleration at peak; root cause: `_handle_movement` applied ground decel (16 m/s²) in air, killing horizontal velocity in 0.56s of a 1.56s flight; fix: skip horiz decel/accel when `not is_on_floor()`; still allows steering via `_desired_move_dir`|-
B20|2026-05-08|hangar detail screen weapon selector sizes to label content width — inconsistent layout across weapons with short vs long names|-
B21|2026-05-08|dead bots not removed from lock target pool or beacon contester list — invisible body still accepts target lock and drains/contests beacons after death|-
B22|2026-05-08|lock-break angle constant regardless of range — close targets move faster across aim arc so lock drops on minor wobble; long-range behavior is correct|-
B23|2026-05-08|target re-selected every frame by smallest angle-to-crosshair — prior fix applied hold cone only when raycast missed; raycast hitting adjacent mech still reset candidate; complete fix: hold cone applied before raycast result is accepted, not only on miss|-
B24|2026-05-08|bot body oscillates ~30 deg left-right continuously -- P-only turn controller in AIInputSource applies full TURN_SPEED regardless of angle_h magnitude; overshoots, angle_h flips sign, overshoots back|-
B25|2026-05-09|audio too loud - master volume default too high; rifle SFX additionally loud relative to other weapons; user found 30% master volume a comfortable midpoint; fix: lowered `Game.settings["master_volume"]` default 1.0->0.5 (part 2, rifle db tuning, deferred until audio content lands T29)|−
B26|2026-05-10|bot target persistence ignores threats and LoS - fix: `_on_pawn_damaged` forces `_target_refresh=0` on damage; `_check_los` accumulates `_los_blocked_time` and clears `_target` if blocked >1s (AIInputSource.gd)|−
B27|2026-05-10|friendly fire enabled - fix: team check added at each damage call site before `take_damage`: Projectile.gd, HomingProjectile.gd, RaycastGun.gd, LaserCannon.gd, ArcWeapon.gd; Shotgun covered via Projectile (already sets `proj.team`)|−
B28|2026-05-10|Beacon `_capturers` dict holds direct mech refs populated by `body_entered` signals on each peer; on death/free, mech may stay in dict until next `_sync_state` RPC → ghost capture progress (dead mech still counts toward capture/contest); fixed by T93 (`is_instance_valid` purge pass in `_update_capture()` + guard in `_teams_present()`)|V27
