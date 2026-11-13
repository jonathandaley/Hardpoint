class_name Patience
extends "res://scripts/WeaponBase.gd"
# Passive charge: builds while loaded. Fire releases at current charge level.
# Damage scales min→max over max_charge_time seconds. FIXED magazine.
# T307 (user 2026-11-05: "Remove the bullet entirely; the beam (totally instant shot) should
# exactly match the damage"): one instant hitscan shot like the laser's crosshair ray --
# damage lands on the ray's first hit the tick it fires and the beam ends exactly there.
# (A 360 m/s bullet used to fly there separately and land late, so aim led the beam.)

@export var inaccuracy_angle: float = 0.0  # half-cone degrees; 0 = perfectly accurate
@export var min_damage: float = 30.0
@export var max_damage: float = 250.0
@export var max_charge_time: float = 3.0
@export var projectile_speed: float = 360.0

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

# _charge_time scales fire damage (_do_fire), so it must advance at the fixed
# physics rate to stay deterministic -- not render rate.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)  # base cooldown/reload/refill timers
	if _reloading or (max_ammo >= 0 and ammo <= 0):
		_charge_time = 0.0
		_charge_visual.visible = false
		return
	_charge_time = minf(_charge_time + delta, max_charge_time)
	_charge_visual.visible = true
	var t := _charge_time / max_charge_time
	_charge_visual.scale = Vector3.ONE * lerpf(0.3, 1.4, t)
	_charge_mat.emission_energy_multiplier = lerpf(2.0, 8.0, t)

## T348 (HUMAN_FOUND 2026-11-08: damage should scale exponentially with charge, same max):
## charge squared -- half a charge hits a quarter of the way up, a full one still max_damage.
func charge_damage() -> float:
	var t := _charge_time / max_charge_time
	return lerpf(min_damage, max_damage, t * t)

func get_charge_progress() -> float:
	return _charge_time / max_charge_time

func _do_fire() -> void:
	if owner_mech == null:
		return
	var t := _charge_time / max_charge_time
	var actual_damage := charge_damage()

	var cam := owner_mech.get("camera") as Camera3D
	if cam == null:
		return
	var cam_fwd := -cam.global_transform.basis.z
	if inaccuracy_angle > 0.0:
		var perp := Vector3(Game.rng.randf_range(-1.0, 1.0), Game.rng.randf_range(-1.0, 1.0), Game.rng.randf_range(-1.0, 1.0))
		perp = perp - cam_fwd * perp.dot(cam_fwd)
		if perp.length_squared() > 0.0001:
			cam_fwd = (cam_fwd + perp.normalized() * tan(deg_to_rad(inaccuracy_angle))).normalized()
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position + cam_fwd * range)
	query.exclude = owner_mech.get_exclude_rids()
	var result := space.intersect_ray(query)
	var hit_pos: Vector3 = result.position if result else cam.global_position + cam_fwd * range
	_hit(result, actual_damage)

	_charge_time = 0.0
	_charge_visual.visible = false
	# T260 (HUMAN_FOUND_ISSUES 2026-11-05 "thick beam that fades slowly"): thicker with
	# charge, lingers 1.6 s, and clients see it too (it was server-only).
	VFX.tracer(global_position, hit_pos, Color(0.75, 0.5, 1.0), 1.6, true, lerpf(0.15, 0.4, t))
