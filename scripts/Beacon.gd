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

@onready var _cap_mesh: MeshInstance3D = $Visual/Cap
var _cap_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("beacons")
	# Surface override takes priority; fall back to mesh material; else create fresh.
	var existing: Material = _cap_mesh.get_surface_override_material(0)
	if existing == null:
		existing = _cap_mesh.mesh.surface_get_material(0)
	_cap_mat = (existing.duplicate() if existing != null else StandardMaterial3D.new()) as StandardMaterial3D
	_cap_mesh.set_surface_override_material(0, _cap_mat)
	$CaptureZone.body_entered.connect(_on_body_entered)
	$CaptureZone.body_exited.connect(_on_body_exited)
	_update_visuals()

func _process(delta: float) -> void:
	_update_capture(delta)

func _update_capture(delta: float) -> void:
	var teams := _teams_present()

	if teams.size() > 1:
		if state != State.CONTESTED:
			state = State.CONTESTED
			_update_visuals()
		return

	if teams.is_empty():
		if _capture_progress > 0.0 and _capturing_team != owner_team:
			_capture_progress = max(0.0, _capture_progress - delta / capture_time)
		return

	var team: int = teams[0]
	if team == owner_team:
		return

	if _capturing_team != team:
		_capturing_team = team
		_capture_progress = 0.0

	_capture_progress += delta / capture_time
	if _capture_progress >= 1.0:
		_capture_progress = 0.0
		owner_team = team
		state = State.TEAM_A if team == 0 else State.TEAM_B
		_update_visuals()
		captured.emit(team)

func _teams_present() -> Array:
	var out: Array = []
	for t in _capturers:
		if not _capturers[t].is_empty():
			out.append(t)
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
	match state:
		State.NEUTRAL:
			_cap_mat.albedo_color = Color(0.9, 0.9, 0.9)
		State.TEAM_A:
			_cap_mat.albedo_color = Color(0.2, 0.5, 1.0)
		State.TEAM_B:
			_cap_mat.albedo_color = Color(1.0, 0.3, 0.2)
		State.CONTESTED:
			_cap_mat.albedo_color = Color(1.0, 0.85, 0.0)
