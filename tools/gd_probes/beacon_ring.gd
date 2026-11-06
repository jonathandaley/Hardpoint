extends Node
# T229 probe (HUMAN_FOUND_ISSUES 2026-11-04: "Sydney doesn't show the ring around the
# beacons, probably covered by the grey rectangle"): on every map, each beacon's capture ring
# sits above the top of every flat mesh (plaza pads, slabs, pads, water) under its footprint.

const Beacon := preload("res://scripts/Beacon.gd")

func _fail(msg: String) -> void:
	push_error("[probe] beacon_ring: " + msg)

func _ring_y(b: Node3D) -> float:
	for c in b.get_node("Visual").get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh:
			return (c as MeshInstance3D).global_position.y
	return -INF

## Does the box's XZ footprint reach the ring's band around p (some point at r in [R-0.18, R])?
func _meets_band(box: AABB, p: Vector3) -> bool:
	var nx := clampf(p.x, box.position.x, box.end.x) - p.x
	var nz := clampf(p.z, box.position.z, box.end.z) - p.z
	var near := sqrt(nx * nx + nz * nz)
	var fx := maxf(absf(box.position.x - p.x), absf(box.end.x - p.x))
	var fz := maxf(absf(box.position.z - p.z), absf(box.end.z - p.z))
	var far := sqrt(fx * fx + fz * fz)
	return near <= Beacon.CIRCLE_RADIUS and far >= Beacon.CIRCLE_RADIUS - 0.18

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scenes := {}
	for f in DirAccess.get_files_at("res://resources/maps"):
		if f.ends_with(".tres"):
			var md: Resource = load("res://resources/maps/" + f)
			scenes[md.scene_path] = md
	var checked := 0
	for sp in scenes:
		Game.mp_active_match["roster"] = []
		Game.loadout["team_size"] = 1
		Game.loadout["map_def"] = scenes[sp]
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child.call_deferred(arena)
		for i in 3:
			await get_tree().process_frame
		var map: Node = arena.get("_map")
		var flats: Array = []  # global AABBs of thin meshes (decals, pads, water planes)
		for mi in map.find_children("*", "MeshInstance3D", true, false):
			var n := mi as MeshInstance3D
			if n.mesh == null or n.get_parent().get_parent() is Beacon or n.get_parent() is Beacon:
				continue
			var box: AABB = n.global_transform * n.get_aabb()
			if box.size.y < 1.0:
				flats.append(box)
		for b in get_tree().get_nodes_in_group("beacons"):
			var ry := _ring_y(b)
			var p: Vector3 = (b as Node3D).global_position
			for box in flats:
				# a pad buries the ring if it lies at its height (bottom at or under it, top over
				# it); a thin light strip on a 10 m ceiling (Corvette) doesn't. T314: only where
				# its footprint meets the ring's band (r = R - 0.18 .. R) -- the old square around
				# the whole disc flagged rocks wholly inside / outside the 6 m ring
				if _meets_band(box, p) and (box as AABB).position.y <= ry and (box as AABB).end.y >= ry - 0.02:
					_fail("%s beacon (%.0f, %.0f): ring at y %.2f, a flat mesh's top at %.2f covers it" % [
						String(sp).get_file(), p.x, p.z, ry, (box as AABB).end.y])
					break
			checked += 1
		arena.queue_free()
		await get_tree().process_frame
	print("[probe] beacon_ring done (%d beacons on %d maps)" % [checked, scenes.size()])
	get_tree().quit(0)
