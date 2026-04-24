class_name ArcWeapon
extends "res://scripts/WeaponBase.gd"
# Continuous homing beam aimed at locked_target. Damage ticks at fire_rate.
# Beam pivot child rotates each tick to track target in global space.

var _beam_pivot: Node3D = null
var _beam_mesh: MeshInstance3D = null
var _beam_timer: float = 0.0
var _loop_player: AudioStreamPlayer3D = null

func _ready() -> void:
	super._ready()
	_beam_pivot = Node3D.new()
	add_child(_beam_pivot)

	var box := BoxMesh.new()
	box.size = Vector3(0.045, 0.045, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.88)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.0, 1.0, 0.88)
	mat.emission_energy_multiplier = 5.0
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.set_surface_override_material(0, mat)
	_beam_pivot.add_child(mi)
	_beam_mesh = mi
	_beam_mesh.visible = false

func _process(delta: float) -> void:
	super._process(delta)
	if _beam_timer > 0.0:
		_beam_timer -= delta
		if _beam_timer <= 0.0:
			_beam_mesh.visible = false
			if _loop_player != null and _loop_player.playing:
				_loop_player.stop()

func fire() -> void:
	if owner_mech == null or owner_mech.get("locked_target") == null:
		return
	super.fire()

func _do_fire() -> void:
	if owner_mech == null:
		return
	var target := owner_mech.get("locked_target") as Node3D
	if not is_instance_valid(target):
		return

	var target_pos := target.global_position + Vector3(0, 1.0, 0)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, target_pos)
	query.exclude = owner_mech.get_exclude_rids()
	var result := space.intersect_ray(query)
	if result:
		if result.collider.has_method("take_damage"):
			result.collider.take_damage(damage)
			_emit_hit_if_visible(result.collider, result.position)

	var dist := maxf(0.01, global_position.distance_to(target_pos))
	_beam_pivot.look_at(target_pos, Vector3.UP)
	_beam_mesh.position = Vector3(0.0, 0.0, -dist * 0.5)
	_beam_mesh.scale.z = dist
	if not _beam_mesh.visible:
		_beam_mesh.visible = true
		_start_arc_loop()
	_beam_timer = 0.15

func _start_arc_loop() -> void:
	var stream := SoundManager.get_sfx_stream("arc_loop")
	if stream == null:
		return
	if _loop_player == null:
		_loop_player = AudioStreamPlayer3D.new()
		_loop_player.bus = "SFX"
		_loop_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_loop_player.unit_size = 10.0
		_loop_player.max_distance = 80.0
		add_child(_loop_player)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_loop_player.stream = stream
	_loop_player.play()
