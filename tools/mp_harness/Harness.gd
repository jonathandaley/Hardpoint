extends Node
# M0.4: headless two-process loopback entry for the MP autodebug harness.
# Instantiated by Game._ready ONLY when --mp-scenario=<file> is present, so none
# of this touches the normal (UI) code path. It bypasses Title/SignIn/MPEntry/
# Lobby and drives the real match-start flow directly: host or join over loopback
# ENet, build a roster, reuse Game._rpc_match_start, then swap a ReplayInputSource
# onto the local player mech (mech.set_input_source) so the run is deterministic.
# Identical netcode path to a real LAN game.
#
# Scenario JSON (untyped, V14):
#   {
#     "seed": 1337,
#     "port": 8910,
#     "map_path": "res://resources/maps/MathTemple.tres",
#     "mech": "res://resources/mechs/Hippogriff.tres",
#     "duration_ticks": 600,
#     "peers": {
#       "server":   {"input": {...ReplayInputSource spec...}},
#       "client_1": {"input": {...}}
#     }
#   }
# role + scenario path come from cmdline (--role=, --mp-scenario=).

const ReplaySrc := preload("res://scripts/ReplayInputSource.gd")
const DEFAULT_MECH := "res://resources/mechs/Hippogriff.tres"

var _scenario: Dictionary = {}
var _role: String = "server"
var _port: int = 8910
var _expected_clients: int = 1
var _connected: Array = []
var _match_started: bool = false
var _override_done: bool = false
var _deadline_frame: int = -1

func _ready() -> void:
	var path := ""
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for a in args:
		if a.begins_with("--mp-scenario="):
			path = a.get_slice("=", 1)
		elif a.begins_with("--role="):
			_role = a.get_slice("=", 1)
	if path == "":
		push_error("[Harness] no --mp-scenario= given")
		get_tree().quit(1)
		return
	_scenario = _load_json(path)
	if _scenario.is_empty():
		push_error("[Harness] could not load scenario %s" % path)
		get_tree().quit(1)
		return
	_port = int(_scenario.get("port", 8910))
	var peers: Dictionary = _scenario.get("peers", {})
	_expected_clients = 0
	for k in peers:
		if k != "server":
			_expected_clients += 1
	print("[Harness] role=%s port=%d expected_clients=%d" % [_role, _port, _expected_clients])
	if _role == "server":
		_start_server()
	else:
		_start_client()

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}

func _start_server() -> void:
	Game.host(_port)
	if _expected_clients <= 0:
		_begin_match.call_deferred()
		return
	multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(id: int) -> void:
	if not _connected.has(id):
		_connected.append(id)
	print("[Harness] client connected: %d (%d/%d)" % [id, _connected.size(), _expected_clients])
	if _connected.size() >= _expected_clients and not _match_started:
		_begin_match()

func _begin_match() -> void:
	_match_started = true
	var roster := _build_roster()
	var seed := int(_scenario.get("seed", 0))
	var map_path: String = _scenario.get("map_path", "res://resources/maps/MathTemple.tres")
	print("[Harness] starting match: %d mechs, seed=%d" % [roster.size(), seed])
	# call_local: the server also receives this and loads Arena.
	Game._rpc_match_start.rpc(map_path, roster, seed)

func _build_roster() -> Array:
	var mech_path: String = _scenario.get("mech", DEFAULT_MECH)
	var roster: Array = []
	# Server is peer 1, team 0.
	roster.append(_roster_entry(0, 1, 0, mech_path))
	# Each client gets the next team, in connection order (sorted for determinism).
	var ids := _connected.duplicate()
	ids.sort()
	var slot := 1
	for cid in ids:
		roster.append(_roster_entry(slot, cid, 1, mech_path))
		slot += 1
	return roster

func _roster_entry(slot_idx: int, peer_id: int, team: int, mech_path: String) -> Dictionary:
	var squad: Array = []
	for _i in 5:
		squad.append({"mech": mech_path, "weapons": []})
	return {
		"slot_idx": slot_idx,
		"peer_id": peer_id,
		"team": team,
		"squad": squad,
		"bot_id": -1,
	}

func _start_client() -> void:
	Game.join("127.0.0.1", _port)
	# Arena loads automatically when the server's _rpc_match_start (call_local)
	# reaches us; _process polls for our local mech and then overrides input.

func _process(_delta: float) -> void:
	if not _override_done:
		_try_override_input()
		return
	if _deadline_frame >= 0 and Engine.get_physics_frames() >= _deadline_frame:
		print("[Harness] duration reached, quitting (%s)" % _role)
		Game.disconnect_mp()
		get_tree().quit(0)

# Once our local player mech exists (Arena spawned it), swap its input source
# for a ReplayInputSource driven by this role's scripted sequence.
func _try_override_input() -> void:
	var my_id := multiplayer.get_unique_id()
	var mine: Node = null
	for m in get_tree().get_nodes_in_group("mechs"):
		if int(m.get("owner_peer_id")) == my_id:
			mine = m
			break
	if mine == null:
		return
	var peers: Dictionary = _scenario.get("peers", {})
	var key := _role if _role == "server" else "client_1"
	var spec: Dictionary = peers.get(key, {}).get("input", {})
	var replay := ReplaySrc.new()
	replay.name = "ReplayInput"
	add_child(replay)
	replay.load_spec(spec)
	mine.set_input_source(replay)
	_override_done = true
	_deadline_frame = Engine.get_physics_frames() + int(_scenario.get("duration_ticks", 600))
	print("[Harness] input override done for %s (mech %s); deadline frame %d" % [_role, mine.name, _deadline_frame])
