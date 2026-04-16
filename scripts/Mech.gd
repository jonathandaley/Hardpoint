class_name Mech
extends CharacterBody3D
# The Pawn. Handles movement and weapon firing.
# Ignorant of who pilots it — all control comes through InputSource.
#
# Node hierarchy:
#   Mech (CharacterBody3D)
#     Legs (Node3D)         ← rotates toward velocity direction
#       LegMesh
#     Torso (Node3D)        ← rotates with mouse look
#       BodyMesh
#       HardpointLeft / HardpointRight
#       CameraArm / Camera3D
#     CollisionShape3D

signal died
signal damaged

@export var base_walk_speed: float = 5.25
@export var base_reload_rate: float = 1.0
@export var max_health: float = 100.0
@export var team: int = 0

var health: float = 0.0
var _modifiers: Dictionary = {}
var _input_source: Node = null   # InputSource — untyped to avoid cache dependency
var _camera_pitch: float = -0.3  # matches CameraArm initial rotation.x

@onready var torso: Node3D = $Torso
@onready var legs: Node3D = $Legs
@onready var camera: Camera3D = $Torso/CameraArm/Camera3D
@onready var camera_arm: SpringArm3D = $Torso/CameraArm
@onready var hardpoint_left: Node3D = $Torso/HardpointLeft
@onready var hardpoint_right: Node3D = $Torso/HardpointRight

var walk_speed: float:
	get: return base_walk_speed * _modifiers.get("walk_speed", 1.0)

func _ready() -> void:
	add_to_group("mechs")
	health = max_health
	_setup_weapon_owners()

func _setup_weapon_owners() -> void:
	for hp in [hardpoint_left, hardpoint_right]:
		for child in hp.get_children():
			if "owner_mech" in child:
				child.owner_mech = self

# Returns the torso's world-space basis — use this for aim direction and
# for decomposing world vectors into mech-local movement axes.
func get_aim_basis() -> Basis:
	return torso.global_transform.basis

func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health -= amount
	damaged.emit()
	print("[Mech] %s  %.0f / %.0f HP" % [name, health, max_health])
	if health <= 0.0:
		health = 0.0
		_die()

func _die() -> void:
	print("[Mech] %s destroyed" % name)
	set_physics_process(false)
	set_process(false)
	$CollisionShape3D.disabled = true
	visible = false
	died.emit()

func set_input_source(source: Node) -> void:
	_input_source = source
	if source != null and source.has_method("is_human_input") and source.is_human_input():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func apply_modifier(stat: String, value: float) -> void:
	_modifiers[stat] = value

func remove_modifier(stat: String) -> void:
	_modifiers.erase(stat)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _input_source != null:
		_handle_look()
		_handle_movement(delta)
		_handle_fire()

	move_and_slide()
	_update_legs()

func _update_legs() -> void:
	var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horiz_vel.length_squared() > 0.25:
		legs.look_at(legs.global_position + horiz_vel.normalized(), Vector3.UP)

func _handle_look() -> void:
	var look: Vector2 = _input_source.get_look_delta()
	if look == Vector2.ZERO:
		return
	var sens: float = Game.settings.get("mouse_sensitivity", 0.003)
	torso.rotate_y(-look.x * sens)
	_camera_pitch = clamp(_camera_pitch - look.y * sens, -1.2, 0.4)
	camera_arm.rotation.x = _camera_pitch

func _handle_movement(delta: float) -> void:
	var dir2d: Vector2 = _input_source.get_move_direction()
	if dir2d == Vector2.ZERO:
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * 8.0 * delta)
		return
	var aim := torso.global_transform.basis
	var forward := -aim.z
	var right := aim.x
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
