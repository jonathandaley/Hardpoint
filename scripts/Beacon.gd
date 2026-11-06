class_name Beacon
extends Node3D
# States: neutral / team A / team B / contested.
# Mechs enter/exit the Area3D child; capture progress ticks until timer expires.

signal captured(new_team: int)

enum State { NEUTRAL, TEAM_A, TEAM_B, CONTESTED }

@export var capture_time: float = 3.0

var state: State = State.NEUTRAL
var owner_team: int = -1   # -1 neutral, 0 team A, 1 team B

var _capturers: Dictionary = {}   # team_id -> Array of bodies in zone
var _capturing_team: int = -1
var _capture_progress: float = 0.0
var _progress_broadcast_timer: float = 0.0
const _PROGRESS_BROADCAST_INTERVAL := 0.15
var _contested_hold_timer: float = 0.0

const BEAM_HEIGHT := 30.0
const CIRCLE_RADIUS := 6.0  # T314 (HUMAN_FOUND 2026-11-05: takeover ring "double in diameter"); = the CaptureZone radius
const RING_Y := 0.25  # T229: clears every map's beacon pads (probe beacon_ring)

@onready var _cap_mesh: MeshInstance3D = $Visual/Cap
var _cap_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _circle_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("beacons")
	var existing: Material = _cap_mesh.get_surface_override_material(0)
	if existing == null:
		existing = _cap_mesh.mesh.surface_get_material(0)
	_cap_mat = (existing.duplicate() if existing != null else StandardMaterial3D.new()) as StandardMaterial3D
	_cap_mesh.set_surface_override_material(0, _cap_mat)

	# Sky beam - tall emissive column rising from beacon
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.emission_enabled = true
	var beam_box := BoxMesh.new()
	beam_box.size = Vector3(0.25, BEAM_HEIGHT, 0.25)
	var beam_mi := MeshInstance3D.new()
	beam_mi.mesh = beam_box
	beam_mi.set_surface_override_material(0, _beam_mat)
	beam_mi.position = Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)
	$Visual.add_child(beam_mi)

	# Ground capture ring - emissive torus just above the ground. T229: RING_Y, not flush:
	# maps lay flat pads / slabs over the beacon floor (Sydney plazas 0.12 m, Giza's
	# causeway 0.18) and a flush ring was buried under them
	_circle_mat = StandardMaterial3D.new()
	_circle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_circle_mat.emission_enabled = true
	var circle_mesh := TorusMesh.new()
	circle_mesh.outer_radius = CIRCLE_RADIUS
	circle_mesh.inner_radius = CIRCLE_RADIUS - 0.18
	circle_mesh.rings = 32
	circle_mesh.ring_segments = 8
	var circle_mi := MeshInstance3D.new()
	circle_mi.mesh = circle_mesh
	circle_mi.set_surface_override_material(0, _circle_mat)
	circle_mi.position = Vector3(0.0, RING_Y, 0.0)
	$Visual.add_child(circle_mi)

	$CaptureZone.body_entered.connect(_on_body_entered)
	$CaptureZone.body_exited.connect(_on_body_exited)
	_update_visuals()

func _process(delta: float) -> void:
	# T40: capture logic runs server-only; clients receive state via _sync_state RPC.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_update_capture(delta)

func _player_team_in_zone() -> int:
	for t in _capturers:
		for body in _capturers[t]:
			if not is_instance_valid(body):
				continue
			var src: Node = body.get("_input_source")
			if src != null and src.has_method("is_human_input") and src.is_human_input():
				return int(t)
	return -1

