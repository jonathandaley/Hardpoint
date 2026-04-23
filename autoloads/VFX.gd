extends Node

# --- public API ---

func muzzle_flash(pos: Vector3, color: Color = Color(1.0, 0.80, 0.30)) -> void:
	var mi := _sphere(0.12, color, 5.0)
	get_tree().root.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ZERO, 0.07).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)

func hit_sparks(pos: Vector3, color: Color = Color(1.0, 0.55, 0.15)) -> void:
	for i in 6:
		var mi := _sphere(0.045, color, 3.0)
		get_tree().root.add_child(mi)
		mi.global_position = pos
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		var end_pos := pos + dir * randf_range(0.25, 0.65)
		var dur := randf_range(0.12, 0.22)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", end_pos, dur).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ZERO, dur).set_ease(Tween.EASE_IN)
		tw.finished.connect(mi.queue_free)

func death_explosion(pos: Vector3) -> void:
	# outer ring — orange
	_explode_sphere(pos, 1.0, Color(1.0, 0.45, 0.10), 5.0, 3.0, 0.15, 0.28)
	# inner core — white-yellow
	_explode_sphere(pos, 0.55, Color(1.0, 0.92, 0.60), 9.0, 1.6, 0.10, 0.22)
	# debris sparks
	for _i in 12:
		var mi := _sphere(0.06, Color(1.0, 0.65, 0.2), 3.0)
		get_tree().root.add_child(mi)
		mi.global_position = pos
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 1.5), randf_range(-1.0, 1.0)).normalized()
		var end_pos := pos + dir * randf_range(0.8, 2.5)
		var dur := randf_range(0.3, 0.55)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", end_pos, dur).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ZERO, dur).set_ease(Tween.EASE_IN)
		tw.finished.connect(mi.queue_free)

# --- helpers ---

func _explode_sphere(pos: Vector3, radius: float, color: Color, emission: float,
		peak_scale: float, rise: float, fall: float) -> void:
	var mi := _sphere(radius, color, emission)
	mi.scale = Vector3.ZERO
	get_tree().root.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * peak_scale, rise).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ZERO, fall).set_ease(Tween.EASE_IN)
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
