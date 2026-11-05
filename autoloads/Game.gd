extends Node
# Singleton -- cross-match persistent state.
#
# Data ownership:
#   profile  -- server-owned fields (wins/losses/pilot_name). Keep clean for future sync.
#   loadout  -- server-owned fields (chosen mech, weapon config). Same rule.
#   settings -- local-only fields (mouse sensitivity). Never sent to server.
#
# Also hosts bot-coordination (formerly AIDirector autoload) to stay within the
# three-autoload V5 limit.

const _SAVE_PATH     := "user://profile.cfg"
const _SETTINGS_PATH := "user://settings.cfg"

# ELO constants
const _ELO_K := 32
const _BOT_ELO_BY_DIFFICULTY: Array = [800, 1000, 1200, 1400, 1600]

# Skill tree: Fibonacci coin costs for upgrade levels 2-12
const _SKILL_FIB_COSTS: Array[int] = [100, 200, 300, 500, 800, 1300, 2100, 3400, 5500, 8900, 14400]

# key -> {parents: Array[String], any_parent: bool, label: String, per_level: float}
# parents empty = root skill; any_parent=true means ONE parent unlocked suffices
const SKILL_TREE: Dictionary = {
	"damage":           {"parents": [],                             "any_parent": false, "label": "Damage",           "per_level": 0.015},
	"health":           {"parents": [],                             "any_parent": false, "label": "Health",            "per_level": 0.02},
	"projectile_speed": {"parents": ["damage"],                     "any_parent": false, "label": "Projectile Speed",  "per_level": 0.01},
	"spread_reduction": {"parents": ["projectile_speed"],           "any_parent": false, "label": "Spread Reduction",  "per_level": 0.06},
	"repair_rate":      {"parents": ["health"],                     "any_parent": false, "label": "Repair Rate",       "per_level": 0.5},
	"shield_capacity":  {"parents": ["health"],                     "any_parent": false, "label": "Shield Capacity",   "per_level": 0.05},
	"move_speed":       {"parents": ["damage", "health"],           "any_parent": true,  "label": "Move Speed",        "per_level": 0.01},
	"beacon_capture":   {"parents": ["move_speed"],                 "any_parent": false, "label": "Beacon Capture",    "per_level": 0.05},
	"contested_hold":   {"parents": ["beacon_capture"],             "any_parent": false, "label": "Contested Hold",    "per_level": 0.5},
	"ability_recharge": {"parents": ["damage", "health"],           "any_parent": true,  "label": "Ability Recharge",  "per_level": 0.05},
	"powerup_duration": {"parents": ["ability_recharge"],           "any_parent": false, "label": "Powerup Duration",  "per_level": 0.05},
	"coin_pickup":      {"parents": ["ability_recharge"],           "any_parent": false, "label": "Coin Pickup",       "per_level": 0.03},
	"xp_bonus":         {"parents": ["ability_recharge"],           "any_parent": false, "label": "XP Bonus",          "per_level": 0.03},
	"reload_speed":     {"parents": ["damage", "ability_recharge"], "any_parent": true,  "label": "Reload Speed",      "per_level": 0.04},
	"lock_speed":       {"parents": ["damage", "ability_recharge"], "any_parent": true,  "label": "Lock Speed",        "per_level": 0.05},
}

# Cumulative XP required to reach each level (index 0 = XP to reach level 2, etc.)
# Formula: _LEVEL_THRESHOLDS[n-1] = sum of (i*100) for i in 1..n
const _LEVEL_THRESHOLDS: Array = [
	100, 300, 600, 1000, 1500, 2100, 2800, 3600, 4500, 5500,
	6600, 7800, 9100, 10500, 12000, 13600, 15300, 17100, 19000,
]  # 19 entries for levels 2-20

var profile: Dictionary = {
	"pilot_name": "Pilot",
	"wins": 0,
	"losses": 0,
	"elo": 1000,
	"xp": 0,
	"level": 1,
	"coins": 0,
	"skills": {},  # skill_key -> level (1-12); absent = locked
}

# Loadout is set in Hangar and consumed by Arena.
# mech_def is a MechDef resource; null until Hangar initialises it.
var loadout: Dictionary = {
	"mech_def": null,
	"bot_def": preload("res://resources/mechs/Hippogriff.tres"),
	"weapon_overrides": [],        # Array[PackedScene|null], parallel to mech_def.weapon_slots
	"mech_weapon_choices": {},     # {mech_resource_path: [weapon_scene_path, ...]}
	"team_size": 1,                # mechs per team (1 = 1v1, 5 = 5v5)
	"squad": [],                   # Array of 5 mech resource paths (slot 0 = player mech)
	"presets": {},                 # T177: {name: {"squad": [mech paths], "weapons": {mech path: [weapon paths]}}}
	"map_def": null,               # MapDef resource; null = Math Temple (default)
}

## T196: over-the-shoulder side of the local view, +1 right / -1 left (V swaps).
var shoulder := 1.0

var settings: Dictionary = {
	"mouse_sensitivity": 0.003,
	"bot_difficulty": 1,  # 0=Easy  1=Normal  2=Medium  3=Hard  4=Elite
	"master_volume": 0.5,
	"shadows": "blob",  # T193: "blob" (disc under each mech, no sun shadows) or "full"
}

# M0.1: central seeded RNG for all gameplay randomness (weapon spread, etc.).
# Seeded from the match_seed in Match.start() (MP: the _rpc_match_start payload) so the server
# (and any deterministic replay) produces a reproducible physics tick stream.
# Cosmetic randomness (VFX, camera shake, drop-pod debris) stays on the global
# randf_range and is intentionally NOT routed here.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func seed_rng(s: int) -> void:
	rng.seed = s

# T165: opt-in per-system frame-time accumulators (soak runs set prof_on); one bool
# check per call when off. Harness perf lines report usec per system per window.
var prof_on: bool = false
var _prof_frame: Dictionary = {}   # this physics frame: key -> usec
var _prof: Dictionary = {}         # window: key -> [sum_usec, max_frame_usec, frames]

func prof_add(key: String, usec: int) -> void:
	_prof_frame[key] = int(_prof_frame.get(key, 0)) + usec

# Called once per physics frame (harness). "phys" = engine-reported total physics
# time of the last frame, so per-frame maxima show whether spikes are in our scripts
# or elsewhere (physics step, node churn).
func prof_end_frame() -> void:
	_prof_frame["phys"] = int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0)
	_prof_frame["nav"] = int(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000000.0)
	_prof_frame["pairs"] = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)) * 1000  # count, shown as x1000
	for k in _prof_frame:
		var e: Array = _prof.get(k, [0, 0, 0])
		var v: int = _prof_frame[k]
		_prof[k] = [e[0] + v, maxi(e[1], v), e[2] + 1]
	_prof_frame = {}

func prof_take() -> Dictionary:
	var d := _prof
	_prof = {}
	return d

# ---- M0.2: sync snapshot logging (flag-gated, zero-cost when off) ----
# Writes one JSONL line per physics tick per tracked mech plus an event stream,
# for the MP autodebug determinism self-test and oracle tools. This is the one
# justified runtime-logging exception to V13 (a Python tool cannot read live
# game state). All comparison/oracle logic lives in tools/*.py, not here.
# Enable with the cmdline flag "--sync-log" (engine arg or after a "--"
# separator). Optional "--sync-role=server|client" and "--sync-dir=<path>"
# override the auto-detected role and output directory.
var sync_logging_enabled: bool = false
var _sync_role_override: String = ""
var _sync_dir: String = "user://"
var _sync_snap_file: FileAccess = null
var _sync_event_file: FileAccess = null
var _sync_beacon_file: FileAccess = null
var _sync_files_open: bool = false
var _sync_start_ms: int = 0
var _sync_start_frame: int = 0
var _sync_rpc_seq: int = 0
var _sync_cli: bool = false  # --sync-log given (harness / manual run): it owns the log dir
var _sync_base: String = ""   # T157: file base of this peer's logs (server / client_<id>)

