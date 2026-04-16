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

	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.damage = damage
	proj.speed = projectile_speed
	proj.team = owner_mech.get("team") if owner_mech.get("team") != null else 0
	proj._exclude_rid = owner_mech.get_rid()

	get_tree().current_scene.add_child(proj)
	# Spawn at muzzle, inherit camera orientation so -Z points in fire direction
	proj.global_transform = Transform3D(cam.global_transform.basis, global_position)
