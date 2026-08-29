# Hardpoint Code Review — 2026-07-03

**Scope read:** all root docs, `tools/*.py`, `autoloads/` (Game, SoundManager, VFX), and core scripts: Mech, Beacon, BeaconMatch, Match, WeaponBase, ProjectileGun, Projectile, HomingProjectile, AIInputSource, PlayerInputSource, NetworkInputSource, InputSource, BipedLegs, EnergyShield, Player, Pilot, HUD.
**Not read:** Arena.gd body (660KB — truncated; only the header const blocks seen), Hangar/Lobby/Settings/TitleScreen, weapon subclasses (MachineGun, Shotgun, RaycastGun, LaserCannon, ArcWeapon, Patience, AerialStrike, RocketLauncher), MechVisuals, BeaconDot, Crosshair, WeaponHUD, shaders, `.tscn` scenes.

---

## 1. Bugs — high confidence

### 1.1 `Game.save_settings()` loads the wrong file
```gdscript
func save_settings() -> void:
    var cfg := ConfigFile.new()
    cfg.load(_SAVE_PATH)        # ← profile.cfg, not settings.cfg
    ...
    cfg.save(_SETTINGS_PATH)
```
Every settings save copies your entire **profile + loadout** sections into `settings.cfg`. Should be `cfg.load(_SETTINGS_PATH)`. Bonus inconsistency: the fallback here is `master_volume 1.0` while the runtime default is `0.5` (B25's fix) — if the key is ever missing you're back to ear-blasting volume.

### 1.2 Beacon stuck in CONTESTED state forever
`Beacon._update_capture()`: state only *leaves* CONTESTED via a completed capture. If the attacker leaves (teams = [owner] → `team == owner_team → return`) or everyone leaves (`teams.is_empty() → return`), the early returns skip any state restore. The beam/cap/HUD dot stays yellow indefinitely. Scoring is unaffected (`owner_team` is correct) — it's a state/visual bug, cousin of B28.

### 1.3 Bot turn speed is framerate-dependent
`AIInputSource.get_look_delta()` returns `_look_delta` **without clearing it** (PlayerInputSource and NetworkInputSource both drain on read). The AI writes it in `_process` (render rate) but `Mech._handle_look()` consumes it every `_physics_process` tick (60Hz). At 30fps render — likely on the T3500 target — each computed delta is applied ~twice, *and* it was computed with a 2× render delta. Bots effectively turn much faster the slower the machine runs. This is the same family as B24's oscillation and V11's "no per-frame damage" rationale. Fix: zero `_look_delta` on read, or move AI to `_physics_process`.

### 1.4 Bots are blind to respawned mechs
`AIInputSource._find_targets()` snapshots `_enemy_mechs` **once at spawn**. With squad lives (T64/T127 — both done), the player's next mech is a brand-new node that no existing bot has in its list. After your first death, enemy bots stop shooting at you entirely (they'll only walk beacons). Same for any respawned MP peer. The `"mechs"` group already exists — query it live in `_pick_best_target`, or refresh lists on every spawn.

### 1.5 Remote peers inherit the *host's* pilot skills
All live skill polls are gated on `is_human_input()`, and `NetworkInputSource.is_human_input()` returns `true`. On the server, remote peers' mechs therefore pass every gate — `repair_rate` (Mech._process), `ability_recharge`, `beacon_capture`, `contested_hold` (Beacon) — but `Game.get_skill_effect()` reads the **host's local profile**. Every human in an MP match gets the host's skill build for the per-event skill class. V21's gate meant "not a bot" (SP); MP needs "which human." Fix direction: snapshot the owning peer's skill effects onto the Mech at spawn (extend `apply_pilot_skills` to take a data dict from lobby metadata) instead of polling the autoload.

