class_name Patience
extends "res://scripts/WeaponBase.gd"
# Passive charge: builds while loaded. Fire releases at current charge level.
# Damage scales min→max over max_charge_time seconds. FIXED magazine.

const PROJECTILE_SCENE := preload("res://scenes/weapons/Projectile.tscn")

@export var min_damage: float = 30.0
@export var max_damage: float = 250.0
@export var max_charge_time: float = 3.0
@export var projectile_speed: float = 180.0

var _charge_time: float = 0.0
var _charge_visual: MeshInstance3D = null
var _charge_mat: StandardMaterial3D = null

func _ready() -> void:
	super._ready()
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	mesh.radial_segments = 8
	mesh.rings = 4
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.5, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.5, 1.0)
	mat.emission_energy_multiplier = 2.0
	mi.set_surface_override_material(0, mat)
	add_child(mi)
	_charge_visual = mi
	_charge_mat = mat
	_charge_visual.visible = false

func _process(delta: float) -> void:
	super._process(delta)
	if _reloading or (max_ammo >= 0 and ammo <= 0):
		_charge_time = 0.0
		_charge_visual.visible = false
		return
	_charge_time = minf(_charge_time + delta, max_charge_time)
	_charge_visual.visible = true
	var t := _charge_time / max_charge_time
	_charge_visual.scale = Vector3.ONE * lerpf(0.3, 1.4, t)
	_charge_mat.emission_energy_multiplier = lerpf(2.0, 8.0, t)

func get_charge_progress() -> float:
	return _charge_time / max_charge_time

func _do_fire() -> void:
	if owner_mech == null:
		return
	var t := _charge_time / max_charge_time
	var actual_damage := lerpf(min_damage, max_damage, t)

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

	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	proj.damage = actual_damage
	proj.speed = projectile_speed
	proj.lifetime = range / projectile_speed
	proj.team = owner_mech.get("team") if owner_mech.get("team") != null else 0
	proj._exclude_rids = owner_mech.get_exclude_rids()
	proj.owner_body = owner_mech
	proj.on_hit = func(body, pos): _emit_hit_if_visible(body, pos)
	get_tree().current_scene.add_child(proj)
	proj.global_transform = Transform3D(Basis(), global_position).looking_at(aim_point)

	_charge_time = 0.0
	_charge_visual.visible = false