func _parse_sync_log_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for a in args:
		if a == "--sync-log":
			sync_logging_enabled = true
		elif a.begins_with("--sync-role="):
			_sync_role_override = a.get_slice("=", 1)
		elif a.begins_with("--sync-dir="):
			_sync_dir = a.get_slice("=", 1)
	_sync_cli = sync_logging_enabled

func _sync_role() -> String:
	if _sync_role_override != "":
		return _sync_role_override
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return "client"
	return "server"

func _open_sync_files() -> void:
	var role := _sync_role()
	var peer := 1
	if multiplayer.has_multiplayer_peer():
		peer = multiplayer.get_unique_id()
	# A given --sync-role is used verbatim as the filename base so two runs line
	# up (ENet assigns a fresh unique_id each run, so peer id is not stable).
	var base := _sync_role_override if _sync_role_override != "" else ("%s_%d" % [role, peer] if role == "client" else role)
	_sync_base = base
	var dir := _sync_dir.trim_suffix("/")
	_sync_snap_file = FileAccess.open("%s/%s.jsonl" % [dir, base], FileAccess.WRITE)
	_sync_event_file = FileAccess.open("%s/%s.events.jsonl" % [dir, base], FileAccess.WRITE)
	_sync_beacon_file = FileAccess.open("%s/%s.beacons.jsonl" % [dir, base], FileAccess.WRITE)
	if _sync_snap_file == null or _sync_event_file == null:
		push_error("Game: sync-log could not open output files in %s" % dir)
		sync_logging_enabled = false
		return
	_sync_start_ms = Time.get_ticks_msec()
	# Tick is match-relative (frames since the first logged tick), not absolute
	# engine frames: two independently launched processes boot in a variable
	# number of frames, so only a relative tick lines up in the self-test.
	_sync_start_frame = Engine.get_physics_frames()
	_sync_files_open = true

# ---- T157: session recorder ----
# A real MP session (no --sync-log, i.e. not a harness run) records the same logs to
# user://sessions/<date_time>/ plus a half-size JPG every 10 s on a rendered peer, so
# "it was weird at minute 3" can go through the oracles (tools/session_window.py,
# then sync_compare.py tools/sessions/real_session.json; docs/SESSION_RECORDING.md).
# ponytail: full 60 Hz like the harness (~15 MB/min per peer, ~1 ms/frame on a 7-mech
# host); keep the newest SESSIONS_KEEP; add a tick stride if size or cost ever shows.
const SESSIONS_DIR := "user://sessions"
const SESSIONS_KEEP := 3
const SESSION_SHOT_TICKS := 600
var _recording: bool = false

func _session_start() -> void:
	if _sync_cli:
		return
	_session_stop()
	DirAccess.make_dir_recursive_absolute(SESSIONS_DIR)
	var old := Array(DirAccess.get_directories_at(SESSIONS_DIR))
	old.sort()
	while old.size() >= SESSIONS_KEEP:
		_rm_tree(SESSIONS_DIR.path_join(old.pop_front()))
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	_sync_dir = SESSIONS_DIR.path_join(stamp)
	DirAccess.make_dir_recursive_absolute(_sync_dir)
	_sync_root = ""
	_sync_match = 0
	sync_logging_enabled = true
	_recording = true
	set_physics_process(true)

func _session_stop() -> void:
	if not _recording:
		return
	_recording = false
	_wait_shot()
	sync_logging_enabled = false
	for f in [_sync_snap_file, _sync_event_file, _sync_beacon_file]:
		if f != null:
			f.close()
	_sync_files_open = false
	set_physics_process(false)

func _rm_tree(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_rm_tree(path.path_join(d))
	DirAccess.remove_absolute(path)

func _session_shot(tick: int) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_sync_dir.path_join("%s_%06d.jpg" % [_sync_base, tick]))
	_wait_shot()
	_shot_task = WorkerThreadPool.add_task(func() -> void:  # encode off the main thread: no hitch
		img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_jpg(path, 0.7))

# Every WorkerThreadPool task must be waited for (Godot docs); an unwaited one crashed
# the engine at exit (SIGSEGV in shutdown, T157 e2e run).
var _shot_task: int = -1

func _wait_shot() -> void:
	if _shot_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_shot_task)
		_shot_task = -1

func _exit_tree() -> void:
	_wait_shot()

# T163: match 2+ of one session logs to <sync-dir>/match<N>/ (fresh files, tick 0
# at that match's first mech frame) so oracles judge each match on its own.
var _sync_match: int = 0
var _sync_root: String = ""

func _sync_next_match() -> void:
	_sync_match += 1
	if _sync_match < 2 or not _sync_files_open:
		return
	for f in [_sync_snap_file, _sync_event_file, _sync_beacon_file]:
		if f != null:
			f.close()
	_sync_files_open = false
	if _sync_root == "":
		_sync_root = _sync_dir.trim_suffix("/")
	_sync_dir = _sync_root.path_join("match%d" % _sync_match)
	DirAccess.make_dir_recursive_absolute(_sync_dir)

func _physics_process(_delta: float) -> void:
	if not prof_on:  # T165 profiling shim (harness sync logging is test-only cost)
		_physics_process_impl(_delta)
		return
	var t0 := Time.get_ticks_usec()
	_physics_process_impl(_delta)
	prof_add("synclog", Time.get_ticks_usec() - t0)

func _physics_process_impl(_delta: float) -> void:
	if not sync_logging_enabled:
		return
	var mechs := get_tree().get_nodes_in_group("mechs")
	if mechs.is_empty():
		return  # no match yet; defer file open until there is state to log
	if not _sync_files_open:
		_open_sync_files()
		if not _sync_files_open:
			return
	# Deterministic iteration order so two runs of the same seed line up.
	mechs.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
	var tick := Engine.get_physics_frames() - _sync_start_frame
	var wall := Time.get_ticks_msec() - _sync_start_ms
	var role := _sync_role()
	var peer := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	for m in mechs:
		_sync_snap_file.store_line(JSON.stringify(_mech_snapshot(m, tick, wall, role, peer)))
	if _recording and tick % SESSION_SHOT_TICKS == 0 and DisplayServer.get_name() != "headless":
		_session_shot(tick)
	# M2.1: per-tick beacon state stream (own file so mech oracles stay untouched).
	# Server fields are authoritative; client fields arrive via Beacon._sync_progress
	# and _sync_state RPCs (T105), which is exactly the seam beacon_desync checks.
	if _sync_beacon_file != null:
		var beacons := get_tree().get_nodes_in_group("beacons")
		beacons.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
		for b in beacons:
			_sync_beacon_file.store_line(JSON.stringify({
				"tick": tick,
				"peer": peer,
				"beacon_id": b.name,
				"state": int(b.get("state")),
				"owner_team": b.get("owner_team"),
				"progress": snappedf(b.get("_capture_progress"), 0.001),
				"capturing_team": b.get("_capturing_team"),
			}))

