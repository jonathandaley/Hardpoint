class_name MachineGun
extends "res://scripts/ProjectileGun.gd"
# Fixed mag, accelerating fire rate while trigger held, resets on release.
# base_fire_rate -> ramps to max_fire_rate at rate_accel rps/s.
# Releasing trigger decays back to base at rate_decay rps/s.

@export var spread_angle: float = 1.0  # half-cone degrees; total spread = 2x this
@export var base_fire_rate: float = 4.0
@export var max_fire_rate: float = 14.0
@export var rate_accel: float = 10.0   # rps added per second while held
@export var rate_decay: float = 25.0   # rps lost per second after release

var _current_rate: float = 0.0
var _trigger_held: bool = false

func _do_fire() -> void:
	if owner_mech == null:
		return
	var cam := owner_mech.get("camera") as Camera3D
	if cam == null:
		return
	var cam_fwd := -cam.global_transform.basis.z
	if spread_angle > 0.0:
		var perp := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		perp = perp - cam_fwd * perp.dot(cam_fwd)
		if perp.length_squared() > 0.0001:
			cam_fwd = (cam_fwd + perp.normalized() * tan(deg_to_rad(spread_angle))).normalized()
	var space := get_world_3d().direct_space_state
	var aim_query := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position + cam_fwd * range)
	aim_query.exclude = owner_mech.get_exclude_rids()
	var aim_result := space.intersect_ray(aim_query)
	var aim_point: Vector3 = aim_result.position if aim_result \
		else cam.global_position + cam_fwd * range
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	proj.damage = damage
	proj.speed = projectile_speed
	proj.lifetime = range / projectile_speed
	proj.team = owner_mech.get("team") if owner_mech.get("team") != null else 0
	proj._exclude_rids = owner_mech.get_exclude_rids()
	proj.on_hit = func(body): _emit_hit_if_visible(body)
	get_tree().current_scene.add_child(proj)
	proj.global_transform = Transform3D(Basis(), global_position).looking_at(aim_point)

func _ready() -> void:
	super._ready()
	_current_rate = base_fire_rate

func _process(delta: float) -> void:
	super._process(delta)
	if _trigger_held:
		_current_rate = minf(_current_rate + rate_accel * delta, max_fire_rate)
	else:
		_current_rate = maxf(_current_rate - rate_decay * delta, base_fire_rate)
	_trigger_held = false

func fire() -> void:
	_trigger_held = true
	if _cooldown > 0.0:
		return
	if _reloading:
		return
	if max_ammo >= 0 and ammo <= 0:
		if magazine_type == MagazineType.FIXED:
			_start_reload()
		return
	_cooldown = 1.0 / _current_rate
	_do_fire()
	if shake_magnitude > 0.0 and owner_mech != null and owner_mech.has_method("apply_camera_shake"):
		owner_mech.apply_camera_shake(shake_magnitude)
	if max_ammo >= 0:
		ammo -= 1
		if ammo <= 0 and magazine_type == MagazineType.FIXED:
			_start_reload()
