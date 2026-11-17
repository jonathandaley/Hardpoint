extends Node
# T442 probe (2026-11-17 survey): on Forest, every crown is a cluster (>= 4 blobs, one darker
# underside) instead of one squashed sphere; ferns are fronds (thin blades, no wedge thicker than
# 0.5 m); and no root flare's top ring sticks out past its trunk (the seam ring).

func _fail(msg: String) -> void:
	push_error("[probe] forest_canopy: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Forest.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	var map: Node = arena.get("_map")
	var bad := 0
	var trees := 0
	var blades := 0
	for n in map.get_children():
		if n is MeshInstance3D and n.mesh is PrismMesh:
			blades += 1
			if (n.mesh as PrismMesh).size.z > 0.5:
				bad += 1
				if bad <= 3:
					_fail("a fern at %s is a wedge %s, not a frond" % [n.position, (n.mesh as PrismMesh).size])
		if not n is StaticBody3D:
			continue
		var trunk: CylinderMesh = null
		var flare: CylinderMesh = null
		var blobs: Array = []
		for c in n.get_children():
			if c is MeshInstance3D and c.mesh is CylinderMesh:
				if (c.mesh as CylinderMesh).height > 10.0:
					trunk = c.mesh
				else:
					flare = c.mesh
			elif c is MeshInstance3D and c.mesh is SphereMesh:
				blobs.append(c)
		if trunk == null or flare == null:
			continue
		trees += 1
		var dark := blobs.filter(func(b): return ((b as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.v < 0.2)
		if blobs.size() < 4 or dark.size() != 1:
			bad += 1
			if bad <= 3:
				_fail("tree at %s: %d crown blobs, %d dark underside (want >= 4, 1)" % [n.position, blobs.size(), dark.size()])
		var at3 := trunk.bottom_radius + (trunk.top_radius - trunk.bottom_radius) * 3.0 / trunk.height
		if flare.top_radius > at3:
			bad += 1
			if bad <= 3:
				_fail("tree at %s: flare top %.3f m sticks out past the trunk's %.3f m" % [n.position, flare.top_radius, at3])
	if trees < 20 or blades < 400:
		bad += 1
		_fail("only %d trees / %d fern blades" % [trees, blades])
	print("[probe] forest_canopy: %d trees, %d fern blades: %s" % [trees, blades, "PASS" if bad == 0 else "FAIL %d" % bad])
	get_tree().quit(1 if bad else 0)