func _mech_snapshot(m: Node, tick: int, wall: int, role: String, peer: int) -> Dictionary:
	var torso: Node3D = m.get("torso")
	var rot_local := Quaternion.IDENTITY
	var rot_global := Quaternion.IDENTITY
	if torso != null:
		rot_local = torso.transform.basis.get_rotation_quaternion()
		rot_global = torso.global_transform.basis.get_rotation_quaternion()
	var pos: Vector3 = m.global_position
	# T140: aim as plain floats; quaternion snapping noise (~0.04 rad) hides small drift
	var yaw: float = torso.rotation.y if torso != null else 0.0
	var pitch = m.get("_camera_pitch")
	var aim := [snappedf(yaw, 0.00001), snappedf(pitch if pitch != null else 0.0, 0.00001)]
	var ammo: Dictionary = {}
	var ammo_max: Dictionary = {}  # T149: world_invariants range check (-1 = infinite)
	var reloading: Dictionary = {}
	var loops: Array = []  # T155: weapon slots whose loop audio (arc/laser beam) is playing
	var weapons = m.get("_weapons")
	if weapons is Array:
		for i in weapons.size():
			var w = weapons[i]
			if w != null:
				var lp = w.get("_loop_player")
				if lp != null and lp.playing and not lp.stream_paused:  # audible (a disabled node pauses its player)
					loops.append(i)
				ammo[str(i)] = w.get("ammo")
				ammo_max[str(i)] = w.get("max_ammo")
				reloading[str(i)] = w.get("_reloading")
	var lock = m.get("locked_target")
	var lock_id = (lock.name as String) if lock != null and is_instance_valid(lock) else null
	var elig = m.get("lock_eligible_target")  # T148: the red aim box target
	var elig_id = (elig.name as String) if elig != null and is_instance_valid(elig) else null
	var cds: Dictionary = {}
	var raw_cds = m.get("_ability_cooldowns")
	if raw_cds is Dictionary:
		for k in raw_cds:
			cds[str(k)] = snappedf(raw_cds[k], 0.001)
	return {
		"tick": tick,
		"wall_ms": wall,
		# T151: shared wall clock (all harness peers run on one machine) -- oracles align
		# client ticks to the server's by it; per-peer tick anchors differ by up to ~1 s
		# when the reliable match-start packet is lost and resent.
		"unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"peer": peer,
		"role": role,
		"mech_id": m.name,
		"owner": m.get("owner_peer_id"),
		"pos": [snappedf(pos.x, 0.0001), snappedf(pos.y, 0.0001), snappedf(pos.z, 0.0001)],
		"rot_local": [snappedf(rot_local.x, 0.0001), snappedf(rot_local.y, 0.0001), snappedf(rot_local.z, 0.0001), snappedf(rot_local.w, 0.0001)],
		"rot_global": [snappedf(rot_global.x, 0.0001), snappedf(rot_global.y, 0.0001), snappedf(rot_global.z, 0.0001), snappedf(rot_global.w, 0.0001)],
		"aim": aim,
		"scale": snappedf(m.global_transform.basis.get_scale().x, 0.001),  # T142: body_scale must survive replication
		"health": snappedf(m.get("health"), 0.01),
		"vel": [snappedf(m.velocity.x, 0.01), snappedf(m.velocity.y, 0.01), snappedf(m.velocity.z, 0.01)],  # T152 stuck check
		"max_hp": m.get("max_health"),
		"ammo_max": ammo_max,
		"ammo": ammo,
		"lock_target": lock_id,
		"eligible": elig_id,
		"active_set": m.get("_active_set"),
		"reloading": reloading,
		"loops": loops,
		"team": m.get("team"),
		"abilities": cds,
	}

# Public event-stream API. type = fired|hit|captured|died|spawned|ability.
# rpc_seq is a monotonic counter so dropped/reordered events are detectable.
func sync_log_event(type: String, mech_id: String, payload: Dictionary = {}) -> void:
	if not sync_logging_enabled or not _sync_files_open:
		return
	var t0 := Time.get_ticks_usec() if prof_on else 0
	var peer := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	_sync_rpc_seq += 1
	_sync_event_file.store_line(JSON.stringify({
		"tick": Engine.get_physics_frames() - _sync_start_frame,
		"peer": peer,
		"type": type,
		"mech_id": mech_id,
		"payload": payload,
		"rpc_seq": _sync_rpc_seq,
	}))
	if prof_on:
		prof_add("synclog", Time.get_ticks_usec() - t0)

# ---- Multiplayer transport (V5: no new autoload; stays in Game.gd) ----

signal mp_peer_connected(id: int)
signal mp_peer_disconnected(id: int)
signal mp_join_failed
signal mp_server_lost

