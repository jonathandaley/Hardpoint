extends Node
# T438 probe (user 2026-11-17: "the redwood trunks extend past the highest leaves"): on Forest, every
# standing trunk's visible top ends inside its crown (at least 1 m under the crown's top).

func _fail(msg: String) -> void:
	push_error("[probe] forest_crowns: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Forest.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	var trees := 0
	var bad := 0
	for body in (arena.get("_map") as Node).get_children():
		var trunk: MeshInstance3D = null
		var crown_top := -INF  # T442: the crown is several blobs; its top is the highest
		for c in body.get_children():
			if c is MeshInstance3D and c.mesh is CylinderMesh and (c.mesh as CylinderMesh).height > 10.0:
				trunk = c
			elif c is MeshInstance3D and c.mesh is SphereMesh:
				crown_top = maxf(crown_top, c.position.y + (c.mesh as SphereMesh).height * 0.5)
		if trunk == null or crown_top == -INF:
			continue
		trees += 1
		var top := trunk.position.y + (trunk.mesh as CylinderMesh).height * 0.5
		if top > crown_top - 1.0:
			bad += 1
			if bad <= 3:
				_fail("trunk at %s: top %.1f m, crown top %.1f m" % [body.position, top, crown_top])
	if trees < 20:
		_fail("only %d trees found" % trees)
	print("[probe] forest_crowns: %d trees, %d poke out: %s" % [trees, bad, "PASS" if bad == 0 and trees >= 20 else "FAIL"])
	get_tree().quit(1 if bad or trees < 20 else 0)
