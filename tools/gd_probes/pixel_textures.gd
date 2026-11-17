extends Node
# T440 probe (user 2026-11-17: "I prefer chunky-pixel over blurry"): on every map, each textured
# map material (albedo or detail texture) draws with nearest filtering, and its detail grain is a
# small pixel texture (<= 64 px) -- except Redwood's floor, kept soft on purpose (user 2026-11-05).

func _fail(msg: String) -> void:
	push_error("[probe] pixel_textures: " + msg)

func _arena(md: Resource) -> Node:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = md
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	return arena

func _ready() -> void:
	var scenes := {}
	for f in DirAccess.get_files_at("res://resources/maps"):
		if f.ends_with(".tres"):
			var md: Resource = load("res://resources/maps/" + f)
			if not scenes.has(md.scene_path):
				scenes[md.scene_path] = md
	var bad := 0
	var soft_floors := 0
	for sp in scenes:
		var arena: Node = await _arena(scenes[sp])
		var map: Node = arena.get("_map")
		var mapname := String(sp).get_file().get_basename()
		var seen := {}
		for n in map.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.get_script() != null or mi.get_parent().get_script() != null and mi.get_parent() != map:
				continue  # beacons, water, fog: their own shaders
			for mm in MapScene.surface_materials(mi):
				var m := mm as StandardMaterial3D
				if m == null or seen.has(m) or (m.albedo_texture == null and not m.detail_enabled):
					continue
				seen[m] = true
				if mapname == "Forest" and mi.mesh is ArrayMesh and m.detail_enabled and m.detail_albedo is NoiseTexture2D:
					soft_floors += 1  # Redwood's floor stays soft
					continue
				if m.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST and m.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
					bad += 1
					_fail("%s: %s on %s draws filtered (texture_filter %d)" % [mapname, m, mi.name, m.texture_filter])
				if m.detail_enabled and m.detail_albedo != null and m.detail_albedo.get_width() > 64:
					bad += 1
					_fail("%s: detail grain on %s is %d px (a soft noise, not a pixel grain)" % [mapname, mi.name, m.detail_albedo.get_width()])
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	if soft_floors != 1:
		bad += 1
		_fail("expected Redwood's soft floor once, saw %d" % soft_floors)
	print("[probe] pixel_textures: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)