func _ready() -> void:
	_load_profile()
	_load_settings()
	_load_loadout()
	multiplayer.peer_connected.connect(_on_mp_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	multiplayer.connection_failed.connect(_on_mp_connection_failed)
	multiplayer.server_disconnected.connect(_on_mp_server_disconnected)
	# T170 (B64): every connection passes an auth step first; the host refuses mid-match
	# joiners there, so they never enter the connected set (see _on_mp_peer_authenticating).
	var smp := multiplayer as SceneMultiplayer
	smp.auth_callback = _on_mp_auth
	smp.auth_timeout = AUTH_TIMEOUT_S
	smp.peer_authenticating.connect(_on_mp_peer_authenticating)
	set_process(false)
	_parse_sync_log_args()
	set_physics_process(sync_logging_enabled)  # M0.2: zero-cost when flag off
	_maybe_start_harness()  # M0.4: only when --mp-scenario= is present
	_maybe_start_dedicated()  # T204: only when --server is present

# M0.4: spin up the autodebug harness driver, isolated from the normal UI path.
func _maybe_start_harness() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for a in args:
		if a.begins_with("--mp-scenario="):
			var h: Node = load("res://tools/mp_harness/Harness.gd").new()
			h.name = "MPHarness"
			add_child.call_deferred(h)
			return

# ---- T204: dedicated server ----
# `godot --headless --path <project> -- --server[=port] [--team-size=N] [--map=<res path>]
#   [--min-players=N] [--no-bots]`: hosts with no local player and no menus. The lobby
# lives on the server (Lobby scene, no own entry): players JOIN by address, ready up,
# and the match starts LOBBY_COUNTDOWN_S after everyone is ready (a new joiner or an
# unready cancels it); bots fill the teams. Match -> lobby loops with no human host.
const LOBBY_COUNTDOWN_S := 5.0
var dedicated := false
var _min_players := 1
var _countdown_id := 0  # bumps on every lobby change; a stale countdown does nothing

func _maybe_start_dedicated() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var port := -1
	var opts := {}
	for a in args:
		if a == "--server" or a.begins_with("--server="):
			port = int(a.get_slice("=", 1)) if a.contains("=") else 8910
		elif a.begins_with("--team-size="):
			opts["team_size"] = int(a.get_slice("=", 1))
		elif a.begins_with("--map="):
			opts["map_path"] = a.get_slice("=", 1)
		elif a.begins_with("--min-players="):
			opts["min_players"] = int(a.get_slice("=", 1))
		elif a == "--no-bots":
			opts["bot_fill"] = false
	if port > 0 and not has_node("MPHarness"):
		start_dedicated.call_deferred(port, opts)

## Also the harness's entry for "dedicated" scenarios (the same code path as --server).
func start_dedicated(port: int, opts: Dictionary = {}) -> void:
	dedicated = true
	_min_players = maxi(1, int(opts.get("min_players", 1)))
	host(port)
	if not multiplayer.multiplayer_peer is ENetMultiplayerPeer:  # offline also "is_server"
		push_error("[Server] could not host on port %d" % port)
		get_tree().quit(1)
		return
	mp_lobby = {
		"peers":      {},
		"bot_fill":   bool(opts.get("bot_fill", true)),
		"team_size":  clampi(int(opts.get("team_size", 5)), 1, 6),
		"map_path":   String(opts.get("map_path", "res://resources/maps/MathTemple.tres")),
		"match_seed": 0,
	}
	account_server = load("res://scripts/AccountServer.gd").new()  # T207: accounts on port + 1
	account_server.name = "AccountServer"
	add_child(account_server)
	account_server.start(port + 1)
	print("[Server] dedicated on port %d: team size %d, bots %s, map %s, min players %d" % [port,
		mp_lobby["team_size"], mp_lobby["bot_fill"], mp_lobby["map_path"], _min_players])
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")

# Server: any lobby change re-arms (or cancels) the start countdown.
func _dedicated_lobby_changed() -> void:
	if not dedicated or not mp_active_match["roster"].is_empty():
		return
	_countdown_id += 1
	var peers: Dictionary = mp_lobby["peers"]
	var go := peers.size() >= _min_players
	for pid in peers:
		go = go and bool(peers[pid].get("ready", false))
	if bool(mp_lobby.get("starting", false)) != go:
		mp_lobby["starting"] = go
		_rpc_sync_lobby.rpc(mp_lobby)
	if not go:
		return
	var my_id := _countdown_id
	print("[Server] all %d ready; match in %.0f s" % [peers.size(), LOBBY_COUNTDOWN_S])
	get_tree().create_timer(LOBBY_COUNTDOWN_S).timeout.connect(func() -> void:
		if my_id != _countdown_id or not mp_active_match["roster"].is_empty():
			return
		mp_lobby["starting"] = false
		var lobby: Script = load("res://scripts/Lobby.gd")
		var roster: Array = lobby.call("_build_roster")
		mp_lobby["match_seed"] = randi()
		print("[Server] match start: %d players, %d mechs" % [peers.size(), roster.size()])
		_rpc_match_start.rpc(mp_lobby["map_path"], roster, mp_lobby["match_seed"]))

# ---- T207: online accounts (client) ----
# Signed in = `account` holds {host, port, email, session, profile}; Game.profile is the
# account's (from the server) and never written to the local profile.cfg (save_profile).
# Passwords only ever go to the account endpoint (TLS, game port + 1); the game connection
# carries the session token (auth handshake). Sessions last for this run of the game.
var account: Dictionary = {}
var account_server: Node = null  # server: AccountServer when dedicated
var account_mode := "login"      # Account screen: "login" | "signup"

## One request to a server's account endpoint -> its reply ({"ok": false, "error"} on failure).
func account_request(host_addr: String, port: int, req: Dictionary) -> Dictionary:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host(host_addr, port + 1) != OK:
		return {"ok": false, "error": "cannot reach the server"}
	var tls := StreamPeerTLS.new()
	var t0 := Time.get_ticks_msec()
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t0 < 5000:
		tcp.poll()
		await get_tree().process_frame
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return {"ok": false, "error": "cannot reach the server"}
	# ponytail: no certificate check (self-signed, AccountServer notes); encrypted only
	if tls.connect_to_stream(tcp, "hardpoint", TLSOptions.client_unsafe()) != OK:
		return {"ok": false, "error": "secure connection failed"}
	var sent := false
	var buf := PackedByteArray()
	while Time.get_ticks_msec() - t0 < 10000:
		tls.poll()
		var st := tls.get_status()
		if st == StreamPeerTLS.STATUS_CONNECTED:
			if not sent:
				tls.put_data((JSON.stringify(req) + "\n").to_utf8_buffer())
				sent = true
			if tls.get_available_bytes() > 0:
				buf.append_array(tls.get_data(tls.get_available_bytes())[1])
				if buf.find(10) >= 0:
					break
		elif st != StreamPeerTLS.STATUS_HANDSHAKING:
			break
		await get_tree().process_frame
	tls.disconnect_from_stream()
	var reply = JSON.parse_string(buf.get_string_from_utf8().get_slice("\n", 0)) if buf.find(10) >= 0 else null
	return reply if reply is Dictionary else {"ok": false, "error": "no answer from the server"}

func sign_in(host_addr: String, port: int, email: String, reply: Dictionary) -> void:
	account = {"host": host_addr, "port": port, "email": email, "session": reply["session"], "profile": reply["profile"]}
	profile = (reply["profile"] as Dictionary).duplicate(true)

func sign_out() -> void:
	account = {}
	profile = {"pilot_name": "Pilot", "wins": 0, "losses": 0, "elo": 1000, "xp": 0, "level": 1, "coins": 0, "skills": {}}
	_load_profile()

func host(port: int = 8910) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("Game.host: create_server failed (port %d): %d" % [port, err])
		mp_join_failed.emit()
		return
	_clear_mp_session()
	multiplayer.multiplayer_peer = peer
	_session_start()

func join(ip: String, port: int = 8910) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("Game.join: create_client failed (%s:%d): %d" % [ip, port, err])
		mp_join_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	_session_start()

func disconnect_mp() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_mp_session()
	_session_stop()

# B44: called wherever an MP session starts or ends. No stale lobby peers (a new
# host must start fresh) and no stale roster (Arena._ready treats a non-empty
# roster as "this is an MP match", so a later SP match would spawn as MP).
func _clear_mp_session() -> void:
	mp_lobby["peers"].clear()
	mp_active_match["roster"] = []

# T167 (B59) / T214 (B90): ENet's peer timeout is only the backstop. A dead peer is
# noticed by silence at the game level -- the server takes a client's mech after 5 s
# without input (Arena.INPUT_SILENCE_MS), a client leaves after HOST_SILENCE_MS without a
# snapshot (Arena) -- so the cap can be generous. It must be: ENet drops a peer once one
# reliable packet has gone unacknowledged for the cap, and its retry wait starts at
# rtt + 4 x rtt variance and doubles. Measured on `bad` (80 +- 30 ms, 5% loss, reorder):
# rtt 190-300 ms, variance up to 186 ms -> first wait ~1 s, so 12 s fitted only 4 tries
# (0, 1, 3, 7 s): 4 losses in a row of one packet or its ack (~1e-4) dropped live
# players (B90). 45 s fits 6 tries (0, 1, 3, 7, 15, 31 s): ~1e-6.
const PEER_TIMEOUT_MS := 45000

func _on_mp_peer_connected(id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and (multiplayer.is_server() or id == 1):  # other clients are relayed, not ENet peers here
		enet.get_peer(id).set_timeout(32, 5000, PEER_TIMEOUT_MS)
		# T200 (B78): ENet's packet throttle drops UNRELIABLE sends on a counter cycle once
		# it sees jittery RTTs, and recovers slowly while traffic is light: after an idle
		# lobby on a jittery link the 20 Hz snapshots went out in bursts (client mechs stood
		# still ~200 ms at a time). Deceleration 0 keeps it at its full-rate start value.
		# ponytail: no back-off of unreliable traffic on a truly congested link (~2 KB/s of
		# snapshots); set a bandwidth limit on the ENet host if that ever matters.
		enet.get_peer(id).throttle_configure(5000, 2, 0)
	if multiplayer.is_server() and not mp_active_match["roster"].is_empty():
		# T206: a late joiner (its Arena was built during auth): spectator, or its old slot
		var arena := get_tree().current_scene
		if arena == null or not arena.has_method("late_join_connected"):
			multiplayer.multiplayer_peer.disconnect_peer(id)  # mid scene change: try again
			return
		mp_lobby["peers"][id] = {"pilot_name": "Peer %d" % id, "elo": 1000, "level": 1, "squad": [], "ready": false}
		arena.late_join_connected(id, _late_tokens.get(id, ""))
		_rpc_request_meta.rpc_id(id)
		return
	mp_peer_connected.emit(id)
	# Lobby._on_peer_connected runs synchronously above, populating mp_lobby["peers"][id].
	# Now request real profile meta so the placeholder is replaced promptly.
	if multiplayer.is_server():
		_rpc_request_meta.rpc_id(id)

## T168: why the host refused us; read (and cleared) by MPEntry.
var mp_refused_reason := ""
## T176: FIND MATCH -> HOST (0) or JOIN (1) opens MPEntry on that tab.
var mp_entry_tab := 0

## T170 (B64): join handshake. A mid-match joiner used to be kicked after it had
## connected: SceneMultiplayer kept it in the connected set until the disconnect landed,
## so every broadcast to the half-closed peer logged 'Unable to send packet' (a flood on
## a lossy link). Now the host answers during SceneMultiplayer auth -- AUTH_OK + complete,
## or the refusal text and never complete -- and a refused peer is never "connected".
const AUTH_OK := "ok"
## Both sides must complete within this; generous for the `bad` net profile. A refused
## joiner leaves on its own as soon as the reason arrives; this only reaps silent ones.
const AUTH_TIMEOUT_S := 15.0

## T206: the joiner opens with its player token; the server answers AUTH_OK in the lobby,
## or, mid-match, with the whole live match (Arena.late_state, var_to_bytes). The joiner
## builds its Arena from that while still unconnected -- no broadcast can reach a node it
## doesn't have yet (B64's flood; T170 refused mid-match joins for that) -- then says
## "ready"; the server answers "go" and completes, the client completes on "go". The
## client must complete LAST: whoever completes last becomes connected first, and a
## server that is connected first streams (unreliable, another channel) into a client
## still authenticating -> engine error per packet (B89). A token that matches a player dropped < Arena.HOLD_S ago
## takes that slot back (Arena.late_state "rejoin_old").
const AUTH_READY := "ready"
const AUTH_GO := "go"
var late_join = null  # client: the late-join state until Arena applies it
## B101 (T245): the server has streamed to us since we joined -- proof it finished our auth.
## Whoever completes auth last is connected first (B89 makes that the client), so until a
## snapshot arrives our packets could reach a server still authenticating us (engine error
## per packet). Mech holds its input stream until then.
var server_heard := false
var _late_tokens: Dictionary = {}  # server: joining peer id -> token
var _peer_sessions: Dictionary = {}  # server: peer id -> account session token (T207)

func _on_mp_peer_authenticating(id: int) -> void:
	if multiplayer.is_server():
		return  # wait for the joiner's token (_on_mp_auth)
	server_heard = false  # B101
	var hello := "token:" + player_token()
	if not account.is_empty():
		hello += "|" + String(account["session"])  # T207: tie this peer to the account
	(multiplayer as SceneMultiplayer).send_auth(id, hello.to_utf8_buffer())

func _on_mp_auth(id: int, data: PackedByteArray) -> void:
	var smp := multiplayer as SceneMultiplayer
	if multiplayer.is_server():  # V41: client bytes are only ever read as text
		var msg := data.get_string_from_utf8()
		if msg.begins_with("token:"):
			var token := msg.substr(6).get_slice("|", 0).left(64)
			_late_tokens[id] = token
			_peer_sessions[id] = msg.substr(6).get_slice("|", 1).left(64)  # T207 ("" = guest)
			var arena := get_tree().current_scene
			if mp_active_match["roster"].is_empty() or arena == null or not arena.has_method("late_state"):
				smp.send_auth(id, AUTH_OK.to_utf8_buffer())
				smp.complete_auth(id)
				return
			var st: Dictionary = arena.late_state(token)
			st["you"] = id
			smp.send_auth(id, var_to_bytes(st))
		elif msg == AUTH_READY:
			smp.send_auth(id, AUTH_GO.to_utf8_buffer())
			smp.complete_auth(id)
		return
	var text := data.get_string_from_utf8()
	if text == AUTH_OK or text == AUTH_GO:
		smp.complete_auth(id)
		return
	var st = bytes_to_var(data)  # from the server: trusted
	if st is Dictionary and st.has("mechs"):
		late_join = st
		mp_active_match = {"map_path": st["map_path"], "roster": st["roster"], "match_seed": st["match_seed"]}
		var md = ResourceLoader.load(st["map_path"])
		if md != null:
			loadout["map_def"] = md
		get_tree().change_scene_to_file.call_deferred("res://scenes/arena/Arena.tscn")
		return
	mp_refused_reason = text
	_leave_server.call_deferred()  # not from inside the multiplayer poll

## Client: the late-join Arena is built -- finish the handshake (T206).
func late_join_ready() -> void:
	late_join = null
	(multiplayer as SceneMultiplayer).send_auth(1, AUTH_READY.to_utf8_buffer())  # completes on "go"

## T206: per-install id, so a reconnect is recognised (the ENet id changes). Lives in its
## own [net] section: a saved pilot_name is what makes a profile (T192), not this.
func player_token() -> String:
	if profile.get("token", "") == "":
		var cfg := ConfigFile.new()
		cfg.load(_SAVE_PATH)
		var t: String = cfg.get_value("net", "token", "")
		if t == "":
			t = "%08x%08x%08x%08x" % [randi(), randi(), randi(), randi()]
			cfg.set_value("net", "token", t)
			cfg.save(_SAVE_PATH)
		profile["token"] = t
	return profile["token"]

# Server -> client: asks client to send its profile metadata (V36).
@rpc("authority", "call_remote", "reliable")
func _rpc_request_meta() -> void:
	var meta := {
		"pilot_name": profile.get("pilot_name", "Pilot"),
		"elo":        profile.get("elo", 1000),
		"level":      profile.get("level", 1),
	}
	_rpc_send_meta.rpc_id(1, meta)

# Client -> server: delivers profile metadata (V36, V41).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_meta(meta: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	# V41: sender must be a known lobby peer
	if not mp_lobby["peers"].has(sender):
		push_error("_rpc_send_meta: unknown sender %d" % sender)
		return
	var entry: Dictionary = mp_lobby["peers"][sender]
	entry["token"] = _late_tokens.get(sender, "")  # T206: the auth token, not a claim in meta
	var email: String = account_server.email_for(_peer_sessions.get(sender, "")) if account_server != null else ""
	if email != "":  # T207: a signed-in player's name / ELO / level come from its account
		entry["account"] = email
		meta = account_server.profile(email)
	entry["pilot_name"] = str(meta.get("pilot_name", "Pilot"))
	entry["elo"]        = int(meta.get("elo", 1000))
	entry["level"]      = int(meta.get("level", 1))
	broadcast_lobby()

func _on_mp_peer_disconnected(id: int) -> void:
	mp_peer_disconnected.emit(id)
	if not multiplayer.is_server():
		return
	# Case (a): if in lobby (no active match roster), remove peer and rebroadcast.
	if mp_active_match["roster"].is_empty() and mp_lobby["peers"].has(id):
		mp_lobby["peers"].erase(id)
		broadcast_lobby()

func _on_mp_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_mp_session()
	_session_stop()
	mp_join_failed.emit()

func _on_mp_server_disconnected() -> void:
	_leave_server()

## Host lost (server_disconnected) or refused us (T170 auth): tear the peer down, then
## the title, or the join screen when there is a reason to show.
func _leave_server() -> void:
	var mp := multiplayer.multiplayer_peer
	if mp != null and mp.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		mp.close()  # refused (still mid-handshake); a lost host's peer is already down
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_mp_session()
	_session_stop()
	mp_server_lost.emit()
	# T153 (V40 exception): host gone -> back to the title, not an offline zombie Arena/Lobby
	# T168: refused join -> the join screen, which shows the reason
	var to := "res://scenes/ui/MPEntry.tscn" if mp_refused_reason != "" else "res://scenes/ui/TitleScreen.tscn"
	get_tree().change_scene_to_file.call_deferred(to)

## T192: a callsign saved on this machine = signed in (TitleScreen skips the guest path).
## The file also holds the loadout, so the pilot_name key is the test, not the file.
var has_profile := false

func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return
	has_profile = cfg.has_section_key("profile", "pilot_name")
	profile["pilot_name"]  = cfg.get_value("profile", "pilot_name",  profile["pilot_name"])
	profile["wins"]        = cfg.get_value("profile", "wins",        0)
	profile["losses"]      = cfg.get_value("profile", "losses",      0)
	profile["elo"]         = cfg.get_value("profile", "elo",         1000)
	profile["xp"]          = cfg.get_value("profile", "xp",         0)
	profile["level"]       = cfg.get_value("profile", "level",       1)
	profile["coins"]       = cfg.get_value("profile", "coins",       0)
	profile["skills"] = cfg.get_value("profile", "skills", {})

func save_profile() -> void:
	if not account.is_empty():
		return  # T207: an account's profile lives on its server
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)
	cfg.set_value("profile", "pilot_name",  profile.get("pilot_name",  "Pilot"))
	cfg.set_value("profile", "wins",        profile.get("wins",        0))
	cfg.set_value("profile", "losses",      profile.get("losses",      0))
	cfg.set_value("profile", "elo",         profile.get("elo",         1000))
	cfg.set_value("profile", "xp",          profile.get("xp",         0))
	cfg.set_value("profile", "level",       profile.get("level",       1))
	cfg.set_value("profile", "coins",       profile.get("coins",       0))
	cfg.set_value("profile", "skills",      profile.get("skills", {}))
	cfg.save(_SAVE_PATH)
	has_profile = true

# ---- ELO / XP / match helpers ----

func get_bot_elo() -> int:
	var diff: int = clampi(settings.get("bot_difficulty", 1), 0, 4)
	return _BOT_ELO_BY_DIFFICULTY[diff]

func apply_coin_pickup_bonus(base: int) -> int:
	return roundi(float(base) * (1.0 + get_skill_effect("coin_pickup")))

func _check_level_up() -> void:
	var cur_level: int = profile.get("level", 1)
	var cur_xp: int    = profile.get("xp", 0)
	# cur_level - 1 is the index into _LEVEL_THRESHOLDS (0-based)
	while cur_level - 1 < _LEVEL_THRESHOLDS.size() and cur_xp >= _LEVEL_THRESHOLDS[cur_level - 1]:
		cur_level += 1
	profile["level"] = cur_level

## XP remaining until the next level (0 if max level).
func xp_to_next_level() -> int:
	var lv: int = profile.get("level", 1)
	if lv - 1 >= _LEVEL_THRESHOLDS.size():
		return 0
	return _LEVEL_THRESHOLDS[lv - 1] - profile.get("xp", 0)

# ---- Skill tree helpers ----

func skill_level(key: String) -> int:
	return int(profile.get("skills", {}).get(key, 0))

func skill_points_available() -> int:
	return maxi(0, profile.get("level", 1) - profile.get("skills", {}).size())

func _parents_unlocked(key: String) -> bool:
	var def: Dictionary = SKILL_TREE.get(key, {})
	var parents: Array = def.get("parents", [])
	if parents.is_empty():
		return true
	var skills: Dictionary = profile.get("skills", {})
	if def.get("any_parent", false):
		for p: String in parents:
			if skills.has(p):
				return true
		return false
	for p: String in parents:
		if not skills.has(p):
			return false
	return true

func can_unlock(key: String) -> bool:
	if not SKILL_TREE.has(key):
		return false
	if profile.get("skills", {}).has(key):
		return false
	return skill_points_available() > 0 and _parents_unlocked(key)

func can_upgrade(key: String) -> bool:
	var lv: int = skill_level(key)
	if lv <= 0 or lv >= 12:
		return false
	return profile.get("coins", 0) >= _SKILL_FIB_COSTS[lv - 1]

# T213: signed in, a skill changes on the account's server (account_skill); these are
# the local (guest) path.
func unlock_skill(key: String) -> bool:
	if not account.is_empty() or not _skill_apply("unlock_skill", key):
		return false
	save_profile()
	return true

func upgrade_skill(key: String) -> bool:
	if not account.is_empty() or not _skill_apply("upgrade_skill", key):
		return false
	save_profile()
	return true

# The rules-checked change to `profile` (no save): local skills and, borrowed, accounts.
func _skill_apply(op: String, key: String) -> bool:
	if op == "unlock_skill":
		if not can_unlock(key):
			return false
		var skills: Dictionary = profile.get("skills", {})
		skills[key] = 1
		profile["skills"] = skills
		return true
	if op == "upgrade_skill":
		if not can_upgrade(key):
			return false
		var lv: int = skill_level(key)
		profile["coins"] = profile.get("coins", 0) - _SKILL_FIB_COSTS[lv - 1]
		var skills: Dictionary = profile.get("skills", {})
		skills[key] = lv + 1
		profile["skills"] = skills
		return true
	return false

## Server (AccountServer, main thread): the same rules on an account's profile; {} = refused.
func skill_op_on(prof: Dictionary, op: String, key: String) -> Dictionary:
	var keep := profile
	profile = prof.duplicate(true)
	var ok := _skill_apply(op, key)
	var out := profile
	profile = keep
	return out if ok else {}

## Client, signed in: ask the account's server; true + profile updated when it agreed.
func account_skill(op: String, key: String) -> bool:
	var reply: Dictionary = await account_request(account["host"], account["port"],
		{"op": op, "session": account["session"], "key": key})
	if not reply.get("ok", false) or account.is_empty():
		return false
	account["profile"] = reply["profile"]
	profile = (reply["profile"] as Dictionary).duplicate(true)
	return true

func get_skill_effect(key: String) -> float:
	var def: Dictionary = SKILL_TREE.get(key, {})
	return float(skill_level(key)) * float(def.get("per_level", 0.0))

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return
	settings["mouse_sensitivity"] = cfg.get_value("settings", "mouse_sensitivity", settings["mouse_sensitivity"])
	settings["bot_difficulty"]    = cfg.get_value("settings", "bot_difficulty",    settings["bot_difficulty"])
	settings["master_volume"]     = cfg.get_value("settings", "master_volume",     settings["master_volume"])
	settings["shadows"]           = cfg.get_value("settings", "shadows",           settings["shadows"])
	apply_volume(settings["master_volume"])

func _load_loadout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return
	var mech_path: String = cfg.get_value("loadout", "mech_path", "")
	if mech_path != "":
		var md = load(mech_path)
		if md != null:
			loadout["mech_def"] = md
	loadout["mech_weapon_choices"] = _migrate_weapons(cfg.get_value("loadout", "mech_weapon_choices", {}))
	var bot_path: String = cfg.get_value("loadout", "bot_path", "")
	if bot_path != "":
		var bd = load(bot_path)
		if bd != null:
			loadout["bot_def"] = bd
	loadout["team_size"] = cfg.get_value("loadout", "team_size", 1)
	loadout["sp_bots"] = cfg.get_value("loadout", "sp_bots", [])  # T251: [ally, enemy]; [] = fill to team_size
	var squad_paths: Array = cfg.get_value("loadout", "squad", [])
	loadout["squad"] = squad_paths
	loadout["presets"] = _migrate_weapons(cfg.get_value("loadout", "presets", {}))
	var map_path: String = cfg.get_value("loadout", "map_path", "")
	if map_path != "" and ResourceLoader.exists(map_path):  # T248: a saved map that was deleted (Ironworks) -> default
		var mpd = load(map_path)
		if mpd != null:
			loadout["map_def"] = mpd

# T194: the heavy rocket launcher was cut (rockets are light-only; AERIAL HV is the heavy
# pick). Saved choices and presets from before load with the replacement.
const _CUT_WEAPONS := {"res://scenes/weapons/RocketLauncherHeavy.tscn": "res://scenes/weapons/AerialStrikeHeavy.tscn"}

static func _migrate_weapons(v: Variant) -> Variant:
	if v is String:
		return _CUT_WEAPONS.get(v, v)
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _migrate_weapons(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _migrate_weapons(v[k])
		return out
	return v

func save_loadout() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)  # preserve existing sections
	var mech_def = loadout.get("mech_def")
	cfg.set_value("loadout", "mech_path", mech_def.resource_path if mech_def != null else "")
	cfg.set_value("loadout", "mech_weapon_choices", loadout.get("mech_weapon_choices", {}))
	var bot_def = loadout.get("bot_def")
	cfg.set_value("loadout", "bot_path", bot_def.resource_path if bot_def != null else "")
	cfg.set_value("loadout", "team_size", loadout.get("team_size", 1))
	cfg.set_value("loadout", "sp_bots", loadout.get("sp_bots") if loadout.get("sp_bots") is Array else [])  # T251 ([] = fill)
	cfg.set_value("loadout", "squad", loadout.get("squad", []))
	cfg.set_value("loadout", "presets", loadout.get("presets", {}))
	var map_def = loadout.get("map_def")
	cfg.set_value("loadout", "map_path", map_def.resource_path if map_def != null else "")
	cfg.save(_SAVE_PATH)

## T177: hangar squad presets -- the whole squad (5 mech paths) plus the weapon choices
## of the mechs in it, under a typed name. Same name = overwrite.
func save_preset(pname: String) -> void:
	var choices: Dictionary = loadout.get("mech_weapon_choices", {})
	var weapons := {}
	for path in loadout.get("squad", []):
		if choices.has(path):
			weapons[path] = (choices[path] as Array).duplicate()
	var presets: Dictionary = loadout.get("presets", {})
	presets[pname] = {"squad": (loadout.get("squad", []) as Array).duplicate(), "weapons": weapons}
	loadout["presets"] = presets
	save_loadout()

## Makes preset `pname` the current squad (its weapon choices win for its mechs). False if unknown.
func load_preset(pname: String) -> bool:
	var p: Dictionary = loadout.get("presets", {}).get(pname, {})
	if p.is_empty():
		return false
	loadout["squad"] = (p["squad"] as Array).duplicate()
	var choices: Dictionary = loadout.get("mech_weapon_choices", {})
	for path in p["weapons"]:
		choices[path] = (p["weapons"][path] as Array).duplicate()
	loadout["mech_weapon_choices"] = choices
	if not loadout["squad"].is_empty():
		var md = load(loadout["squad"][0])
		if md != null:
			loadout["mech_def"] = md
	save_loadout()
	return true

func delete_preset(pname: String) -> void:
	loadout.get("presets", {}).erase(pname)
	save_loadout()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value("settings", "mouse_sensitivity", settings.get("mouse_sensitivity", 0.003))
	cfg.set_value("settings", "bot_difficulty",    settings.get("bot_difficulty",    1))
	cfg.set_value("settings", "master_volume",     settings.get("master_volume",     0.5))
	cfg.set_value("settings", "shadows",           settings.get("shadows",           "blob"))
	cfg.save(_SETTINGS_PATH)

func apply_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(linear))