### 1.6 MP 30s return-to-lobby timeout is never armed
`Game._mp_return_deadline` is checked in `_process` and cleared in `_do_return_to_lobby()`, but **nothing ever sets it non-zero** (checked Game, HUD, Match, Mech). T121 specifies "all confirm OR 30s timeout." A peer who quits/crashes on the stats screen stalls everyone forever — and `_on_mp_peer_disconnected` only prunes peers while in the *lobby* phase (`roster.is_empty()`), so their confirmation will never arrive either. Two fixes needed: arm the deadline in `_rpc_match_end`, and count disconnects as confirmations.

### 1.7 T124's damage sender-ownership check doesn't exist
`Mech._take_damage_rpc` validates only that the sender is *some* lobby peer:
```gdscript
if not Game.mp_lobby["peers"].has(sender): ... return
```
T124 is marked done with "`_take_damage_rpc` … add sender = projectile/weapon owner check", but no ownership check is present. Any connected client can RPC damage onto any mech, choosing `src_path` itself (subject only to the 1.5× clamp and range gate — both computed from the weapon the *client* named). Under V30 (server-authoritative projectiles) clients should arguably never originate damage at all — consider rejecting non-server senders outright.

### 1.8 Remote clients lose ~half their keypresses
`Mech._maybe_forward_input()` sends every 2nd physics tick (30Hz), but reload / ability / slot-toggle come from `Input.is_action_just_pressed`, which is true for **one** frame. Presses landing on the skipped tick are silently dropped. Latch one-shot inputs every tick and flush them with the next send (the look accumulator already does this correctly).

### 1.9 Projectile splash measured from the wrong point
`Projectile.gd` computes splash distance from `global_position` (start-of-tick), not `result.position` (impact) — at missile speeds that's meters of error, shrinking effective splash radius. `HomingProjectile.gd` already uses `result.position`; make them match.

---

## 2. Suspected bugs (need runtime confirmation / unread files)

- **Client ammo HUD frozen in MP** — client weapons never fire locally (V38) and there's no ammo/reload sync RPC, so WeaponHUD on a remote peer likely shows static ammo forever. T129 smoke test would surface it.
- **`Game.host()` doesn't reset `mp_lobby` / `mp_active_match`** — re-hosting after a previous session may carry stale peers/roster unless Lobby.tscn clears it (didn't read Lobby).
- **Contested-hold sentinel** — `if _contested_hold_timer == 0.0: re-arm` float-equality loop re-arms every expiry. Harmless today (state is already CONTESTED) but fragile; use an explicit `_hold_armed` bool.
- **HUD `_process` lacks `is_instance_valid(_player_mech)`** — mechs are hidden not freed today, so it holds; the first code path that frees a mech (MP respawn cleanup?) turns this into a crash.

---

## 3. Design concerns

- **V17 enforcement by filename** — `Game._weapon_size_from_path()` returns Heavy iff `"Heavy" in path`. A rename or a mech path containing "Heavy" silently breaks squad validation. The weapon scene already has `slot_size`; load it and read the real value.
- **`is_human_input()` is overloaded** — means "not a bot" in some call sites and "the local player" in others (root cause of bug 1.5). Split into `is_human()` and `is_local_player()`.
- **`Mech._net_look_accum` grows unboundedly** on host/SP — only drained on the client send path. Zero it when not forwarding.
- **Defender presence doesn't decay attacker capture progress** — progress only decays when the zone is *empty*, so an attacker resumes exactly where they left off even after the owner "defended" the beacon. If intentional, document it in SPEC; it reads like an oversight.
- **HUD `_update_team_counts` hardcodes team 0 as `1 + allies`** — wrong once squad lives (5 mechs per player) or MP rosters exist.
- **`BipedLegs._face_velocity` ignores its `rot_speed` parameter** — `Mech.leg_rotation_speed` export is dead; actual rate is `pow(walk_speed, 1.5) * 2.5`. Delete the export/param or honor it.
- **`Player.on_pawn_destroyed` → `get_parent().on_player_eliminated(self)`** — hard structural coupling; a signal would match the rest of the architecture.
- **BeaconMatch tie-break** — if both scores hit 0 the same tick, team 1 always wins (team 0 checked first). Pick a rule deliberately.
- **VFX / SoundManager attach to `current_scene` / root with no null guard** — a death explosion or SFX racing a scene change crashes. One-line guard.
- **`Mech.fire_weapon(slot, aim)`** — `aim` param accepted and ignored; either wire it (T40 will need it) or drop it until then.

