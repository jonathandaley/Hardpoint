extends Node

# --- public API ---

func muzzle_flash(pos: Vector3, color: Color = Color(1.0, 0.80, 0.30)) -> void:
	var mi := _sphere(0.14, color, 6.0)
	mi.scale = Vector3(1.875, 1.875, 1.875)
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ZERO, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)

func hit_sparks(pos: Vector3, color: Color = Color(1.0, 0.55, 0.15)) -> void:
	for i in 6:
		var mi := _sphere(0.055, color, 3.5)
		get_tree().current_scene.add_child(mi)
		mi.global_position = pos
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()
		var end_pos := pos + dir * randf_range(0.3, 0.8)
		var dur := randf_range(0.14, 0.24)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", end_pos, dur).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ZERO, dur).set_ease(Tween.EASE_IN)
		tw.finished.connect(mi.queue_free)

func death_explosion(pos: Vector3) -> void:
	# Flash — brief, fades fast so particles take over
	_explode_sphere(pos, 1.0, Color(1.0, 0.55, 0.15), 6.0, 3.0, 0.08, 0.14)
	_explode_sphere(pos, 0.5, Color(1.0, 0.95, 0.7), 11.0, 1.6, 0.05, 0.10)
	# Particles carry the energy after the flash
	for _i in 26:
		_death_particle(pos)

func _death_particle(pos: Vector3) -> void:
	var hot := randf()
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
		peak_scale: float, rise: float, fade: float) -> void:
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

	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * peak_scale, rise).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mat.emission_energy_multiplier = v, emission, 0.0, fade)
	tw.tween_callback(mi.queue_free)

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
