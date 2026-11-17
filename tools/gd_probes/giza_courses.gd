extends Node
# T443 probe (2026-11-17 survey: smooth pyramids): every Giza pyramid is drawn in cut-stone courses:
# a world-triplanar, nearest-filtered texture whose mortar rows (0 and 8) are darker than the block
# faces between them, with a sharp blend so the courses run level on the faces.

func _fail(msg: String) -> void:
	push_error("[probe] giza_courses: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Giza.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	var bad := 0
	var pyramids := 0
	for b in (arena.get("_map") as Node).get_children():
		for c in b.get_children():
			if not (c is MeshInstance3D and c.mesh is CylinderMesh and (c.mesh as CylinderMesh).radial_segments == 4):
				continue
			pyramids += 1
			var m := (c as MeshInstance3D).material_override as StandardMaterial3D
			var img: Image = m.albedo_texture.get_image() if m != null and m.albedo_texture != null else null
			if img == null or not m.uv1_world_triplanar or m.uv1_triplanar_sharpness < 4.0 \
					or m.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
				bad += 1
				_fail("pyramid at %s: no world-triplanar pixel course texture" % b.position)
				continue
			if img.get_pixel(3, 0).v >= img.get_pixel(3, 4).v or img.get_pixel(3, 8).v >= img.get_pixel(3, 12).v:
				bad += 1
				_fail("pyramid at %s: no darker mortar rows" % b.position)
	if pyramids != 3:
		bad += 1
		_fail("found %d pyramids, want 3" % pyramids)
	print("[probe] giza_courses: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)
