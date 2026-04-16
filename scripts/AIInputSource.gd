class_name AIInputSource
extends "res://scripts/InputSource.gd"

const TURN_SPEED    := 1.8   # rad/s
const ENGAGE_DIST   := 35.0  # close enough to shoot
const RETREAT_DIST  := 8.0   # too close — back off
const AIM_THRESHOLD := 0.25  # fire when within this many radians of target
const AIM_SPREAD    := 0.055 # max random jitter added to aim (radians)
const BURST_FIRE    := 1.6   # seconds of continuous fire per burst
const BURST_PAUSE   := 0.85  # seconds of pause between bursts
const STUCK_CHECK   := 0.5   # seconds between stuck checks
const STUCK_DIST    := 0.5   # minimum movement to not be considered stuck (m)
const ESCAPE_TIME   := 0.8   # seconds to strafe sideways when stuck

var _target: Node3D = null
var _beacons: Array = []
var _look_delta: Vector2 = Vector2.ZERO
var _move_dir: Vector2 = Vector2.ZERO
var _firing: bool = false
var _strafe_timer: float = 0.0
var _strafe_sign: float = 1.0
var _burst_timer: float = BURST_FIRE
var _in_burst: bool = true
var _jitter: Vector2 = Vector2.ZERO
var _jitter_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _stuck_timer: float = STUCK_CHECK
var _escape_timer: float = 0.0
var _escape_dir: float = 1.0

func _ready() -> void:
	call_deferred("_find_targets")

func _find_targets() -> void:
	for mech in get_tree().get_nodes_in_group("mechs"):
		if mech.get("team") == 0:
			_target = mech
			break
	_beacons = get_tree().get_nodes_in_group("beacons")

func _pick_target_beacon(bot_mech: Node3D) -> Node:
	var best: Node = null
	var best_score := -INF
	for b in _beacons:
		if not is_instance_valid(b):
			continue
		var owner: int = b.get("owner_team") if b.get("owner_team") != null else -1
		if owner == 1:   # already ours — skip
			continue
		var priority: float = 10.0 if owner == -1 else 5.0   # neutral > enemy
		var dist: float = bot_mech.global_position.distance_to(b.global_position)
		var score: float = priority - dist * 0.05
		if score > best_score:
			best_score = score
			best = b
	return best

func _process(delta: float) -> void:
	var bot_mech: Node3D = get_parent().get("pawn")
	if bot_mech == null or _target == null or not is_instance_valid(_target) \
			or not _target.visible:
		_look_delta = Vector2.ZERO
		_move_dir   = Vector2.ZERO
		_firing     = false
		return

	var to_target := _target.global_position - bot_mech.global_position
	var dist      := to_target.length()
	var sens: float = Game.settings.get("mouse_sensitivity", 0.003)

	# Horizontal aim — rotate torso toward player
	var to_flat := Vector3(to_target.x, 0.0, to_target.z)
	var h_dist  := to_flat.length()
	var angle_h := 0.0
	if h_dist > 0.01:
		to_flat = to_flat / h_dist
		angle_h = (-bot_mech.get_aim_basis().z).signed_angle_to(to_flat, Vector3.UP)
	var turn_h: float = clamp(angle_h, -TURN_SPEED * delta, TURN_SPEED * delta)
	_look_delta.x = -turn_h / sens

	# Vertical aim — compute angle from the camera's actual position to target centre
	var cam_arm := bot_mech.get_node_or_null("Torso/CameraArm") as SpringArm3D
	var cam     := bot_mech.get_node_or_null("Torso/CameraArm/Camera3D") as Camera3D
	if cam_arm and cam:
		var target_centre := _target.global_position + Vector3(0, 1.0, 0)
		var cam_to_target := target_centre - cam.global_position
		var cam_h_dist: float = Vector2(cam_to_target.x, cam_to_target.z).length()
		var desired_pitch: float = atan2(cam_to_target.y, maxf(cam_h_dist, 0.01))
		var pitch_diff: float    = desired_pitch - cam_arm.rotation.x
		var turn_v: float        = clamp(pitch_diff, -TURN_SPEED * delta, TURN_SPEED * delta)
		_look_delta.y = -turn_v / sens

	# Movement — retreat takes priority over everything else
	if dist < RETREAT_DIST:
		_move_dir = Vector2(0.0, 1.0)
	else:
		# Navigate to uncaptured beacon when one exists, else fight
		var beacon := _pick_target_beacon(bot_mech)
		if beacon != null:
			var to_beacon: Vector3 = beacon.global_position - bot_mech.global_position
			to_beacon.y = 0.0
			var beacon_dist: float = to_beacon.length()
			if beacon_dist > 3.0:
				# Walk toward beacon in torso-local space (matches _handle_movement)
				var aim_basis: Basis = bot_mech.call("get_aim_basis")
				var fwd: Vector3   = -aim_basis.z
				var right: Vector3 = aim_basis.x
				to_beacon = to_beacon / beacon_dist
				_move_dir = Vector2(to_beacon.dot(right), -to_beacon.dot(fwd)).normalized()
			else:
				_move_dir = Vector2.ZERO   # standing on beacon — hold and cap
		else:
			# All beacons owned — circle-strafe and fight
			_strafe_timer -= delta
			if _strafe_timer <= 0.0:
				_strafe_timer = randf_range(1.5, 3.0)
				_strafe_sign  = 1.0 if randf() > 0.5 else -1.0

			if dist > ENGAGE_DIST:
				_move_dir = Vector2(0.0, -1.0)
			else:
				_move_dir = Vector2(_strafe_sign, -0.3).normalized()

	# Stuck detection — if not making progress while moving, escape sideways
	_stuck_timer -= delta
	if _stuck_timer <= 0.0:
		_stuck_timer = STUCK_CHECK
		if _move_dir != Vector2.ZERO and \
				bot_mech.global_position.distance_to(_last_pos) < STUCK_DIST:
			_escape_timer = ESCAPE_TIME
			_escape_dir = 1.0 if randf() > 0.5 else -1.0
		_last_pos = bot_mech.global_position

	if _escape_timer > 0.0:
		_escape_timer -= delta
		_move_dir = Vector2(_escape_dir, -0.5).normalized()

	# Aim jitter — slow random drift that makes the bot miss occasionally
	_jitter_timer -= delta
	if _jitter_timer <= 0.0:
		_jitter_timer = randf_range(0.08, 0.18)
		_jitter = Vector2(randf_range(-AIM_SPREAD, AIM_SPREAD),
						  randf_range(-AIM_SPREAD, AIM_SPREAD))
	_look_delta += _jitter / sens

	# Burst fire — shoot for BURST_FIRE seconds, pause for BURST_PAUSE seconds
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_in_burst = not _in_burst
		_burst_timer = BURST_FIRE if _in_burst else BURST_PAUSE

	# Fire when aimed closely enough, in range, and in burst window
	_firing = _in_burst and abs(angle_h) < AIM_THRESHOLD and dist < ENGAGE_DIST + 15.0

func get_move_direction() -> Vector2:
	return _move_dir

func get_look_delta() -> Vector2:
	return _look_delta

func is_firing_primary() -> bool:
	return _firing
