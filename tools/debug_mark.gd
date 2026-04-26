# Debug mark tool — NOT wired up in production.
#
# To re-enable:
#   1. Mech.gd: add `signal mark_requested(pos: Vector3)`
#   2. Mech.gd: in _physics_process, inside human-input block:
#        if _input_source.is_mark_pressed():
#            mark_requested.emit(global_position)
#   3. InputSource.gd: add stub `func is_mark_pressed() -> bool: return false`
#   4. PlayerInputSource.gd: add override:
#        func is_mark_pressed() -> bool:
#            return Input.is_action_just_pressed("mark_debug")
#   5. Arena.gd: player_mech.mark_requested.connect(_on_mark_requested)
#   6. Arena.gd: paste _on_mark_requested below
#   project.godot already has `mark_debug` action bound.

# Paste into Arena.gd:
#
# func _on_mark_requested(pos: Vector3) -> void:
# 	print("[MARK] x=%.3f y=%.3f z=%.3f" % [pos.x, pos.y, pos.z])
# 	var mat := StandardMaterial3D.new()
# 	mat.albedo_color = Color(1.0, 0.8, 0.0)
# 	mat.emission_enabled = true
# 	mat.emission = Color(1.0, 0.8, 0.0)
# 	mat.emission_energy_multiplier = 3.0
# 	var mesh := SphereMesh.new()
# 	mesh.radius = 0.4
# 	mesh.height = 0.8
# 	var mi := MeshInstance3D.new()
# 	mi.mesh = mesh
# 	mi.set_surface_override_material(0, mat)
# 	mi.position = pos + Vector3(0, 0.4, 0)
# 	add_child(mi)
