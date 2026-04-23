class_name Projectile
extends Node3D
# A fired projectile. Moves forward each physics tick, raycasting ahead to detect hits.
# Spawned by ProjectileGun; configure damage/speed/team before adding to the scene tree.

var speed: float = 40.0
var damage: float = 25.0
var lifetime: float = 3.0
var team: int = 0          # reserved for friendly-fire checks later
var _exclude_rids: Array = []   # RIDs excluded from hit tests (mech + own shield)
var on_hit: Callable       # called when the projectile hits a damageable target
var damage_override: Callable  # optional: func(distance: float) -> float
var splash_radius: float = 0.0
var splash_damage: float = 0.0
var owner_body: Node3D = null  # excluded from splash (set by weapon on spawn)

var _age: float = 0.0
var _distance_traveled: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var step := -global_transform.basis.z * speed * delta
	_distance_traveled += step.length()

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	if not _exclude_rids.is_empty():
		query.exclude = _exclude_rids
	var result := space.intersect_ray(query)

	if result:
		if result.collider.has_method("take_damage"):
			var actual: float = damage_override.call(_distance_traveled) if damage_override.is_valid() else damage
			result.collider.take_damage(actual)
			if on_hit.is_valid():
				on_hit.call(result.collider, result.position)
		if splash_radius > 0.0:
			for mech in get_tree().get_nodes_in_group("mechs"):
				if mech == result.collider or mech == owner_body:
					continue
				var dist: float = (mech as Node3D).global_position.distance_to(global_position)
				if dist < splash_radius:
					mech.take_damage(splash_damage * (1.0 - dist / splash_radius))
		queue_free()
		return

	global_position += step
