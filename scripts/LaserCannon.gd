class_name LaserCannon
extends "res://scripts/WeaponBase.gd"
# Continuous-beam hitscan weapon. Damage ticks at fixed 1/fire_rate interval (V11).
# REFILLING magazine = overheat budget; refill_rate < fire_rate enforces burst play (V10).

var _beam: MeshInstance3D = null
var _beam_pivot: Node3D = null
var _beam_timer: float = 0.0
var _audio_timer: float = 0.0
var _loop_player: AudioStreamPlayer3D = null

func _ready() -> void:
	super._ready()
	_beam_pivot = Node3D.new()
	add_child(_beam_pivot)
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
	_beam_pivot.add_child(mesh_inst)
	_beam = mesh_inst
	_beam.visible = false

func _process(delta: float) -> void:
	# Base cooldown/reload timers run via the inherited _physics_process; this
	# _process handles only the cosmetic beam/audio fade timers.
	if _beam_timer > 0.0:
		_beam_timer -= delta
		if _beam_timer <= 0.0:
			_beam.visible = false
	if _audio_timer > 0.0:
		_audio_timer -= delta
		if _audio_timer <= 0.0:
			if _loop_player != null and _loop_player.playing:
				_loop_player.stop()

# Crosshair ray from the owner's camera: {} if no camera, else {"pos", "result"}.
func _crosshair_ray() -> Dictionary:
	var cam := owner_mech.get("camera") as Camera3D
	if cam == null:
		return {}
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z * range)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = owner_mech.get_exclude_rids()
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return {"pos": result.position if result else to, "result": result, "from": from}


# T142: harness-only description of a crosshair ray for beam_check / beam_fire events.
func _ray_info(ray: Dictionary) -> Dictionary:
	var p: Vector3 = ray["pos"]
	var f: Vector3 = ray["from"]
	var r: Dictionary = ray["result"]
	return {"hit": [p.x, p.y, p.z], "cam": [f.x, f.y, f.z],
		"collider": String(r.collider.name) if r else ""}

func _do_fire() -> void:
	if owner_mech == null:
		return
	var ray := _crosshair_ray()
	if ray.is_empty():
		return
	var hit_pos: Vector3 = ray["pos"]
	var result: Dictionary = ray["result"]
	# T299 (user: "Laser and arc should not go through targets, but stop when hitting a mech"):
	# the beam leaves the muzzle, not the camera -- a mech (or shield) on the way to the crosshair
	# point stops it and takes the hit. Walls there keep the old crosshair behaviour.
	var mq := PhysicsRayQueryParameters3D.create(global_position, hit_pos)
	mq.exclude = owner_mech.get_exclude_rids()
	var mr := get_world_3d().direct_space_state.intersect_ray(mq)
	if mr and mr.collider != (result.collider if result else null) and mr.collider.has_method("take_damage"):
		result = mr
		hit_pos = mr.position
	if result:
		if result.collider.has_method("take_damage"):
			var target_team: int = result.collider.get("team") if "team" in result.collider else -1
			var own_team: int = owner_mech.get("team") if "team" in owner_mech else -2
			if target_team != own_team:
				result.collider.take_damage(damage, self)
				_emit_hit_if_visible(result.collider, result.position)

	_beam_fx(hit_pos)
	if Game.sync_logging_enabled:
		Game.sync_log_event("beam_fire", owner_mech.name, _ray_info(ray))  # T142
	# Audit #15: beam + loop audio were server-only; remote peers saw nothing.
	# One RPC per damage tick (1/fire_rate); client-side fade timers hide the
	# beam and stop the audio on their own when ticks stop arriving.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_beam_fx.rpc(hit_pos)

func _beam_fx(hit_pos: Vector3) -> void:
	var hit_dist := maxf(0.01, global_position.distance_to(hit_pos))
	_beam_pivot.look_at(hit_pos, Vector3.UP)
	# T296: in the gun's own scale (weapon_scale x body_scale), or the beam stops short / overshoots
	var local := hit_dist / maxf(0.01, _beam_pivot.global_transform.basis.get_scale().z)
	_beam.position = Vector3(0.0, 0.0, -local * 0.5)
	_beam.scale.z = local
	if not _beam.visible:
		_beam.visible = true
	_start_laser_loop()
	_beam_timer = 0.12
	_audio_timer = 0.35

@rpc("authority", "unreliable_ordered")
func _rpc_beam_fx(hit_pos: Vector3) -> void:
	if not is_inside_tree() or multiplayer.is_server():  # V50 / B130: a straggler for a node already out of the tree
		return
	_beam_fx(hit_pos)
	# T142 (B-b): on the owner's own screen the server's beam must land where the
	# owner's crosshair points. Harness-only (sync logging); costs nothing in play.
	if Game.sync_logging_enabled and owner_mech != null \
			and int(owner_mech.get("owner_peer_id")) == multiplayer.get_unique_id():
		var ray := _crosshair_ray()
		if not ray.is_empty():
			var info := _ray_info(ray)
			info["server_hit"] = [hit_pos.x, hit_pos.y, hit_pos.z]
			info["local_hit"] = info["hit"]
			Game.sync_log_event("beam_check", owner_mech.name, info)

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
	if not _loop_player.playing:
		_loop_player.stream = stream
		_loop_player.play()
