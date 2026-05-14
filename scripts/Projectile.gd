class_name Projectile
extends Node3D
# A fired projectile. Moves forward each physics tick, raycasting ahead to detect hits.
# Spawned by ProjectileGun; configure damage/speed/team before adding to the scene tree.

var speed: float = 40.0
var damage: float = 25.0
var lifetime: float = 3.0
var team: int = 0
var _exclude_rids: Array = []
var on_hit: Callable
var damage_override: Callable
var splash_radius: float = 0.0
var splash_damage: float = 0.0
var owner_body: Node3D = null
var source_weapon: Node3D = null  # T103/V28: weapon node for server-side damage clamp
var is_ghost: bool = false  # T100: client-side visual ghost; skips hit detection

@export var smoke_trail: bool = false

const _SMOKE_INTERVAL := 0.06
const _SMOKE_LIFETIME := 0.18

static var _smoke_mesh: SphereMesh = null
static var _smoke_mat: StandardMaterial3D = null

var _age: float = 0.0
var _distance_traveled: float = 0.0
var _smoke_timer: float = 0.0


static func _init_smoke() -> void:
	if _smoke_mesh != null:
		return
	_smoke_mesh = SphereMesh.new()
	_smoke_mesh.radius = 0.08
	_smoke_mesh.height = 0.16
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.albedo_color = Color(0.44, 0.44, 0.44)


func _spawn_smoke() -> void:
	_init_smoke()
	var mi := MeshInstance3D.new()
	mi.mesh = _smoke_mesh
	mi.set_surface_override_material(0, _smoke_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = global_position
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ZERO, _SMOKE_LIFETIME)
	tw.tween_callback(mi.queue_free)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	if smoke_trail:
		_smoke_timer += delta
		if _smoke_timer >= _SMOKE_INTERVAL:
			_smoke_timer = 0.0
			_spawn_smoke()

	var step := -global_transform.basis.z * speed * delta
	_distance_traveled += step.length()

	if is_ghost:
		global_position += step
		return

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	if not _exclude_rids.is_empty():
		query.exclude = _exclude_rids
	var result := space.intersect_ray(query)

	if result:
		if result.collider.has_method("take_damage"):
			var target_team: int = result.collider.get("team") if "team" in result.collider else -1
			if target_team != team:
				var actual: float = damage_override.call(_distance_traveled) if damage_override.is_valid() else damage
				result.collider.take_damage(actual, source_weapon)
				if on_hit.is_valid():
					on_hit.call(result.collider, result.position)
		if splash_radius > 0.0:
			for mech in get_tree().get_nodes_in_group("mechs"):
				if mech == result.collider or (is_instance_valid(owner_body) and mech == owner_body):
					continue
				if int(mech.get("team")) == team:
					continue
				var dist: float = (mech as Node3D).global_position.distance_to(global_position)
				if dist < splash_radius:
					mech.take_damage(splash_damage * (1.0 - dist / splash_radius), source_weapon)
		queue_free()
		return

	global_position += step