func _update_capture(delta: float) -> void:
	for t in _capturers:
		_capturers[t] = _capturers[t].filter(func(b): return is_instance_valid(b))
	var teams := _teams_present()

	if teams.size() > 1:
		var player_t: int = _player_team_in_zone()
		var hold: float = Game.get_skill_effect("contested_hold") if player_t >= 0 else 0.0
		if hold > 0.0:
			if _contested_hold_timer == 0.0:
				_contested_hold_timer = hold
			_contested_hold_timer -= delta
			if _contested_hold_timer > 0.0:
				return
			_contested_hold_timer = 0.0
		_set_state(State.CONTESTED)
		return

	_contested_hold_timer = 0.0
	# B116: a contest used to stick until the next capture (T297 "stays contested
	# indefinitely"): with one team or none left the beacon shows its owner again.
	if state == State.CONTESTED:
		_set_state(_owner_state())

	if teams.is_empty():
		if _capture_progress > 0.0 and _capturing_team != owner_team:
			_capture_progress = max(0.0, _capture_progress - delta / capture_time)
			_stream_progress(delta, _capture_progress <= 0.0)  # B116: clients saw the decay never
		return

	var team: int = teams[0]
	if team == owner_team:
		return

	if _capturing_team != team:
		_capturing_team = team
		_capture_progress = 0.0

	var cap_delta: float = delta
	if _player_team_in_zone() == team:
		cap_delta *= 1.0 + Game.get_skill_effect("beacon_capture")
	# B87: clamp -- the capturing tick overshot (1.002) and the stream sent that before the reset
	_capture_progress = minf(_capture_progress + cap_delta / capture_time, 1.0)
	_stream_progress(delta, false)
	if _capture_progress >= 1.0:
		_capture_progress = 0.0
		owner_team = team
		captured.emit(team)
		Game.sync_log_event("captured", name, {"team": team})  # M1.3 autodebug event stream
		_set_state(_owner_state(), true)

func _owner_state() -> State:
	if owner_team < 0:
		return State.NEUTRAL
	return State.TEAM_A if owner_team == 0 else State.TEAM_B

# B116: every state change goes through here, so clients hear about all of them -- contest
# start / end weren't sent at all (the client never saw CONTESTED; T314's bigger zones made
# brushes with them common: beacon_capture / outage_recovery desync).
func _set_state(new_state: State, force := false) -> void:
	if new_state == state and not force:
		return
	state = new_state
	_update_visuals()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and Game.mp_live:  # V52; late joiners get it in the join snapshot
		_sync_state.rpc(owner_team, state, _capture_progress)

# T105 progress stream (rate-limited); `now` forces a send (e.g. the decay reaching 0).
func _stream_progress(delta: float, now: bool) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	_progress_broadcast_timer -= delta
	if (now or _progress_broadcast_timer <= 0.0) and Game.mp_live:  # T159/V52 stream gate
		_progress_broadcast_timer = _PROGRESS_BROADCAST_INTERVAL
		_sync_progress.rpc(_capture_progress, _capturing_team)

func _teams_present() -> Array:
	var out: Array = []
	for t in _capturers:
		for body in _capturers[t]:
			if is_instance_valid(body) and not body.get("is_dead"):
				out.append(t)
				break
	return out

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("mechs"):
		return
	var t: int = body.get("team") if body.get("team") != null else 0
	if not _capturers.has(t):
		_capturers[t] = []
	if body not in _capturers[t]:
		_capturers[t].append(body)

func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("mechs"):
		return
	var t: int = body.get("team") if body.get("team") != null else 0
	if _capturers.has(t):
		_capturers[t].erase(body)

func _update_visuals() -> void:
	var col: Color
	match state:
		State.NEUTRAL:
			col = Color(0.55, 0.55, 0.55)
		State.TEAM_A:
			col = Color(0.2, 0.5, 1.0)
		State.TEAM_B:
			col = Color(1.0, 0.3, 0.2)
		State.CONTESTED:
			col = Color(1.0, 0.85, 0.0)
	_cap_mat.albedo_color = col
	if _beam_mat != null:
		_beam_mat.albedo_color = col
		_beam_mat.emission = col
		_beam_mat.emission_energy_multiplier = 1.5
	if _circle_mat != null:
		_circle_mat.albedo_color = col
		_circle_mat.emission = col
		_circle_mat.emission_energy_multiplier = 1.2

# T105: periodic progress sync so clients see capture bar move in real-time (V33).
@rpc("authority", "unreliable_ordered")
func _sync_progress(progress: float, capturing_team: int) -> void:
	if multiplayer.is_server():
		return
	_capture_progress = progress
	_capturing_team = capturing_team

# T40: server broadcasts capture state to all clients after each ownership change.
# Clients apply visuals only; _update_capture never runs on clients.
@rpc("authority", "reliable")
func _sync_state(new_owner: int, new_state: int, new_progress: float) -> void:
	owner_team = new_owner
	state = new_state as State
	_capture_progress = new_progress
	_update_visuals()
