class_name AIInputSource
extends "res://scripts/InputSource.gd"

const TURN_SPEED    := 1.8   # rad/s
const ENGAGE_DIST   := 35.0  # close enough to shoot
const RETREAT_DIST  := 8.0   # too close — back off
const AIM_THRESHOLD := 0.25  # fire when within this many radians of target

var _target: Node3D = null
var _look_delta: Vector2 = Vector2.ZERO
var _move_dir: Vector2 = Vector2.ZERO
var _firing: bool = false
var _strafe_timer: float = 0.0
var _strafe_sign: float = 1.0

func _ready() -> void:
	call_deferred("_find_target")

func _find_target() -> void:
	for mech in get_tree().get_nodes_in_group("mechs"):
		if mech.get("team") == 0:
			_target = mech
			break

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

	# Horizontal aim — rotate mech body toward player
	var to_flat := Vector3(to_target.x, 0.0, to_target.z)
	var h_dist  := to_flat.length()
	var angle_h := 0.0
	if h_dist > 0.01:
		to_flat = to_flat / h_dist
		angle_h = (-bot_mech.global_transform.basis.z).signed_angle_to(to_flat, Vector3.UP)
	var turn_h: float = clamp(angle_h, -TURN_SPEED * delta, TURN_SPEED * delta)
	_look_delta.x = -turn_h / sens

	# Vertical aim — tilt camera arm to track height difference
	var cam_arm := bot_mech.get_node_or_null("CameraArm") as SpringArm3D
	if cam_arm:
		var desired_pitch: float = atan2(-to_target.y, maxf(h_dist, 0.01))
		var pitch_diff: float    = desired_pitch - cam_arm.rotation.x
		var turn_v: float        = clamp(pitch_diff, -TURN_SPEED * delta, TURN_SPEED * delta)
		_look_delta.y = -turn_v / sens

	# Movement — advance, circle-strafe in range, retreat if too close
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.5, 3.0)
		_strafe_sign  = 1.0 if randf() > 0.5 else -1.0

	if dist > ENGAGE_DIST:
		_move_dir = Vector2(0.0, -1.0)
	elif dist < RETREAT_DIST:
		_move_dir = Vector2(0.0, 1.0)
	else:
		_move_dir = Vector2(_strafe_sign, -0.3).normalized()

	# Fire when aimed closely enough and in range
	_firing = abs(angle_h) < AIM_THRESHOLD and dist < ENGAGE_DIST + 15.0

func get_move_direction() -> Vector2:
	return _move_dir

func get_look_delta() -> Vector2:
	return _look_delta

func is_firing_primary() -> bool:
	return _firing
