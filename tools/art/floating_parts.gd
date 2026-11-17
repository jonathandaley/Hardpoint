extends Node
# PARKED in tools/art (outside the suite) until T439 fixes what it finds; then move it to tools/gd_probes.
#   godot --headless res://tools/art/floating_parts.tscn
# Floating-parts probe (user 2026-11-17: "some floating pieces in Factory and Giza"): on every map,
# each visible mesh must be connected to the ground through meshes that touch (AABBs grown by
# TOUCH). Flood fill from the meshes that reach the floor; whatever the fill never reaches is
# hanging in the air. Skips: things under scripted nodes (beacons, water, fog, pickups), terrain /
# floor planes, and names listed in a map's `floating_ok` (deliberate: canopies, sky props).
# ponytail: O(n^2) AABB pairs; fine at ~1-2k meshes a map, use a grid if a map gets far bigger.
const TOUCH := 0.15
const GROUND_TOL := 0.3
const GAP_MAX := 4.0

func _fail(msg: String) -> void:
	push_error("[probe] floating_parts: " + msg)

func _arena(md: Resource) -> Node:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = md
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	return arena

static func _checked(map: Node, mi: MeshInstance3D) -> bool:
	if mi.mesh == null or not mi.is_visible_in_tree() or mi.mesh is PlaneMesh or mi.mesh is QuadMesh:
		return false
	if mi.mesh is ArrayMesh:
		return false  # terrain / baked walls: they are the ground
	var p: Node = mi
	while p != map:
		if p == null or p.get_script() != null:
			return false
		p = p.get_parent()
	return true

## Floating meshes of one map: Array of [path, what is wrong].
static func floating(map: Node) -> Array:
	var boxes: Array[AABB] = []
	var nodes: Array = []
	for n in map.find_children("*", "MeshInstance3D", true, false):
		if _checked(map, n):
			nodes.append(n)
			boxes.append((n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb())
	var reached := PackedByteArray()
	reached.resize(boxes.size())
	var todo: Array[int] = []
	for i in boxes.size():
		var b := boxes[i]
		var g := -INF
		var lo := INF
		for c in [b.get_center(), b.position, b.position + Vector3(b.size.x, 0, 0), b.position + Vector3(0, 0, b.size.z), b.end]:
			g = maxf(g, float(map.call("ground_y", c.x, c.z)))
			lo = minf(lo, float(map.call("ground_y", c.x, c.z)))
		if b.position.y > lo + GROUND_TOL and b.position.y <= g + GROUND_TOL and b.size.y < 40.0:
			print("[probe] floating_parts: HOVER %s gap %.2f size %s at %s" % [map.get_path_to(nodes[i]), b.position.y - lo, b.size, b.get_center()])
		if b.position.y <= g + GROUND_TOL:
			reached[i] = 1
			todo.append(i)
	while not todo.is_empty():
		var i: int = todo.pop_back()
		var gb := boxes[i].grow(TOUCH)
		for j in boxes.size():
			if reached[j] == 0 and gb.intersects(boxes[j]):
				reached[j] = 1
				todo.append(j)
	# near misses: a post whose top stops TOUCH..GAP_MAX short of the piece covering it (a roof
	# over its pillars) reads as a hovering roof even though the fill reached it through others
	var gaps: Array = []
	for i in boxes.size():
		var a := boxes[i]
		var ar := Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(-0.1)
		for j in boxes.size():
			var b := boxes[j]
			var gap := b.position.y - a.end.y
			if gap <= TOUCH or gap >= GAP_MAX or not Rect2(b.position.x, b.position.z, b.size.x, b.size.z).encloses(ar):
				continue
			var between := false
			for k in boxes.size():
				var c := boxes[k]
				if k != i and k != j and c.end.y > a.end.y and c.position.y < b.position.y \
						and Rect2(c.position.x, c.position.z, c.size.x, c.size.z).intersects(ar):
					between = true
					break
			if not between:
				gaps.append([str(map.get_path_to(nodes[i])), gap, a.get_center()])
	var ok: Array = map.get("floating_ok") if map.get("floating_ok") != null else []
	var out: Array = []
	for i in boxes.size():
		if reached[i] == 0 and not String(nodes[i].name) in ok:
			out.append([str(map.get_path_to(nodes[i])), "floats, aabb %s" % boxes[i]])
	for g in gaps:
		out.append([g[0], "stops %.2f m short of the piece above it, at %s" % [g[1], g[2]]])
	return out

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scenes := {}
	for f in DirAccess.get_files_at("res://resources/maps"):
		if f.ends_with(".tres"):
			var md: Resource = load("res://resources/maps/" + f)
			if not scenes.has(md.scene_path):
				scenes[md.scene_path] = md
	var bad := 0
	for sp in scenes:
		var arena: Node = await _arena(scenes[sp])
		var map: Node = arena.get("_map")
		var mapname := String(sp).get_file().get_basename()
		var fl := floating(map)
		for e in fl:
			_fail("%s: %s %s" % [mapname, e[0], e[1]])
		print("[probe] floating_parts: %s %d floating" % [mapname, fl.size()])
		bad += fl.size()
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	print("[probe] floating_parts: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)