# ---- Multiplayer lobby state (V39) ----

signal lobby_updated

# Server-authoritative lobby state.  Clients receive a replicated copy via
# _rpc_sync_lobby.  All mutation from clients must go through an @rpc to server
# which then calls broadcast_lobby().
var mp_lobby: Dictionary = {
	"peers":      {},    # peer_id (int) -> {pilot_name, elo, level, squad, ready}
	"bot_fill":   true,
	"team_size":  1,
	"map_path":   "res://resources/maps/MathTemple.tres",
	"match_seed": 0,
}

@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby(data: Dictionary) -> void:
	mp_lobby = data
	lobby_updated.emit()

# V40: all coordinated scene transitions go through here (server-origin only).
# T159/V52: clients only (call_remote) -- they leave first and ack; the server
# changes after every ack (server_change_scene), so no client RPC is in flight to
# a scene the server already left.
@rpc("authority", "call_remote", "reliable")
func _rpc_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
	_rpc_transition_ack.rpc_id(1)

# ---- Scene-transition handshake (T159, V52) ----
# Server-side: true only while every client has the match Arena loaded. The
# continuous unreliable streams (snapshots, beacon progress, scores) send only
# while live, so nothing streams into a scene a client hasn't loaded yet or has
# already left (Godot drops those packets and logs 'Node not found').
var mp_live: bool = false
var _await_acks: Array = []
var _await_then: Callable = Callable()
var _await_id: int = 0

