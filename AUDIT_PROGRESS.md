# Project Audit Progress (2026-06-09)

Goal: full-project sweep for bugs, efficiency problems, and anything else worth addressing.
This file is the resumable state. If session dies, restart from "Next up".

## Status
- [x] autoloads/ (Game, AIDirector, SoundManager, VFX, MovementLogger)
- [x] scripts/Mech.gd + BipedLegs + MechVisuals
- [x] weapons (WeaponBase + all weapon scripts + Projectile/Homing) — AerialStrike/Patience/shields still pending
- [x] AI (AIInputSource) + Beacon + Player + input sources
- [x] MP (Lobby, MPEntry, Match/BeaconMatch)
- [x] UI (HUD, WeaponHUD, Hangar, Settings, PauseMenu, TitleScreen, Crosshair)
- [x] Arena.gd (logic portion; lines 1-4404 are baked Penrose/bowl data, skimmed only)
- [x] misc small files (SignIn, EligibleIndicator, BeaconDot, InputSource, Pilot, defs, shaders)
- [~] tools/*.py skipped (offline generators, not shipped code); Arena baked-data consts skimmed only

## Findings

### Bugs
1. **Game.gd:351 save_settings() loads the wrong file.** It does `cfg.load(_SAVE_PATH)` (profile.cfg) then `cfg.save(_SETTINGS_PATH)` (settings.cfg). Every settings save copies all profile/loadout sections into settings.cfg, and any sections in settings.cfg not currently in memory are not preserved (the load that was meant to preserve them reads the wrong file). Fix: `cfg.load(_SETTINGS_PATH)`.
2. **Game.gd:354 save_settings() fallback default for master_volume is 1.0** but the canonical default (settings dict, line 75) is 0.5. Inconsistent; harmless today since key always exists, but a trap.
3. **Arena.gd:5290 SP win counter assumes player team == 0.** `wins` incremented when `winning_team == 0`, but ELO/XP uses `winning_team == player_team`. If player_team is ever nonzero in SP, wins/losses disagree with ELO. (Verify whether SP player_team is always 0; if so, downgrade to consistency nit.)

### Bugs (Mech / weapons)
8. **RocketLauncher.gd:58 sends a raw `instance_id` over RPC and resolves it on the client with `instance_from_id()`.** Instance IDs are process-local; the server's ID is meaningless on a client. Ghost rockets on clients either get a null target (no homing) or, worse, resolve to an unrelated client-side object. Fix: send the target mech's NodePath (stable across peers since the tree is replicated) and `get_node_or_null` it.
9. **MachineGun.gd:51-59 ramp logic breaks at high frame rates.** `fire()` (called from `_physics_process`, 60 Hz) sets `_trigger_held = true`; `_process` (render rate) consumes and clears it. At >60 fps, extra `_process` frames see `_trigger_held == false` and decay `_current_rate` at 25 rps/s between physics ticks, so the spin-up stalls/oscillates for high-refresh players. Track held state from the physics side (e.g. clear in `_physics_process`, or timestamp the last fire call).
10. **MachineGun.fire() duplicates WeaponBase.fire() but drops MP broadcast**: `VFX.muzzle_flash(...)` is called without the broadcast flag and there's no positional fire-sound broadcast (loop player is local to the server). Remote peers see/hear nothing from machine guns. (Related to known open MP bug group.)
11. **Mech.gd:322 `_sync_health` is `unreliable_ordered`, and death (h=0) rides on it.** The final health packet can be dropped, leaving a client showing a live mech (or wrong HP until the next hit). Death should be a reliable RPC (or Arena should broadcast death/respawn reliably — verify in Arena pass).
12. **ProjectileGun/MachineGun/MissileLauncher aim-point can be behind the barrel.** Camera sits ~6 m behind the weapon; if the camera ray hits geometry between camera and barrel, `looking_at(aim_point)` makes the projectile fire backwards. Clamp: if `(aim_point - barrel).dot(cam_fwd) <= 0`, aim along cam_fwd instead. (The camera-raycast pattern itself is correct per house rule; this is the close-wall edge case.)
13. **Mech.gd:595 `_net_look_accum` grows without bound in SP/server play** — `_handle_look` always accumulates, but only the MP-client path (`_maybe_forward_input`) ever drains it. Harmless until float precision degrades in a long session; drain or skip accumulation when not a MP client.
14. **Mech.gd:88 `_body_meshes` is captured once in `_ready`** and is used by `_do_shield_flash`/`_process` to set `material_override`. If weapons are (re)configured after the mech enters the tree (`configure_weapons` frees `Hardpoint*` nodes), the array can hold freed instances → runtime errors on next shield flash. Cheap fix: rebuild `_body_meshes` at the end of `configure_weapons`, or `is_instance_valid` filter in the two loops. (Severity depends on Arena's spawn order — verify.)

17. **Patience deals zero damage in MP.** PatienceHeavy.tscn sets `damage = 0.0` (real damage comes from min/max_damage charge lerp), but `Mech.request_damage` clamps with `source.get("damage")` → `amount > 0*1.5` rejects every hit whenever a server is running. SP is unaffected (clamp only runs with a multiplayer peer). Fix: clamp against `max_damage` for Patience (e.g. expose a `get_max_damage()` on weapons, or set the export to max_damage).
18. **AerialStrike._fire_burst awaits a timer 20x in a loop without validity checks** (AerialStrike.gd:25-31). If the firing mech dies and is freed mid-burst, the resumed coroutine calls `get_tree()`/`global_position` on a freed weapon → errors/crash. Guard each iteration with `if not is_instance_valid(self) or not is_inside_tree(): return` (and note mech death currently only hides the mech — verify whether weapons are ever freed before match end).
19. **PhysicalShield.gd has stray `pass` statements** (lines 20, 29) — leftovers, harmless.
20. **AerialStrike has no MP ghost broadcast** (rockets invisible to clients), same family as finding 15.

### MP visual/audio gaps (likely overlap with known open MP bug list)
15. RaycastGun tracer + muzzle flash mesh, LaserCannon beam, ArcWeapon beam, Shotgun pellets: all rendered server-side only; no ghost/broadcast for clients. Clients see nothing for these weapons. (Laser already listed in project_mp_bugs_open memory.)
16. **ProjectileGun._rpc_spawn_ghost is `reliable`** — per-bullet reliable RPCs (machine gun ~14/s/mech) add retransmit overhead for purely cosmetic ghosts; `unreliable` is the right channel.

### Bugs (AI)
21. **AIInputSource._pick_target_beacon hardcodes team identity** (AIInputSource.gd:141-162). Beacon.owner_team is absolute (-1 neutral, 0 team A, 1 team B), but the role logic treats `owner == 1` as "my beacon" (defender priority 15, attacker `continue`). Correct only for team-1 bots. Any bot on team 0 — i.e. ALL allied bots in 5v5 squad play — gets inverted logic: defenders guard enemy beacons, attackers skip enemy beacons and walk to already-owned ones. Fix: compare against `_own_team` / `1 - _own_team`.
22. **AIInputSource turn speed is frame-rate dependent.** AI runs in `_process` (render rate) and computes `_look_delta` scaled by render delta, but `Mech._handle_look` consumes it once per physics tick (60 Hz) without the AI draining it. At 144 fps bots turn ~0.4x as fast as intended; at 30 fps render, 2x. Move AI to `_physics_process`, or drain `_look_delta` on read like PlayerInputSource/NetworkInputSource do.
23. **AIInputSource._pick_closest_enemy is dead code** (never called; `_pick_best_target` superseded it).
24. **AIInputSource._enemy_mechs is a spawn-time snapshot** — mechs added later (late joins, anything respawned as a new node) are never targeted. Fine today if Arena spawns everything up front; fragile otherwise.

### Bugs (Arena / MP / match flow)
25. **Bot-ified disconnected mechs stand still.** `Arena._bot_ify_disconnected_mech` (Arena.gd:5335) parents the new AIInputSource to the *mech*, but AIInputSource reads `get_parent().get("pawn")` (AIInputSource.gd:224), which is null on a Mech — the AI early-returns every frame. The mech of a disconnected peer just idles. Fix: attach the AI input to the existing RemotePlayer node (like `_rpc_spawn_next_mech` does for net input), or teach AIInputSource to accept the mech directly.
26. **Match.gd:41-44 base `_check_win` is inverted**: a team reaching `score_limit` makes the *other* team win (`_end_match(1 - i)`). BeaconMatch overrides it so nothing breaks today, but any future Match subclass inherits a wrong-way win condition. Also the comment headers say "drain" semantics live in BeaconMatch; base Match still mixes both.
27. **MP respawn loses the hit-confirm crosshair X**: `_rpc_spawn_next_mech` reconnects `damaged` → HUD but not each weapon's `hit_confirmed` → `hud.register_hit` (compare _setup_players_mp:4777-4780). After picking a next squad mech, landing hits no longer flashes the X. (Likely part of the known open "hit X" MP bug.)
28. **Match seed RPC race (verify)**: server `Match.start()` runs in Arena._ready and immediately RPCs `_rpc_set_match_seed`; a slower client that hasn't finished loading Arena yet has no matching node path, so the seed (and deterministic bot RNG) is silently lost for that client. Consider re-sending or piggybacking the seed in `mp_active_match` (it's already there as `match_seed` — clients could just read it locally instead of via RPC).
29. **Lobby/Hangar weapon catalogs omit ROCKET LAUNCHER HV** even though `scenes/weapons/RocketLauncherHeavy.tscn` exists; players can never equip it. Intentional?
30. **Hangar._build_weapon_picker uses `existing.free()`** (immediate) instead of `queue_free()` — safe with current call paths, but a freed-while-signaling crash waiting to happen if a picker child ever triggers a rebuild.

### Minor / polish
31. **SignIn._confirm doesn't call `Game.save_profile()`** — a freshly entered pilot name is lost if the player quits before anything else saves the profile.
32. **Settings.gd:34 and Game.gd:354 use `master_volume` fallback 1.0** while the canonical default is 0.5 (Game.gd:75). Pick one.
33. **Arena.gd:5289 SP win counter uses `winning_team == 0`** while ELO uses `winning_team == player_team`. In SP the player team is always 0 today, so this is a consistency nit, not a live bug — but use `player_team` in both places.
34. **HUD._process dereferences `_player_mech.health` with only a null check** (HUD.gd:431-435); every other consumer uses `is_instance_valid`. If the mech node is ever freed (rather than hidden) this is the next "bot-bar crash on respawn".
35. **`.uid` files for Lobby.gd / MPEntry.gd / NetworkInputSource.gd are untracked** (git status). Godot 4.4+ uid sidecars should be committed, or references can break across checkouts. Also untracked: MP_AUTODEBUG_PLAN.md, MP_M0_BRIEF.md, error screenshot.

### Dead code / cleanup
4. **autoloads/AIDirector.gd is dead.** Not registered in project.godot (autoloads are Game, SoundManager, VFX); its logic was absorbed into Game.gd (ai_director_* funcs); no callers reference the AIDirector singleton. Delete the file (AIInputSource comment at line 171 mentions "AIDirector" but calls Game.ai_director_*).
4b. **shaders/health_bar.gdshader is dead** — referenced nowhere (health bars went screen-space per design history). Delete.
4c. **Hangar._on_prog_buy is an empty stub** (T91 leftover). ArcWeapon._process override that only calls super is noise.

### Efficiency (minor)
5. **Game.gd:_process runs every frame forever** just to poll `_mp_return_deadline` (only nonzero for ~30 s after an MP match). Could use a one-shot Timer or set_process toggling. Trivial cost, but it's the autoload pattern.
6. **VFX.gd creates a new SphereMesh/BoxMesh + StandardMaterial3D per particle** (e.g. 6 spheres per hit_sparks, ~39 per death explosion, 1 per tracer). Meshes could be shared consts; materials per-color cached. Only matters if VFX-heavy fights show GC/alloc spikes.
7. **VFX.tracer broadcasts the RPC before the dist<0.01 early-return**, so degenerate tracers still get sent to clients. Move the early return above the broadcast.

## Priority summary (audit COMPLETE 2026-06-09)

Model tags: [SONNET] = well-specified, low-risk; execute the suggested fix as written.
[SONNET+TEST] = fix is specified but behavior must be verified in a running match.
[OPUS/FABLE] = timing/architecture judgment involved; wrong-but-plausible fixes will
look fine at 60 fps or in SP and break elsewhere — use a stronger model, or instruct
Sonnet to follow the finding's suggested approach literally and not improvise.

**Fix first (affects gameplay now):**
- #1 save_settings loads wrong file (settings.cfg polluted with profile data) [SONNET]
- #21 AI beacon logic inverted for team-0 bots (allied bots in squad play) [SONNET+TEST]
- #17 Patience deals zero damage in MP [SONNET]
- #8 RocketLauncher ghost target uses cross-process instance_id [SONNET+TEST]
- #25 disconnected peers' mechs idle instead of bot-ifying [SONNET+TEST]
- #9 MachineGun ramp broken at >60 fps [OPUS/FABLE]

**Fix when touching MP:** #10, #11, #15, #16, #27 [SONNET+TEST]; #28 seed RPC race [OPUS/FABLE]
(mostly overlap with known open MP bug groups)

**Robustness / latent:** #12, #13, #14, #18, #26, #30, #34 [SONNET]; #22 AI turn-speed
frame dependence [OPUS/FABLE — same class of timing bug as #9; fix both together]

**Cleanup / polish:** #3(33), #4/4b/4c, #19, #23, #24, #29, #31, #32, #35, #2, #5, #6, #7 [SONNET]

**Process note:** whichever model implements should check items off in the Findings
list above and update this summary as batches complete, so any session can resume.

## Next up
Nothing — audit complete. Pick items from priority summary to fix.
