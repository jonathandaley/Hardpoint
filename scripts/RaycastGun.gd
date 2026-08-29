class_name RaycastGun
extends "res://scripts/WeaponBase.gd"
# Hitscan weapon. Ray fires from screen centre in camera's forward direction.
# Muzzle flash is cosmetic - stays at hardpoint position.

@onready var muzzle_flash: MeshInstance3D = $MuzzleFlash
var _flash_timer: float = 0.0

func _process(delta: float) -> void:
	# Base cooldown/reload timers run via the inherited _physics_process; this
	# _process handles only the cosmetic muzzle-flash fade timer.
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			muzzle_flash.visible = false

func _do_fire() -> void:
	if owner_mech == null:
		return
	var cam := owner_mech.get("camera") as Camera3D
	if cam == null:
		return

	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z * range)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = owner_mech.get_exclude_rids()

	var hit_pos := to
	var result := space.intersect_ray(query)
	if result:
		hit_pos = result.position
		if result.collider.has_method("take_damage"):
			var target_team: int = result.collider.get("team") if "team" in result.collider else -1
			var own_team: int = owner_mech.get("team") if "team" in owner_mech else -2
			if target_team != own_team:
				result.collider.take_damage(damage, self)
				_emit_hit_if_visible(result.collider, result.position)

	_shot_fx(hit_pos)
	# Audit #15: tracer + flash were server-only; remote peers saw nothing.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_shot_fx.rpc(hit_pos)

func _shot_fx(hit_pos: Vector3) -> void:
	_spawn_tracer(muzzle_flash.global_position, hit_pos)
	muzzle_flash.visible = true
	_flash_timer = 0.08

@rpc("authority", "unreliable")
func _rpc_shot_fx(hit_pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	_shot_fx(hit_pos)

func _spawn_tracer(origin: Vector3, target: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var dist := origin.distance_to(target)
	mesh.size = Vector3(0.025, 0.025, dist)
	tracer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.5, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.set_surface_override_material(0, mat)
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = (origin + target) * 0.5
	tracer.look_at(target)
	get_tree().create_timer(0.05).timeout.connect(tracer.queue_free)