# Server: run `then` once every connected client has acked (or after 5 s).
func server_await_clients(then: Callable) -> void:
	_await_id += 1
	var my_id := _await_id
	_await_acks = Array(multiplayer.get_peers())
	_await_then = then
	if _await_acks.is_empty():
		_finish_await()
		return
	get_tree().create_timer(5.0, true).timeout.connect(func() -> void:
		if my_id == _await_id and _await_then.is_valid():
			push_warning("[Game] transition: no ack from %s after 5 s, continuing" % str(_await_acks))
			_finish_await())

func _finish_await() -> void:
	_await_id += 1
	_await_acks.clear()
	var then := _await_then
	_await_then = Callable()
	if then.is_valid():
		then.call()

# Client -> server: "I'm in the new scene" (Arena loaded, or left for the lobby).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_transition_ack() -> void:
	if not multiplayer.is_server():
		return
	_await_acks.erase(multiplayer.get_remote_sender_id())  # V41: unknown sender = no-op
	if _await_acks.is_empty() and _await_then.is_valid():
		_finish_await()

const STREAM_DRAIN_S := 0.3  # B61: > bad-profile jitter (±30 ms) + snapshot interval (50 ms), with margin

# Server: coordinated scene change (V40). Streams stop, clients leave and ack,
# then the server follows.
func server_change_scene(path: String) -> void:
	mp_live = false
	# B61: snapshots/scores ride unreliable ENet channels, the change rides a reliable one;
	# on a jittery link a snapshot sent just before can land after it, once the client's
	# Arena is gone ('Node not found: Arena'). Let in-flight streams drain first.
	await get_tree().create_timer(STREAM_DRAIN_S).timeout
	# B77: the other direction too -- a client's last unreliable input packets, sent just
	# before its (reliable) ack, can land after it; let them drain into the live Arena.
	server_await_clients(func() -> void:
		get_tree().create_timer(STREAM_DRAIN_S).timeout.connect(func() -> void:
			get_tree().change_scene_to_file(path)))
	_rpc_change_scene.rpc(path)

