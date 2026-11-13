extends Node
# T393 (T290 audit: Game.gd was ~1900 lines in 16 unrelated sections): Game's debug / test
# plumbing -- the T165 frame-time profiler, M0.2 sync snapshot logging and the T157 session
# recorder. Game.gd extends this script, so every name stays Game.<name> for its callers (probes,
# harness, Arena); nothing here may reach into Game's own members -- _records_sessions() is the
# one hook Game overrides.

## Game: whether a real (non-harness) MP session records to user://sessions (T389).
func _records_sessions() -> bool:
	return false

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
## T376: --fixed-bots=<Mech> (the suite passes it to every probe): regular bots fly that mech with
## rifles instead of T365's random squads, so a probe's result never hangs on the draw (a shield
## soaking its hits, a slow walker: B134 / B135). Probes that test the draw clear it.
var fixed_bots := ""
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
		elif a.begins_with("--fixed-bots="):
			fixed_bots = a.get_slice("=", 1)
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
# T389 (user 2026-11-12): a dedicated server always records; a player's game only with
# Settings > RECORD MATCHES on (off by default), and every recording keeps only the newest
# SESSIONS_KEEP matches of a session (T386's rule, which was servers only).
const SESSIONS_DIR := "user://sessions"
const SESSIONS_KEEP := 3
const SESSION_SHOT_TICKS := 600
var _recording: bool = false

func _session_start() -> void:
	if _sync_cli or not _records_sessions():
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
	# T386: a dedicated server is ONE session for as long as it runs (weeks), so the
	# per-session SESSIONS_KEEP never pruned it: ~5 MB a minute of play until the disk was
	# full. Keep the newest SESSIONS_KEEP matches (match 1's files sit in the root).
	# T389: a player's evening on one server is one long session too -> every recording.
	var old := _sync_match - SESSIONS_KEEP
	if _recording and old == 1:
		for f in DirAccess.get_files_at(_sync_root):
			DirAccess.remove_absolute(_sync_root.path_join(f))
	elif _recording and old > 1:
		_rm_tree(_sync_root.path_join("match%d" % old))

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
