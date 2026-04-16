class_name Projectile
extends Node3D
# A fired projectile. Moves forward each physics tick, raycasting ahead to detect hits.
# Spawned by ProjectileGun; configure damage/speed/team before adding to the scene tree.

var speed: float = 40.0
var damage: float = 25.0
var lifetime: float = 3.0
var team: int = 0          # reserved for friendly-fire checks later
var _exclude_rid: RID      # firing mech's RID — excluded from hit tests

var _age: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var step := -global_transform.basis.z * speed * delta

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	if _exclude_rid.is_valid():
		query.exclude = [_exclude_rid]
	var result := space.intersect_ray(query)

	if result:
		if result.collider.has_method("take_damage"):
			result.collider.take_damage(damage)
		queue_free()
		return

	global_position += step