---

## 4. Inefficiencies

- **`print()` in the damage hot path** — `_apply_damage` prints every hit; beam weapons tick at 10Hz per weapon per target. Constant terminal I/O on the exact low-end box you target. Gate behind a debug flag. (You run from terminal on purpose, but this is spam even for that.)
- **Arena.gd is ~660KB of baked const arrays** (`_PENROSE_VERTS`, `_PENROSE_EDGES`, `_PENROSE_COLUMN_VERTS`, …). Script parse/compile cost at load, permanent memory, and the file is unnavigable/undiffable. Move generator output to `.res`/JSON loaded at `_ready`, keep Arena.gd as logic. Your own V13 spirit ("baked data → tools") half-applies: the *generation* moved to Python, but the *payload* still lives in script source.
- **VFX allocates a fresh `StandardMaterial3D` + `SphereMesh` per particle** — hit_sparks = 6 materials/hit, death explosion = ~39. `Projectile.gd` already demonstrates the fix (static shared mesh/mat); only tweened emission needs a per-instance duplicate. T106 benched clean, so this is opportunistic — but it's the first thing to revisit if MP raises effect counts.
- **Beacon `_update_capture` allocates a filtered array per team per frame** — trivial cost; a reverse-iteration erase is free if you're touching the file anyway.
- **`hat_floor_4096.png` (392KB) committed but export-excluded** — fine as source data, but it belongs in `tools/` with the other generator artifacts.

---

## 5. Docs / spec drift

These matter more than usual since SPEC.md is the machine ground-truth for your Claude Code sessions:

- **DESIGN.md is stale** and self-describes as canonical: 320×180 render (actual: 640×360), white/grey/blue "mathematical temple" art direction (actual: Matrix-3 steam/cyberpunk), "**only one autoload**" (V5 allows three), "server-authoritative **with client prediction**" (V37: interpolation-only, prediction deferred to T131). Either update it or demote it to history.
- **GRAPHICS_PLAN.md §C forbids normal maps** while SPEC T78 (marked done) evaluates normal-mapped arena edges. One of them is lying.
- **Task-status drift**: T124 marked `x` but the ownership check is absent (§1.7); T121 marked `x` but the 30s timeout is unarmed (§1.6). If `/check` trusts `x`, these never get revisited.
- **README controls table** lacks Q (ability) and Tab (spectate-cycle); T81 added them to the Settings screen only.
- **Naming**: repo `Hardpoint`, README title `MechBattle`, CLAUDE.md `mechbattle`, binary `mechbattle_X.X.X`. Pick one.

---

## 6. Tooling nits (`tools/*.py`)

- `hat_floor_tex.py` — `color_bucket()` is dead code ending in `return -1 if False else 0`; delete it.
- `hat_floor_tex.py` — scanline fill pads the right edge: `x1 = int(xs[i+1]) + 1` overdraws by a pixel. Harmless at 1024px, but it's where chunky shared edges come from.
- Generators print GDScript to stdout for hand-pasting — combined with the 660KB Arena.gd, emit `.res`/JSON files directly instead.

---

## 7. Checked and fine

Rate limiter window math; ELO/XP/level formulas; skill-tree unlock gating (points = level − unlocked); step-up raycast pair; lock hold-cone fix (B22/B23); beacon drain model (T48); the InputSource abstraction and Player/Pawn split; T95/T96 chokepoint seams; NetworkInputSource one-shot semantics (server side); cosmetic-RNG tagging. The architecture discipline here is genuinely good — nearly every real bug above is at the seams the invariants don't yet cover (MP identity, respawn lifecycles, doc/task truthfulness).
