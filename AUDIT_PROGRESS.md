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
1. ~~**Game.gd:351 save_settings() loads the wrong file.**~~ FIXED: `cfg.load(_SETTINGS_PATH)`.
2. ~~**Game.gd:354 save_settings() fallback default for master_volume is 1.0**~~ FIXED: changed to 0.5 in Game.gd and Settings.gd.
3. ~~**Arena.gd:5290 SP win counter assumes player team == 0.**~~ FIXED: now uses `winning_team == player_team`.

### Bugs (Mech / weapons)
8. ~~**RocketLauncher.gd sends raw instance_id over RPC**~~ FIXED: changed to NodePath + `get_node_or_null`. [needs MP test]
9. ~~**MachineGun.gd:51-59 ramp logic breaks at high frame rates.**~~ FIXED: ramp update + `_trigger_held` clear moved to `_physics_process` so both ends of the flag live at physics rate; `_process` keeps only cooldown (super) and reload loop-stop.
10. **MachineGun.fire() duplicates WeaponBase.fire() but drops MP broadcast**: `VFX.muzzle_flash(...)` is called without the broadcast flag and there's no positional fire-sound broadcast (loop player is local to the server). Remote peers see/hear nothing from machine guns. (Related to known open MP bug group.)
11. **Mech.gd:322 `_sync_health` is `unreliable_ordered`, and death (h=0) rides on it.** The final health packet can be dropped, leaving a client showing a live mech (or wrong HP until the next hit). Death should be a reliable RPC (or Arena should broadcast death/respawn reliably — verify in Arena pass).
12. ~~**ProjectileGun/MachineGun/MissileLauncher aim-point can be behind the barrel.**~~ FIXED: added `(aim_point - global_position).dot(cam_fwd) <= 0` guard in all three weapons.
13. ~~**Mech.gd:595 `_net_look_accum` grows without bound in SP/server play**~~ FIXED: drain in `_handle_look` when not a MP client.
14. ~~**Mech.gd:88 `_body_meshes` is captured once in `_ready`**~~ FIXED: rebuild at end of `configure_weapons`.

17. ~~**Patience deals zero damage in MP.**~~ FIXED: PatienceHeavy.tscn `damage` set to 62.5 (= max_damage).
18. ~~**AerialStrike._fire_burst awaits without validity checks**~~ FIXED: `is_instance_valid(self) and is_inside_tree()` guard at top of loop.
19. ~~**PhysicalShield.gd has stray `pass` statements**~~ FIXED: removed.
20. **AerialStrike has no MP ghost broadcast** (rockets invisible to clients), same family as finding 15.

### MP visual/audio gaps (likely overlap with known open MP bug list)
15. RaycastGun tracer + muzzle flash mesh, LaserCannon beam, ArcWeapon beam, Shotgun pellets: all rendered server-side only; no ghost/broadcast for clients. Clients see nothing for these weapons. (Laser already listed in project_mp_bugs_open memory.)
16. **ProjectileGun._rpc_spawn_ghost is `reliable`** — per-bullet reliable RPCs (machine gun ~14/s/mech) add retransmit overhead for purely cosmetic ghosts; `unreliable` is the right channel.

### Bugs (AI)
21. ~~**AIInputSource._pick_target_beacon hardcodes team identity**~~ FIXED: replaced `owner == 1` / `owner == 0` with `owner == _own_team` / `owner == 1 - _own_team`. [needs test in 5v5]
22. ~~**AIInputSource turn speed is frame-rate dependent.**~~ FIXED: AI loop moved from `_process` to `_physics_process` (1:1 with Mech's consumption; also makes per-tick RNG draws frame-rate independent), plus drain-on-read in `get_look_delta` matching PlayerInputSource/NetworkInputSource.
23. ~~**AIInputSource._pick_closest_enemy is dead code**~~ FIXED: deleted.
24. **AIInputSource._enemy_mechs is a spawn-time snapshot** — mechs added later (late joins, anything respawned as a new node) are never targeted. Fine today if Arena spawns everything up front; fragile otherwise.

### Bugs (Arena / MP / match flow)
25. ~~**Bot-ified disconnected mechs stand still.**~~ FIXED: AIInputSource now attached to RemotePlayer (not mech), with fallback if player node not found. [needs test with real disconnect]
26. ~~**Match.gd:41-44 base `_check_win` is inverted**~~ FIXED: `_end_match(i)` (BeaconMatch correctly overrides with drain logic; base class now correct for accumulate mode).
27. **MP respawn loses the hit-confirm crosshair X**: `_rpc_spawn_next_mech` reconnects `damaged` → HUD but not each weapon's `hit_confirmed` → `hud.register_hit` (compare _setup_players_mp:4777-4780). After picking a next squad mech, landing hits no longer flashes the X. (Likely part of the known open "hit X" MP bug.)
28. **Match seed RPC race (verify)**: server `Match.start()` runs in Arena._ready and immediately RPCs `_rpc_set_match_seed`; a slower client that hasn't finished loading Arena yet has no matching node path, so the seed (and deterministic bot RNG) is silently lost for that client. Consider re-sending or piggybacking the seed in `mp_active_match` (it's already there as `match_seed` — clients could just read it locally instead of via RPC).
29. ~~**Lobby/Hangar weapon catalogs omit ROCKET LAUNCHER HV**~~ FIXED: added to both catalogs.
30. ~~**Hangar._build_weapon_picker uses `existing.free()`**~~ FIXED: changed to `queue_free()`.