func broadcast_lobby() -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_lobby.rpc(mp_lobby)
	_dedicated_lobby_changed()  # T204: every lobby change (join, leave, ready, squad)

# ---- Squad RPC (T113) ----

# Infer slot_size from path naming convention: *Heavy* = 1, else 0 (V17).
func _weapon_size_from_path(path: String) -> int:
	return 1 if "Heavy" in path else 0

# V17: validate one squad entry dict {mech, weapons}.
func _validate_squad_entry(entry: Dictionary) -> bool:
	var mech_path: String = str(entry.get("mech", ""))
	if mech_path.is_empty() or not ResourceLoader.exists(mech_path):
		push_error("_validate_squad_entry: invalid mech path '%s'" % mech_path)
		return false
	var md = ResourceLoader.load(mech_path)
	if md == null:
		push_error("_validate_squad_entry: failed to load mech '%s'" % mech_path)
		return false
	var weapons: Array = entry.get("weapons", [])
	var slots: Array = md.weapon_slots if "weapon_slots" in md else []
	for i in mini(slots.size(), weapons.size()):
		var wpn_path: String = str(weapons[i])
		if wpn_path.is_empty():
			continue
		if not ResourceLoader.exists(wpn_path):
			push_error("_validate_squad_entry: invalid weapon '%s'" % wpn_path)
			return false
		var slot = slots[i]
		var required: int = slot.slot_size if "slot_size" in slot else 0
		if _weapon_size_from_path(wpn_path) != required:
			push_error("V17: weapon '%s' wrong size for slot %d (need %d)" % [wpn_path, i, required])
			return false
	return true

# Validate + store squad for a peer, then broadcast. Called directly on server,
# or via _rpc_set_squad on clients.
func _apply_squad(peer_id: int, squad: Array) -> void:
	if not mp_lobby["peers"].has(peer_id):
		push_error("_apply_squad: unknown peer %d" % peer_id)
		return
	if squad.size() != 5:
		push_error("_apply_squad: expected 5 entries, got %d" % squad.size())
		return
	for entry in squad:
		if not _validate_squad_entry(entry):
			return
	mp_lobby["peers"][peer_id]["squad"] = squad
	broadcast_lobby()

# Client -> server: send squad selection (V39, V41).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_squad(squad: Array) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_apply_squad(sender, squad)

# ---- Match lifecycle (T115) ----

# Set by _rpc_match_start; read by Arena._ready in T116.
var mp_active_match: Dictionary = {
	"map_path":   "",
	"roster":     [],   # Array[{slot_idx, peer_id, team, squad, bot_id}]
	"match_seed": 0,
}

## T184: single player = a local MP match: the hangar squad as peer 1 plus bot fill,
## through the same roster / Arena / match-end path as MP, on the OfflineMultiplayerPeer
## (no socket: a web build can't host ENet; V56). Fills mp_lobby + mp_active_match only;
## start_sp_match() also loads the Arena. Tools/probes call this and edit the roster.
func setup_sp_match() -> void:
	var lobby := load("res://scripts/Lobby.gd")
	var md: Resource = loadout.get("map_def")
	var map_path: String = md.resource_path if md != null else "res://resources/maps/MathTemple.tres"
	mp_lobby = {"peers": {1: lobby._local_peer_meta()}, "bot_fill": true,
		"team_size": loadout.get("team_size", 1), "map_path": map_path, "match_seed": 0}
	if loadout.get("sp_bots") is Array and (loadout["sp_bots"] as Array).size() == 2:  # T251: the SP picker's exact ally / enemy counts
		mp_lobby["bot_counts"] = loadout["sp_bots"]
	mp_active_match = {"map_path": map_path, "roster": lobby._build_roster(), "match_seed": 0}
	loadout["map_def"] = load(map_path)

func start_sp_match() -> void:
	setup_sp_match()
	get_tree().change_scene_to_file("res://scenes/arena/Arena.tscn")

