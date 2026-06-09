extends Node

# --- public API ---

func muzzle_flash(pos: Vector3, color: Color = Color(1.0, 0.80, 0.30), broadcast: bool = false) -> void:
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_muzzle_flash.rpc(pos, color)
	var mi := _sphere(0.14, color, 6.0)
	mi.scale = Vector3(1.875, 1.875, 1.875)
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ZERO, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)

@rpc("authority", "unreliable")
func _rpc_muzzle_flash(pos: Vector3, color: Color) -> void:
	if multiplayer.is_server():
		return
	muzzle_flash(pos, color)

func tracer(from: Vector3, to: Vector3, color: Color = Color(0.75, 0.5, 1.0), duration: float = 0.35, broadcast: bool = false) -> void:
	var dist := from.distance_to(to)
	if dist < 0.01:
		return
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_tracer.rpc(from, to, color, duration)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, dist)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mi.set_surface_override_material(0, mat)
	get_tree().current_scene.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var up := Vector3.UP if abs((to - from).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.look_at(to, up)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: mat.emission_energy_multiplier = v, 4.0, 0.0, duration)
	tw.tween_callback(mi.queue_free)

@rpc("authority", "unreliable")
func _rpc_tracer(from: Vector3, to: Vector3, color: Color, duration: float) -> void:
	if multiplayer.is_server():
		return
	tracer(from, to, color, duration)

func hit_sparks(pos: Vector3, color: Color = Color(1.0, 0.55, 0.15), broadcast: bool = false) -> void:
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_hit_sparks.rpc(pos, color)
	for i in 6:
		var mi := _sphere(0.055, color, 3.5)
		get_tree().current_scene.add_child(mi)
		mi.global_position = pos
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()  # cosmetic
		var end_pos := pos + dir * randf_range(0.3, 0.8)
		var dur := randf_range(0.14, 0.24)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", end_pos, dur).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ZERO, dur).set_ease(Tween.EASE_IN)
		tw.finished.connect(mi.queue_free)

@rpc("authority", "unreliable")
func _rpc_hit_sparks(pos: Vector3, color: Color) -> void:
	if multiplayer.is_server():
		return
	hit_sparks(pos, color)

func death_explosion(pos: Vector3, broadcast: bool = false) -> void:
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_death_explosion.rpc(pos)
	# Instant white-orange core flash - brief, not dominant
	_explode_sphere(pos, 0.35, Color(1.0, 0.95, 0.82), 14.0, 2.8, 0.05, 0.09, 1.0)
	# 12 medium chunks replace the solid sphere - fragmented from frame 1
	for _i in 12:
		_explosion_chunk(pos)
	# 26 fine debris particles
	for _i in 26:
		_death_particle(pos)

@rpc("authority", "unreliable")
func _rpc_death_explosion(pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	death_explosion(pos)

func _explosion_chunk(pos: Vector3) -> void:
	var hot := randf()  # cosmetic
	var col := Color(1.0, lerpf(0.30, 0.72, hot), lerpf(0.0, 0.12, hot))
	var emit := randf_range(4.5, 7.5)
	var mi := _sphere(randf_range(0.18, 0.42), col, emit)
	var mat := mi.get_surface_override_material(0) as StandardMaterial3D
	mi.scale = Vector3.ONE * randf_range(0.6, 1.2)
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos + Vector3(randf_range(-0.25, 0.25), randf_range(-0.1, 0.25), randf_range(-0.25, 0.25))
	var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-0.1, 1.3), randf_range(-1.0, 1.0)).normalized()
	var end_pos := pos + dir * randf_range(1.2, 2.8)
	var dur := randf_range(0.22, 0.48)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "global_position", end_pos, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ZERO, dur).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v: float) -> void: mat.emission_energy_multiplier = v, emit, 0.0, dur)
	tw.finished.connect(mi.queue_free)

func _death_particle(pos: Vector3) -> void:
	var hot := randf()  # cosmetic
	var col := Color(1.0, lerpf(0.25, 0.80, hot), lerpf(0.0, 0.18, hot))
	var mi := _sphere(randf_range(0.05, 0.11), col, randf_range(3.0, 5.5))
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-0.15, 1.4), randf_range(-1.0, 1.0)).normalized()
	var end_pos := pos + dir * randf_range(1.0, 3.8)
	var dur := randf_range(0.38, 0.75)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "global_position", end_pos, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ZERO, dur * 0.85).set_ease(Tween.EASE_IN)
	tw.finished.connect(mi.queue_free)

# --- helpers ---

func _explode_sphere(pos: Vector3, radius: float, color: Color, emission: float,
		peak_scale: float, rise: float, fade: float, expand: float = 1.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission

	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.scale = Vector3.ZERO

	get_tree().current_scene.add_child(mi)
	mi.global_position = pos

	# Rise: scale 0 → peak
	var tw_rise := mi.create_tween()
	tw_rise.tween_property(mi, "scale", Vector3.ONE * peak_scale, rise).set_ease(Tween.EASE_OUT)
	# Fade: scale continues expanding AND emission fades simultaneously
	tw_rise.finished.connect(func() -> void:
		var tw_fade := mi.create_tween().set_parallel(true)
		tw_fade.tween_property(mi, "scale", Vector3.ONE * peak_scale * expand, fade).set_ease(Tween.EASE_IN)
		tw_fade.tween_method(func(v: float) -> void: mat.emission_energy_multiplier = v, emission, 0.0, fade)
		tw_fade.finished.connect(mi.queue_free)
	)

func _sphere(radius: float, color: Color, emission: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission
	mi.set_surface_override_material(0, mat)
	return mi
