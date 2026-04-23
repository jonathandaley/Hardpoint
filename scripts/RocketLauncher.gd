class_name RocketLauncher
extends "res://scripts/WeaponBase.gd"
# Single-shot homing rocket. Requires target lock. Arcs up then descends onto target.

const HOMING_SCENE := preload("res://scenes/weapons/HomingProjectile.tscn")

@export var projectile_speed: float = 18.0
@export var arc_time: float = 0.8
@export var arc_up_blend: float = 0.65
@export var turn_rate: float = 2.1

func fire() -> void:
	if owner_mech == null or owner_mech.get("locked_target") == null:
		return
	super.fire()

func _do_fire() -> void:
	var lock_target := owner_mech.get("locked_target") as Node3D

	var proj := HOMING_SCENE.instantiate() as Node3D
	proj.damage = damage
	proj.speed = projectile_speed
	proj.lifetime = range / projectile_speed
	proj.team = owner_mech.get("team") if owner_mech.get("team") != null else 0
	proj._exclude_rids = owner_mech.get_exclude_rids()
	proj.target = lock_target
	proj.owner_body = owner_mech
	proj.arc_time = arc_time
	proj.arc_up_blend = arc_up_blend
	proj.turn_rate = turn_rate
	proj.on_hit = func(body): _emit_hit_if_visible(body)

	get_tree().current_scene.add_child(proj)
	var fwd_point := global_position - global_transform.basis.z
	proj.global_transform = Transform3D(Basis(), global_position).looking_at(fwd_point)
