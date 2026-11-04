extends Node
# T241 probe (HUMAN_FOUND_ISSUES 2026-11-04: obstacles are plain colour, "add some surface
# detail"): on every map, no opaque non-emissive mesh material is a bare flat colour any
# more -- each has a texture or a detail layer.

func _fail(msg: String) -> void:
	push_error("[probe] surface_detail: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scenes := {}
	for f in DirAccess.get_files_at("res://resources/maps"):
		if f.ends_with(".tres"):
			var md: Resource = load("res://resources/maps/" + f)
			scenes[md.scene_path] = md
	var summary: Array = []
	for sp in scenes:
		Game.mp_active_match["roster"] = []
		Game.loadout["team_size"] = 1
		Game.loadout["map_def"] = scenes[sp]
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child.call_deferred(arena)
		for i in 3:
			await get_tree().process_frame
		var map: Node = arena.get("_map")
		var plain := 0
		var total := 0
		for mi in map.find_children("*", "MeshInstance3D", true, false):
			for mm in MapScene.surface_materials(mi as MeshInstance3D):
				var m := mm as StandardMaterial3D
				if m == null or m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
						or m.resource_path != "":
					continue
				total += 1
				if m.albedo_texture == null and not m.detail_enabled and not m.vertex_color_use_as_albedo:
					plain += 1
		var name := String(sp).get_file().get_basename()
		if plain > 0:
			_fail("%s: %d of %d opaque meshes are still a bare flat colour" % [name, plain, total])
		summary.append("%s %d" % [name, total])
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	print("[probe] surface_detail done (%s)" % ", ".join(summary))
	get_tree().quit(0)
