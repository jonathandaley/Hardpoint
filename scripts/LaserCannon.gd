class_name LaserCannon
extends "res://scripts/WeaponBase.gd"
# Continuous-beam hitscan weapon. Damage ticks at fixed 1/fire_rate interval (V11).
# REFILLING magazine = overheat budget; refill_rate < fire_rate enforces burst play (V10).

var _beam: MeshInstance3D = null
var _beam_timer: float = 0.0
var _loop_player: AudioStreamPlayer3D = null

func _ready() -> void:
	super._ready()
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, 1.0)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.25, 0.1, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.1, 1.0)
	mat.emission_energy_multiplier = 3.0
	mesh_inst.set_surface_override_material(0, mat)
	add_child(mesh_inst)
	_beam = mesh_inst
	_beam.visible = false

func _process(delta: float) -> void:
	super._process(delta)
	if _beam_timer > 0.0:
		_beam_timer -= delta
		if _beam_timer <= 0.0:
			_beam.visible = false
			if _loop_player != null and _loop_player.playing:
				_loop_player.stop()

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
			result.collider.take_damage(damage)
			_emit_hit_if_visible(result.collider, result.position)

	var hit_dist := maxf(0.01, global_position.distance_to(hit_pos))
	_beam.position = Vector3(0.0, 0.0, -hit_dist * 0.5)
	_beam.scale.z = hit_dist
	if not _beam.visible:
		_beam.visible = true
		_start_laser_loop()
	_beam_timer = 0.12

func _start_laser_loop() -> void:
	var stream := SoundManager.get_sfx_stream("laser_loop")
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
