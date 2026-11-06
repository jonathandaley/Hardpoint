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
var source_weapon: Node3D = null  # T103/V28: weapon node for server-side damage clamp
var is_ghost: bool = false  # T100: client-side visual ghost; skips hit detection
var _exclude_rids: Array = []
var on_hit: Callable
var splash_radius: float = 0.0
var splash_damage: float = 0.0
var target_offset: Vector3 = Vector3.ZERO

# Arc phase
var arc_time: float = 0.8       # seconds to fly in arc-up phase
var arc_up_blend: float = 0.65  # how much to blend toward up during arc (rest = forward)

# Phase 2 steering
var turn_rate: float = 3.5      # rad/s max steering rate

var _age: float = 0.0
var _velocity_dir: Vector3 = Vector3.ZERO  # zero = uninit; set from transform on first frame

# T289 / T333 (HUMAN_FOUND: rockets "didn't work in Sydney"; "Make rockets be smarter to avoid
# hitting obstacles"): the way ahead (LOOK_S of flight, or up to the target) is checked every tick;
# when anything but the target blocks it the rocket takes the nearest clear heading -- up first,
# then the sides, then down -- and turns AVOID_TURN x faster while dodging. Before: Sydney 4/16,
# Forest 7/16, Corvette 0/29 (the climb hit the ceiling) in probe rocket_maps. Ghosts steer the
# same way (same world, same exclusions).
const LOOK_S := 0.6
const AVOID_TURN := 2.5
const _AVOID_ANGLES := [0.35, 0.7, 1.05, 1.4]  # rad off the wanted heading
var _avoiding := false

func _clear(dir: Vector3, length: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + dir * length)
	q.exclude = _exclude_rids
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	# the target's own shield counts as the target: dodging round it would void the shield
	return r.is_empty() or r.collider == target or (is_instance_valid(target) and target.is_ancestor_of(r.collider))

func _avoid(desired: Vector3, length: float) -> Vector3:
	_avoiding = false
	if length < 0.5 or _clear(desired, length):
		return desired
	var side := desired.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.001 else Vector3.RIGHT
	var up := side.cross(desired).normalized()
	_avoiding = true
	for a in _AVOID_ANGLES:
		for axis in [up, side, -side, -up]:
			var d: Vector3 = (desired * cos(a) + axis * sin(a)).normalized()
			if _clear(d, length):
				return d
	return (desired * cos(1.4) + up * sin(1.4)).normalized()  # boxed in: climb

func _physics_process(delta: float) -> void:
	if not Game.prof_on:  # T165 profiling shim
		_physics_process_impl(delta)
		return
	var t0 := Time.get_ticks_usec()
	_physics_process_impl(delta)
	Game.prof_add("homing", Time.get_ticks_usec() - t0)

func _physics_process_impl(delta: float) -> void:
	if _velocity_dir == Vector3.ZERO:
		_velocity_dir = -global_transform.basis.z
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var look := speed * LOOK_S
	if _age < arc_time:
		# Phase 1: blend forward with world up
		var fwd := -global_transform.basis.z
		var desired := _avoid(fwd.lerp(Vector3.UP, arc_up_blend).normalized(), look)
		_velocity_dir = _velocity_dir.slerp(desired, minf(1.0, delta * 6.0))
	else:
		# Phase 2: steer toward target
		if is_instance_valid(target):
			var aim_at: Vector3 = target.call("center_mass") if target.has_method("center_mass") else target.global_position
			var to_aim := aim_at + target_offset - global_position
			var desired := _avoid(to_aim.normalized(), minf(look, to_aim.length()))  # T319: centre mass, was the feet
			var rate := turn_rate * (AVOID_TURN if _avoiding else 1.0)
			var angle := _velocity_dir.angle_to(desired)
			var t := minf(1.0, rate * delta / maxf(angle, 0.0001))
			_velocity_dir = _velocity_dir.slerp(desired, t)
		_velocity_dir = _velocity_dir.normalized()

	var step := _velocity_dir * speed * delta

	if is_ghost:
		global_position += step
		if _velocity_dir != Vector3.ZERO:
			look_at(global_position + _velocity_dir, Vector3.UP)
		return

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	if not _exclude_rids.is_empty():
		query.exclude = _exclude_rids
	var result := space.intersect_ray(query)

	if result:
		if result.collider.has_method("take_damage"):
			var target_team: int = result.collider.get("team") if "team" in result.collider else -1
			if target_team != team:
				result.collider.take_damage(damage, source_weapon)
				if on_hit.is_valid():
					on_hit.call(result.collider, result.position)
		if splash_radius > 0.0:
			for mech in get_tree().get_nodes_in_group("mechs"):
				if mech == result.collider or (is_instance_valid(owner_body) and mech == owner_body):
					continue
				if int(mech.get("team")) == team:
					continue
				var dist: float = Projectile.mech_distance(mech as Node3D, result.position)  # T327
				if dist < splash_radius:
					mech.take_damage(splash_damage * (1.0 - dist / splash_radius), source_weapon)
		queue_free()
		return

	global_position += step
	if _velocity_dir != Vector3.ZERO:
		look_at(global_position + _velocity_dir, Vector3.UP)
