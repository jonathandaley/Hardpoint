extends Node
# T439 probe (user 2026-11-17: "some floating pieces in Factory and Giza"): on every map, no mesh
# reads as hanging in the air. Three checks over mesh AABBs:
#  - floating: flood fill from the meshes that reach the floor through meshes that touch (AABBs
#    grown by TOUCH); whatever the fill never reaches is in the air.
#  - short post: a piece whose top stops TOUCH..GAP_MAX under a piece covering it, with nothing
#    between (Giza's temple roofs over dune-following pillars).
#  - slope hover: a piece standing on the floor (its AABB's lowest corner touches) with a corner of
#    its own bottom face more than HOVER_TOL above the floor (props set at their centre's ground
#    height on a slope).
# Skips things under scripted nodes (beacons, water, fog, pickups), floor planes and terrain
# (ArrayMesh); the slope and short-post checks skip anything 40 m+ tall (trunks, towers: sunk on
# purpose; a pyramid is a 4-sided CylinderMesh whose AABB reaches 40% past its real base).
# ponytail: O(n^2) AABB pairs; ~1 s a map at ~1-2k meshes, use a grid if a map gets far bigger.
const TOUCH := 0.15
const GROUND_TOL := 0.3
const HOVER_TOL := 0.3
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
	if mi.mesh == null or not mi.is_visible_in_tree() or mi.mesh is PlaneMesh or mi.mesh is QuadMesh or mi.mesh is ArrayMesh:
		return false
	var p: Node = mi
	while p != map:
		if p == null or p.get_script() != null:
			return false
		p = p.get_parent()
	return true

## Floor height under p: the map's ground, or a collider under p (Math Temple's raised floors).
static func _floor(map: Node3D, p: Vector3, exclude: Array) -> float:
	var g := float(map.call("ground_y", p.x, p.z))
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.5, 0), p + Vector3(0, -30, 0))
	q.exclude = exclude
	var hit := map.get_world_3d().direct_space_state.intersect_ray(q)
	return maxf(g, (hit["position"] as Vector3).y) if not hit.is_empty() else g

static func _xz(b: AABB) -> Rect2:
	return Rect2(b.position.x, b.position.z, b.size.x, b.size.z)

## Problems on one map: Array of strings.
static func problems(map: Node) -> Array:
	var boxes: Array[AABB] = []
	var names: Array = []
	var feet: Array = []  # the mesh's own bottom-face corners + centre, in world space
	var bodies: Array = []  # its collider's RID (excluded from the floor ray), or none
	for n in map.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if _checked(map, mi):
			boxes.append(mi.global_transform * mi.get_aabb())
			var la := mi.get_aabb()
			var f: Array = []
			for k in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0.5)]:
				f.append(mi.global_transform * (la.position + Vector3(la.size.x * k.x, 0.0, la.size.z * k.y)))
			feet.append(f)
			bodies.append([(mi.get_parent() as CollisionObject3D).get_rid()] if mi.get_parent() is CollisionObject3D else [])
			names.append("%s %s" % [mi.mesh.get_class(), str(mi.mesh.get("size") if mi.mesh.get("size") != null else "")])
	var out: Array = []
	var reached := PackedByteArray()
	reached.resize(boxes.size())
	var todo: Array[int] = []
	for i in boxes.size():
		var b := boxes[i]
		var hi := -INF
		var lo := INF
		for c in [b.get_center(), b.position, b.position + Vector3(b.size.x, 0, 0), b.position + Vector3(0, 0, b.size.z), b.end]:
			var g := float(map.call("ground_y", c.x, c.z))
			hi = maxf(hi, g)
			lo = minf(lo, g)
		if b.position.y <= hi + GROUND_TOL:
			reached[i] = 1
			todo.append(i)
			var propped := false  # resting on another piece (planks on posts, roofs on walls)
			for j in boxes.size():
				if j != i and boxes[j].position.y < b.position.y - TOUCH and boxes[j].grow(TOUCH).intersects(b):
					propped = true
					break
			var worst := -INF
			var deepest := INF
			for c in feet[i]:
				var gap := (c as Vector3).y - _floor(map, c, bodies[i])
				worst = maxf(worst, gap)
				deepest = minf(deepest, gap)
			# a tilted slab with its low edge sunk in the ground is embedded, not hovering
			if worst > HOVER_TOL and deepest > -HOVER_TOL and not propped and b.size.y < 40.0:
				out.append("%s hangs %.2f m over the slope at %s" % [names[i], worst, b.get_center()])
	while not todo.is_empty():
		var i: int = todo.pop_back()
		var gb := boxes[i].grow(TOUCH)
		for j in boxes.size():
			if reached[j] == 0 and gb.intersects(boxes[j]):
				reached[j] = 1
				todo.append(j)
	for i in boxes.size():
		if reached[i] == 0:
			out.append("%s floats at %s (aabb %s)" % [names[i], boxes[i].get_center(), boxes[i]])
	for i in boxes.size():
		var a := boxes[i]
		var ar := _xz(a).grow(-minf(0.1, minf(a.size.x, a.size.z) * 0.25))  # thin rails: never negative
		for j in boxes.size():
			var b := boxes[j]
			var gap := b.position.y - a.end.y
			if gap <= TOUCH or gap >= GAP_MAX or b.size.y >= 40.0 or not _xz(b).encloses(ar):
				continue
			var between := false
			for k in boxes.size():
				var c := boxes[k]
				if k != i and k != j and c.end.y > a.end.y and c.position.y < b.position.y and _xz(c).intersects(ar):
					between = true
					break
			if not between:
				out.append("%s stops %.2f m short of the %s above it, at %s" % [names[i], gap, names[j], a.get_center()])
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
		var mapname := String(sp).get_file().get_basename()
		var found := problems(arena.get("_map"))
		for e in found:
			_fail("%s: %s" % [mapname, e])
		print("[probe] floating_parts: %s %d" % [mapname, found.size()])
		bad += found.size()
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	print("[probe] floating_parts: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)
