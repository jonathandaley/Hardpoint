class_name Shotgun
extends "res://scripts/WeaponBase.gd"
# Fires pellet_count projectiles per shot with random spread.
# Damage falls off linearly from damage_close (point-blank) to damage_far (max range).

const PROJECTILE_SCENE := preload("res://scenes/weapons/Projectile.tscn")

@export var pellet_count: int = 8
@export var spread_angle: float = 5.0   # half-cone degrees per pellet
@export var damage_close: float = 18.0  # per pellet at range = 0
@export var damage_far: float = 3.0     # per pellet at range = max
@export var projectile_speed: float = 50.0

func _do_fire() -> void:
	if owner_mech == null:
		return
	var cam := owner_mech.get("camera") as Camera3D
	if cam == null:
		return
	var cam_fwd := -cam.global_transform.basis.z
	var ex: Array = owner_mech.get_exclude_rids()
	var t_val: int = owner_mech.get("team") if owner_mech.get("team") != null else 0
	var dc := damage_close
	var df := damage_far
	var r := range

	# One center raycast to find aim distance, so pellets converge on the crosshair target.
	var space := get_world_3d().direct_space_state
	var center_query := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position + cam_fwd * r)
	center_query.exclude = ex
	var center_result := space.intersect_ray(center_query)
	var aim_dist: float = cam.global_position.distance_to(center_result.position) \
		if center_result else r

	for _i in pellet_count:
		var pellet_fwd := cam_fwd
		if spread_angle > 0.0:
			var perp := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
			perp = perp - cam_fwd * perp.dot(cam_fwd)
			if perp.length_squared() > 0.0001:
				var radius := tan(deg_to_rad(spread_angle)) * sqrt(randf())
				pellet_fwd = (cam_fwd + perp.normalized() * radius).normalized()

		var aim_point := cam.global_position + pellet_fwd * aim_dist
		var proj := PROJECTILE_SCENE.instantiate() as Projectile
		proj.speed = projectile_speed
		proj.lifetime = range / projectile_speed
		proj.damage = dc
		proj.team = t_val
		proj._exclude_rids = ex
		proj.damage_override = func(dist: float) -> float:
			return lerpf(dc, df, clampf(dist / r, 0.0, 1.0))
		proj.on_hit = func(): hit_confirmed.emit()
		get_tree().current_scene.add_child(proj)
		proj.global_transform = Transform3D(Basis(), global_position).looking_at(aim_point)
