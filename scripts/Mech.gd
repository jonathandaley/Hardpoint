class_name Mech
extends CharacterBody3D
# The Pawn. Handles movement and weapon firing.
# Ignorant of who pilots it — all control comes through InputSource.

@export var base_walk_speed: float = 7.0
@export var base_reload_rate: float = 1.0
@export var team: int = 0

var _modifiers: Dictionary = {}
var _input_source: InputSource = null
var _camera_pitch: float = -0.3  # matches CameraArm initial rotation.x

@onready var camera_arm: SpringArm3D = $CameraArm
@onready var hardpoint_left: Node3D = $HardpointLeft
@onready var hardpoint_right: Node3D = $HardpointRight

var walk_speed: float:
	get: return base_walk_speed * _modifiers.get("walk_speed", 1.0)

func set_input_source(source: InputSource) -> void:
	_input_source = source
	if source is PlayerInputSource:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func apply_modifier(stat: String, value: float) -> void:
	_modifiers[stat] = value

func remove_modifier(stat: String) -> void:
	_modifiers.erase(stat)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= get_gravity().y * delta

	if _input_source != null:
		_handle_look()
		_handle_movement(delta)
		_handle_fire()

	move_and_slide()

func _handle_look() -> void:
	var look := _input_source.get_look_delta()
	if look == Vector2.ZERO:
		return
	var sens: float = Game.settings.get("mouse_sensitivity", 0.003)
	rotate_y(-look.x * sens)
	_camera_pitch = clamp(_camera_pitch - look.y * sens, -1.2, 0.4)
	camera_arm.rotation.x = _camera_pitch

func _handle_movement(delta: float) -> void:
	var dir2d := _input_source.get_move_direction()
	if dir2d == Vector2.ZERO:
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * 8.0 * delta)
		return
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var move_vec := (right * dir2d.x + forward * -dir2d.y).normalized()
	velocity.x = move_vec.x * walk_speed
	velocity.z = move_vec.z * walk_speed

func _handle_fire() -> void:
	if _input_source.is_firing_primary():
		_fire_hardpoint(hardpoint_left)
		_fire_hardpoint(hardpoint_right)

func _fire_hardpoint(hardpoint: Node3D) -> void:
	for child in hardpoint.get_children():
		if child.has_method("fire"):
			child.fire()
