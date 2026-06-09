class_name MissileLauncher
extends "res://scripts/ProjectileGun.gd"
# Fast-firing projectile with splash damage on impact.

@export var splash_radius: float = 4.0
@export var splash_damage: float = 15.0

func _do_fire() -> void:
	if owner_mech == null:
		return
	var cam := owner_mech.get("camera") as Camera3D
	if cam == null:
		return
	var cam_fwd := -cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var aim_query := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position + cam_fwd * range)
	aim_query.exclude = owner_mech.get_exclude_rids()
	var aim_result := space.intersect_ray(aim_query)
	var aim_point: Vector3 = aim_result.position if aim_result \
		else cam.global_position + cam_fwd * range
	if (aim_point - global_position).dot(cam_fwd) <= 0.0:
		aim_point = global_position + cam_fwd * range

	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	proj.damage = damage
	proj.speed = projectile_speed
	proj.lifetime = range / projectile_speed
	proj.team = owner_mech.get("team") if owner_mech.get("team") != null else 0
	proj._exclude_rids = owner_mech.get_exclude_rids()
	proj.splash_radius = splash_radius
	proj.splash_damage = splash_damage
	proj.owner_body = owner_mech
	proj.source_weapon = self
	proj.on_hit = func(body, pos): _emit_hit_if_visible(body, pos)
	get_tree().current_scene.add_child(proj)
	proj.global_transform = Transform3D(Basis(), global_position).looking_at(aim_point)
