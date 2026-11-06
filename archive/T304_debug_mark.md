# T304 archive (2026-11-06): debug-only code removed from the game at the user's request
# (HUMAN_FOUND 2026-11-05: "Remove debug mech and the 'e' mark set key. Archive the code just in case").
# resources/mechs/DebugMech.tres itself stays: the beacon_capture test scenario uses it.

## scenes/arena/Arena.gd
```gdscript
func _on_mark_requested(pos: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.0)
	mat.emission_energy_multiplier = 3.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos + Vector3(0, 0.4, 0)
	add_child(mi)
```

## scripts/Mech.gd (in _physics_process_impl, human input branch; plus `signal mark_requested(pos: Vector3)`)
```gdscript
			if _input_source.is_mark_pressed():
				mark_requested.emit(global_position)
```

## scripts/InputSource.gd
```gdscript
func is_mark_pressed() -> bool:
	return false
```

## scripts/PlayerInputSource.gd
```gdscript
func is_mark_pressed() -> bool:
	return Input.is_action_just_pressed("mark_debug")
```

## scripts/ReplayInputSource.gd
```gdscript
func is_mark_pressed() -> bool:
	return not _take_pulse("mark").is_empty()
```

## project.godot input map
```
mark_debug={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":69,"key_label":0,"unicode":101,"location":0,"echo":false,"script":null)
]
}
```