# Server broadcasts this; all peers store match data and change scene (V40).
@rpc("authority", "call_local", "reliable")
func _rpc_match_start(map_path: String, roster: Array, match_seed: int) -> void:
	if multiplayer.is_server():
		# T159: stream nothing until every client has loaded Arena (it acks from Arena._ready);
		# set up before any ack can arrive.
		mp_live = false
		server_await_clients(func() -> void: mp_live = true)
	_sync_next_match()
	mp_active_match = {
		"map_path":   map_path,
		"roster":     roster,
		"match_seed": match_seed,
	}
	# Keep SP loadout map_def in sync so Arena SP path still works.
	if map_path != "":
		var md = ResourceLoader.load(map_path)
		if md != null:
			loadout["map_def"] = md
	get_tree().change_scene_to_file("res://scenes/arena/Arena.tscn")

# ---- Ready toggle (T114) ----

func _apply_ready(peer_id: int, ready: bool) -> void:
	if not mp_lobby["peers"].has(peer_id):
		push_error("_apply_ready: unknown peer %d" % peer_id)
		return
	mp_lobby["peers"][peer_id]["ready"] = ready
	broadcast_lobby()

# Client -> server: toggle ready state (V39, V41).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_apply_ready(sender, ready)

# ---- Bot coordination (V5: absorbed from former AIDirector autoload) ----

var _bot_intents: Dictionary = {}  # bot Node -> {beacon: Node, team: int}

func ai_director_set_intent(bot: Node, beacon: Node, team: int) -> void:
	_bot_intents[bot] = {"beacon": beacon, "team": team}

func ai_director_clear_intent(bot: Node) -> void:
	_bot_intents.erase(bot)

# ---- Match-end lifecycle (T121) ----

signal match_ended_mp(winner_team: int, stats: Array)

var _mp_return_confirmations: Dictionary = {}
var _mp_return_deadline: float = 0.0

@rpc("authority", "call_local", "reliable")
func _rpc_match_end(winner_team: int, stats: Array) -> void:
	SoundManager.stop_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match_ended_mp.emit(winner_team, stats)
	_update_mp_profile(winner_team, stats)
	if multiplayer.is_server() and account_server != null:
		_update_account_profiles(winner_team, stats)

# T207: server -- each signed-in player's result goes to its account, then back to it.
func _update_account_profiles(winner_team: int, stats: Array) -> void:
	for entry in mp_active_match["roster"]:
		var pid: int = int(entry.get("peer_id", 0))
		var email: String = mp_lobby["peers"].get(pid, {}).get("account", "")
		if pid < 2 or email == "":
			continue
		var before: Dictionary = account_server.profile(email)
		var after := _apply_match_to(before, int(entry.get("team", -1)), winner_team, stats)
		account_server.save_profile(email, after)
		print("[Server] account %s: elo %d -> %d" % [email, int(before.get("elo", 0)), int(after.get("elo", 0))])
		_rpc_account_profile.rpc_id(pid, after)

signal account_profile_updated

@rpc("authority", "reliable")
func _rpc_account_profile(prof: Dictionary) -> void:
	if account.is_empty():
		return
	account["profile"] = prof
	profile = prof.duplicate(true)
	account_profile_updated.emit()

## Human opponents' pre-match ELOs for a player on `my_team`; bot ELO if none (V36).
## ponytail: bot fallback reads THIS peer's bot_difficulty, so the result table's
## guess for another peer's all-bot match can differ from what that peer applies.
func mp_opp_elos(my_team: int, stats: Array) -> Array:
	var roster: Array = mp_active_match["roster"]
	var opp_elos: Array = []
	for stat in stats:
		var sid: int = stat.get("peer_id", 0)
		if sid == 0:
			continue
		var their_team := -1
		for entry in roster:
			if entry.get("peer_id", 0) == sid:
				their_team = entry.get("team", -1)
				break
		if their_team != my_team and their_team != -1:
			var pe: int = stat.get("pre_elo", 0)
			if pe > 0:
				opp_elos.append(pe)
	if opp_elos.is_empty():
		opp_elos.append(get_bot_elo())
	return opp_elos

## ELO change: average K=32 delta across opponents, floor 100. Shared by the profile
## update and the MP result table (T168) so the shown change is the applied one.
func mp_elo_delta(my_elo: int, opp_elos: Array, won: bool) -> int:
	var result_val: float = 1.0 if won else 0.0
	var d: float = 0.0
	for opp_elo in opp_elos:
		var expected: float = 1.0 / (1.0 + pow(10.0, float(opp_elo - my_elo) / 400.0))
		d += float(_ELO_K) * (result_val - expected)
	return maxi(100, my_elo + roundi(d / float(opp_elos.size()))) - my_elo

# V36: each peer locally recomputes own ELO/XP/coins from broadcast match result.
func _update_mp_profile(winner_team: int, stats: Array) -> void:
	var my_peer_id := multiplayer.get_unique_id()
	var roster: Array = mp_active_match["roster"]
	# Find own team from roster.
	var my_team := -1
	for entry in roster:
		if entry.get("peer_id", 0) == my_peer_id:
			my_team = entry.get("team", -1)
			break
	if my_team == -1 or not account.is_empty():
		return  # T207: a signed-in player's result is applied on the server (_rpc_account_profile)
	_apply_match(my_team, winner_team, stats)
	save_profile()

# T207: the same result math on an account's profile (server side).
# ponytail: borrows `profile` for the call, so the skill/level helpers need no profile arg.
func _apply_match_to(prof: Dictionary, my_team: int, winner_team: int, stats: Array) -> Dictionary:
	var keep := profile
	profile = prof.duplicate(true)
	_apply_match(my_team, winner_team, stats)
	var out := profile
	profile = keep
	return out

func _apply_match(my_team: int, winner_team: int, stats: Array) -> void:
	var won: bool = winner_team == my_team
	var wl := "wins" if won else "losses"
	profile[wl] = profile.get(wl, 0) + 1
	var my_elo: int = profile.get("elo", 1000)
	var opp_elos := mp_opp_elos(my_team, stats)
	profile["elo"] = my_elo + mp_elo_delta(my_elo, opp_elos, won)
	# XP with avg opponent ELO.
	var avg_opp_elo: int = 0
	for e in opp_elos:
		avg_opp_elo += e
	avg_opp_elo /= opp_elos.size()
	var xp_gain: int
	if won:
		xp_gain = clampi(roundi(50.0 * float(avg_opp_elo) / float(maxi(1, my_elo))), 25, 200)
	else:
		xp_gain = clampi(roundi(15.0 * float(avg_opp_elo) / float(maxi(1, my_elo))), 5, 50)
	xp_gain = roundi(float(xp_gain) * (1.0 + get_skill_effect("xp_bonus")))
	profile["xp"] = profile.get("xp", 0) + xp_gain
	_check_level_up()
	# Coins.
	var base_coins: int = 75 if won else 20
	profile["coins"] = profile.get("coins", 0) + apply_coin_pickup_bonus(base_coins)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready_for_next() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not mp_lobby["peers"].has(sender):
		push_error("_rpc_ready_for_next: unknown sender %d" % sender)
		return
	_mp_return_confirmations[sender] = true
	_check_all_ready_for_next()

func _confirm_ready_for_next_local() -> void:
	_mp_return_confirmations[1] = true
	_check_all_ready_for_next()

func _check_all_ready_for_next() -> void:
	for peer_id in mp_lobby["peers"].keys():
		if not _mp_return_confirmations.has(peer_id):
			return
	_do_return_to_lobby()

func _do_return_to_lobby() -> void:
	_mp_return_confirmations.clear()
	_mp_return_deadline = 0.0
	set_process(false)
	for peer_id in mp_lobby["peers"].keys():
		mp_lobby["peers"][peer_id]["ready"] = false
	broadcast_lobby()
	server_change_scene("res://scenes/ui/Lobby.tscn")

func _process(_delta: float) -> void:
	if _mp_return_deadline > 0.0 and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if Time.get_ticks_msec() * 0.001 >= _mp_return_deadline:
			_do_return_to_lobby()

func ai_director_intent_count(beacon: Node, team: int) -> int:
	var count := 0
	var stale: Array = []
	for bot in _bot_intents:
		if not is_instance_valid(bot):
			stale.append(bot)
			continue
		var entry: Dictionary = _bot_intents[bot]
		if entry.get("beacon") == beacon and entry.get("team") == team:
			count += 1
	for bot in stale:
		_bot_intents.erase(bot)
	return count
