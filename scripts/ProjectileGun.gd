class_name ProjectileGun
extends "res://scripts/WeaponBase.gd"
# Spawns a Projectile each shot aimed along the camera's forward axis.

@export var projectile_speed: float = 40.0

const PROJECTILE_SCENE := preload("res://scenes/weapons/Projectile.tscn")

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
	var space := get_world_3d().direct_space_state
	var aim_query := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position + cam_fwd * range)
	aim_query.exclude = owner_mech.get_exclude_rids()
	var aim_result := space.intersect_ray(aim_query)
	var aim_point: Vector3 = aim_result.position if aim_result \
		else cam.global_position + cam_fwd * range

	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.damage = damage
	proj.speed = projectile_speed
	proj.team = owner_mech.get("team") if owner_mech.get("team") != null else 0
	proj._exclude_rids = owner_mech.get_exclude_rids()

	proj.on_hit = func(): hit_confirmed.emit()
	get_tree().current_scene.add_child(proj)
	# looking_at() orients -Z toward aim_point, matching Projectile's movement axis
	proj.global_transform = Transform3D(Basis(), global_position).looking_at(aim_point)
