extends Node
# T211 probe: Badlands loads as its own map scene and is a real arena: 5 beacons (V18),
# 3 spawn points per team, bigger than Math Temple, hills + canyons, ruins, mechs stand
# on its floor, and the navmesh reaches every beacon from every spawn (V55).

func _fail(msg: String) -> void:
	push_error("[probe] badlands: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 3
	Game.loadout["map_def"] = load("res://resources/maps/Badlands.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	var map: Node = arena.get("_map")
	if map == null or map.get_script().resource_path != "res://scripts/maps/Badlands.gd":
		_fail("Arena did not load the Badlands scene")
		get_tree().quit(0)
		return
	var beacons: Array = get_tree().get_nodes_in_group("beacons")
	if beacons.size() != 5:
		_fail("%d beacons (V18: 5)" % beacons.size())
	for t in 2:
		if arena.spawn_points(t).size() != 3:
			_fail("team %d has %d spawn points, want 3" % [t, arena.spawn_points(t).size()])
	if float(map.minimap_half) < 104.0 * 1.3:
		_fail("not bigger than Math Temple (half %.0f m)" % map.minimap_half)
	var lo := INF
	var hi := -INF
	for i in 41:
		for j in 41:
			var y: float = map.ground_y(-130.0 + i * 6.5, -130.0 + j * 6.5)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if hi - lo < 10.0:
		_fail("flat: %.1f m of relief inside the berm" % (hi - lo))
	if float(map._canyon_cut(-45, -12)) < 5.0:
		_fail("no canyon where the first one runs")
	var ruins := get_tree().get_nodes_in_group("ruins").size()
	if ruins < 40:  # ~12 buildings of several blocks each
		_fail("only %d ruin blocks" % ruins)
	for i in 120:
		await get_tree().physics_frame
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			if is_instance_valid(m) and not m.is_dead and (not m.is_on_floor() or absf(m.velocity.y) > 3.0):
				_fail("%s not standing on the floor (floor %s, vy %.1f)" % [m.name, m.is_on_floor(), m.velocity.y])
	var region: NavigationRegion3D = arena.get("_nav_region")
	for i in 3000:  # threaded bake of a 320 m map
		if region != null and region.navigation_mesh.get_polygon_count() > 0 and not region.is_baking():
			break
		await get_tree().physics_frame
	var nav_map: RID = arena.get_world_3d().navigation_map
	for i in 10:
		await get_tree().physics_frame  # map sync
	var misses := 0
	for t in 2:
		for p in arena.spawn_points(t):
			for b in beacons:
				var path := NavigationServer3D.map_get_path(nav_map, p, b.global_position, true)
				if path.is_empty() or path[path.size() - 1].distance_to(b.global_position) > 5.0:
					misses += 1
					_fail("no nav path from team %d spawn %s to %s" % [t, p.snapped(Vector3.ONE), b.name])
	print("[probe] badlands done (relief %.1f m, %d ruin blocks, navmesh %d polys, %d path misses)" % [
		hi - lo, ruins, region.navigation_mesh.get_polygon_count() if region != null else -1, misses])
	get_tree().quit(0)
