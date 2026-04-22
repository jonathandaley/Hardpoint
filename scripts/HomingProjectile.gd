class_name HomingProjectile
extends Node3D
# Homing projectile: phase 1 arcs upward, phase 2 steers toward target.
# Shared by RocketLauncher (T19) and Arc weapon (T21) via configuration.

var speed: float = 18.0
var damage: float = 80.0
var lifetime: float = 10.0
var team: int = 0
var target: Node3D = null
var owner_body: Node3D = null
var _exclude_rids: Array = []
var on_hit: Callable

# Arc phase
var arc_time: float = 0.8       # seconds to fly in arc-up phase
var arc_up_blend: float = 0.65  # how much to blend toward up during arc (rest = forward)

# Phase 2 steering
var turn_rate: float = 3.5      # rad/s max steering rate

var _age: float = 0.0
var _velocity_dir: Vector3 = Vector3.ZERO  # zero = uninit; set from transform on first frame

func _physics_process(delta: float) -> void:
	if _velocity_dir == Vector3.ZERO:
		_velocity_dir = -global_transform.basis.z
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	if _age < arc_time:
		# Phase 1: blend forward with world up
		var fwd := -global_transform.basis.z
		var desired := fwd.lerp(Vector3.UP, arc_up_blend).normalized()
		_velocity_dir = _velocity_dir.slerp(desired, minf(1.0, delta * 6.0))
	else:
		# Phase 2: steer toward target
		if is_instance_valid(target):
			var to_target := (target.global_position - global_position).normalized()
			var angle := _velocity_dir.angle_to(to_target)
			var t := minf(1.0, turn_rate * delta / maxf(angle, 0.0001))
			_velocity_dir = _velocity_dir.slerp(to_target, t)
		_velocity_dir = _velocity_dir.normalized()

	var step := _velocity_dir * speed * delta

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	if not _exclude_rids.is_empty():
		query.exclude = _exclude_rids
	var result := space.intersect_ray(query)

	if result:
		if result.collider.has_method("take_damage"):
			result.collider.take_damage(damage)
			if on_hit.is_valid():
				on_hit.call()
		queue_free()
		return

	global_position += step
	if _velocity_dir != Vector3.ZERO:
		look_at(global_position + _velocity_dir, Vector3.UP)
