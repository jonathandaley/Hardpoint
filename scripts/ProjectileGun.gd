class_name ProjectileGun
extends "res://scripts/WeaponBase.gd"
# Spawns a Projectile each shot aimed along the camera's forward axis.

@export var projectile_speed: float = 40.0
@export var inaccuracy_angle: float = 0.0  # half-cone degrees; 0 = perfectly accurate

const PROJECTILE_SCENE := preload("res://scenes/weapons/ProjectileGrey.tscn")

func _do_fire() -> void:
	if owner_mech == null:
		return
	var cam := owner_mech.get("camera") as Camera3D
	if cam == null:
		return

	# Cast from camera centre to find where the crosshair is pointing.
	# The projectile spawns at the barrel but aims at that point so it
	# converges with the crosshair regardless of the barrel's vertical offset.
	var cam_fwd := -cam.global_transform.basis.z
	if inaccuracy_angle > 0.0:
		var perp := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		perp = perp - cam_fwd * perp.dot(cam_fwd)
		if perp.length_squared() > 0.0001:
			cam_fwd = (cam_fwd + perp.normalized() * tan(deg_to_rad(inaccuracy_angle))).normalized()
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
	proj.source_weapon = self

	proj.on_hit = func(body, pos): _emit_hit_if_visible(body, pos)
	get_tree().current_scene.add_child(proj)
	# looking_at() orients -Z toward aim_point, matching Projectile's movement axis
	proj.global_transform = Transform3D(Basis(), global_position).looking_at(aim_point)

	# T100: broadcast ghost to clients when server in MP.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_spawn_ghost.rpc(global_position, proj.global_transform.basis,
			proj.speed, proj.lifetime, proj.team)

@rpc("authority", "reliable")
func _rpc_spawn_ghost(pos: Vector3, basis: Basis, speed: float, lifetime: float, team: int) -> void:
	if multiplayer.is_server():
		return
	var ghost := PROJECTILE_SCENE.instantiate() as Projectile
	ghost.is_ghost = true
	ghost.speed = speed
	ghost.lifetime = lifetime
	ghost.team = team
	get_tree().current_scene.add_child(ghost)
	var actual_basis := basis
	if owner_mech != null and owner_mech.get("owner_peer_id") == multiplayer.get_unique_id():
		var cam := owner_mech.get("camera") as Camera3D
		if cam != null:
			var aim_far := pos - cam.global_transform.basis.z * 1000.0
			actual_basis = Transform3D(Basis(), pos).looking_at(aim_far).basis
	ghost.global_transform = Transform3D(actual_basis, pos)
