class_name AerialStrike
extends "res://scripts/WeaponBase.gd"
# One fire command launches a quick burst of homing rockets that scatter onto target.

const HOMING_SCENE := preload("res://scenes/weapons/HomingProjectile.tscn")

@export var projectile_speed: float = 22.0
@export var arc_time: float = 1.8
@export var arc_up_blend: float = 0.92
@export var turn_rate: float = 2.8
@export var splash_radius: float = 8.0
@export var splash_damage: float = 1.6
@export var burst_count: int = 20
@export var burst_interval: float = 0.06
@export var jitter_radius: float = 5.0

func fire() -> void:
	if owner_mech == null or owner_mech.get("locked_target") == null:
		return
	super.fire()

func _do_fire() -> void:
	_fire_burst()

func _fire_burst() -> void:
	var lock_target := owner_mech.get("locked_target") as Node3D
	for i in burst_count:
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if not is_instance_valid(lock_target):
			break
		_spawn_rocket(lock_target)
		await get_tree().create_timer(burst_interval).timeout

func _spawn_rocket(lock_target: Node3D) -> void:
	var jitter := Vector3(
		Game.rng.randf_range(-jitter_radius, jitter_radius),
		0.0,
		Game.rng.randf_range(-jitter_radius, jitter_radius))

	var proj := HOMING_SCENE.instantiate() as Node3D
	proj.damage = damage
	proj.speed = projectile_speed
	proj.lifetime = range / projectile_speed
	proj.team = owner_mech.get("team") if owner_mech.get("team") != null else 0
	proj._exclude_rids = owner_mech.get_exclude_rids()
	proj.target = lock_target
	proj.target_offset = jitter
	proj.owner_body = owner_mech
	proj.source_weapon = self
	proj.arc_time = arc_time
	proj.arc_up_blend = arc_up_blend
	proj.turn_rate = turn_rate
	proj.splash_radius = splash_radius
	proj.splash_damage = splash_damage
	proj.on_hit = func(body, pos): _emit_hit_if_visible(body, pos)

	get_tree().current_scene.add_child(proj)
	var fwd_point := global_position - global_transform.basis.z
	proj.global_transform = Transform3D(Basis(), global_position).looking_at(fwd_point)