### Minor / polish
31. ~~**SignIn._confirm doesn't call `Game.save_profile()`**~~ FIXED: added call.
32. ~~**Settings.gd:34 and Game.gd:354 use `master_volume` fallback 1.0**~~ FIXED (see #2).
33. ~~**Arena.gd:5289 SP win counter uses `winning_team == 0`**~~ FIXED (see #3).
34. ~~**HUD._process dereferences `_player_mech.health` with only a null check**~~ FIXED: changed to `is_instance_valid`.
35. **`.uid` files for Lobby.gd / MPEntry.gd / NetworkInputSource.gd are untracked** (git status). Godot 4.4+ uid sidecars should be committed, or references can break across checkouts. Also untracked: MP_AUTODEBUG_PLAN.md, MP_M0_BRIEF.md, error screenshot.

### Dead code / cleanup
4. ~~**autoloads/AIDirector.gd is dead.**~~ FIXED: deleted (+ .uid).
4b. ~~**shaders/health_bar.gdshader is dead**~~ FIXED: deleted (+ .uid).
4c. ~~**Hangar._on_prog_buy empty stub; ArcWeapon._process only calls super**~~ FIXED: both removed.

### Efficiency (minor)
5. ~~**Game.gd:_process runs every frame forever**~~ FIXED: `set_process(false)` in `_ready`/`_do_return_to_lobby`; `set_process(true)` in Arena when deadline is set.
6. **VFX.gd creates a new SphereMesh/BoxMesh + StandardMaterial3D per particle** (e.g. 6 spheres per hit_sparks, ~39 per death explosion, 1 per tracer). Meshes could be shared consts; materials per-color cached. Only matters if VFX-heavy fights show GC/alloc spikes.
7. ~~**VFX.tracer broadcasts the RPC before the dist<0.01 early-return**~~ FIXED: early-return moved above broadcast.

## Priority summary (audit COMPLETE 2026-06-09)

Model tags: [SONNET] = well-specified, low-risk; execute the suggested fix as written.
[SONNET+TEST] = fix is specified but behavior must be verified in a running match.
[OPUS/FABLE] = timing/architecture judgment involved; wrong-but-plausible fixes will
look fine at 60 fps or in SP and break elsewhere — use a stronger model, or instruct
Sonnet to follow the finding's suggested approach literally and not improvise.

**Fix first (affects gameplay now):**
- ~~#1 save_settings loads wrong file~~ DONE
- ~~#17 Patience deals zero damage in MP~~ DONE
- ~~#21 AI beacon logic~~ DONE (needs test)
- ~~#8 RocketLauncher ghost target~~ DONE (needs test)
- ~~#25 disconnected peers' mechs idle~~ DONE (needs test)
- ~~#9 MachineGun ramp broken at >60 fps~~ DONE

**Fix when touching MP:** #10, #11, #15, #16, #27 [SONNET+TEST]; #28 seed RPC race [OPUS/FABLE]
(mostly overlap with known open MP bug groups)

**Robustness / latent:**
- ~~#12, #13, #14, #18, #26, #30, #34~~ DONE
- ~~#22 AI turn-speed frame dependence~~ DONE (fixed together with #9)

**Cleanup / polish:**
- ~~#2, #3(33), #4/4b/4c, #5, #7, #19, #23, #29, #31, #32, #33, #34, #35~~ DONE
- #24 _enemy_mechs spawn-time snapshot [SONNET — low priority]
- #6 VFX mesh/material allocation per particle [SONNET — only if GC spikes appear]

## Next up
- ~~#9, #22 MachineGun ramp + AI turn-speed~~ DONE 2026-06-09
- #10, #11, #15, #16, #27 MP visual/audio gaps + #28 seed RPC race [batch when touching MP]
  (do these in the T129 LAN-smoke session -- see MP_PLAN.md Phase 15 -- along with verifying the
  [needs MP test] fixes #8, #21, #25)
- #24 _enemy_mechs snapshot, #6 VFX alloc [low priority]
