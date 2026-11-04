extends RefCounted
# T221: is a map playable everywhere a mech can get to? On a loaded Arena (any map scene):
#   1. navmesh reach: a path from every spawn point to every beacon (V55);
#   2. walk-out grid: points every `spacing` m snapped onto the navmesh (= where bots and
#      players can go); at each, a test mech (outside the match: no team, ignored by bots,
#      invincible) drops in, settles, then walks 1.5 s each way along +X, -X, +Z, -Z
#      (Hippogriff 1.75 m/s: ~2.6 m on open ground). A point is STUCK if the mech is
#      wedged: less than STUCK_M from it in every direction.
#   3. ISLANDS (reported, not failed): grid points the navmesh can't reach from team 0's
#      first spawn whose walks never got back onto the connected navmesh -- a pit or a
#      pocket shows here, but so do walkable slopes the navmesh splits (Badlands' edge
#      berm, Math Temple's outer ledges), so they are for a look, not a verdict.
# Used by the map_stuck probe (every map scene) and tools/maps/stuck_check.tscn (one map,
# finer grid, prints every stuck point). ponytail: no random-walk bots; add them if a trap
# ever needs a sequence of moves to fall into.

const STUCK_M := 1.0
const SETTLE := 30
const LEG := 90  # physics ticks per direction
const DIRS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
const LINK_M := 3.0  # a path that ends this close to its goal reaches it

static func _linked(nav: RID, from: Vector3, to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(nav, from, to, true)
	return not path.is_empty() and path[path.size() - 1].distance_to(to) < LINK_M

class Walker extends "res://scripts/InputSource.gd":
	var dir := Vector2.ZERO
	func get_move_direction() -> Vector2:
		return dir

static func run(arena: Node, spacing: float, mech_path := "res://resources/mechs/Hippogriff.tres") -> Dictionary:
	var tree: SceneTree = arena.get_tree()
	var region: NavigationRegion3D = arena.get("_nav_region")
	for i in 3000:
		if region != null and region.navigation_mesh.get_polygon_count() > 0 and not region.is_baking():
			break
		await tree.physics_frame
	for i in 10:
		await tree.physics_frame
	var map: Node = arena.get("_map")
	var nav: RID = arena.get_world_3d().navigation_map
	var md_map = Game.loadout.get("map_def")
	var out := {"map": String(md_map.map_name) if md_map != null else String(map.name), "unreached": [], "stuck": [],
		"islands": [], "tested": 0}
	# 1. reach
	for t in 2:
		for p in arena.spawn_points(t):
			for b in tree.get_nodes_in_group("beacons"):
				var path := NavigationServer3D.map_get_path(nav, p, b.global_position, true)
				if path.is_empty() or path[path.size() - 1].distance_to(b.global_position) > 5.0:
					out["unreached"].append("team %d spawn (%.0f, %.0f) -> %s" % [t, p.x, p.z, b.name])
	# 2. walk-out grid on the navmesh
	var c: Vector2 = map.center
	var half: float = float(map.minimap_half) * 0.95
	var pts: Array = []
	var x := c.x - half
	while x <= c.x + half:
		var z := c.y - half
		while z <= c.y + half:
			var probe := Vector3(x, float(map.ground_y(x, z)) + 1.0, z)
			var q := NavigationServer3D.map_get_closest_point(nav, probe)
			if Vector2(q.x, q.z).distance_to(Vector2(x, z)) < spacing * 0.3:
				pts.append(q)
			z += spacing
		x += spacing
	out["tested"] = pts.size()
	var md: Resource = load(mech_path)
	var home: Vector3 = arena.spawn_points(0)[0]
	var walkers: Array = []
	for p in pts:
		var m: CharacterBody3D = md.scene.instantiate()
		m.name = "StuckCheck_%d" % walkers.size()
		m.max_health = md.max_health
		m.base_walk_speed = md.walk_speed
		m.scale = Vector3.ONE * md.body_scale
		m.team = 99
		arena.add_child(m)
		m.remove_from_group("mechs")
		m.invincible = true
		m.global_position = p + Vector3.UP * 1.0
		var w := Walker.new()
		m.add_child(w)
		m.set_input_source(w)
		walkers.append([m, w, 0.0, _linked(nav, home, p)])  # [mech, input, max move, connected]
	for i in SETTLE:
		await tree.physics_frame
	for d in DIRS:
		var start: Array = walkers.map(func(e: Array) -> Vector3: return (e[0] as Node3D).global_position)
		for e in walkers:
			(e[1] as Walker).dir = d
		for i in LEG:
			await tree.physics_frame
		for k in walkers.size():
			var e: Array = walkers[k]
			var at: Vector3 = (e[0] as Node3D).global_position
			e[2] = maxf(float(e[2]), at.distance_to(start[k]))
			if not e[3]:  # an island: did this walk get it back to the connected navmesh?
				e[3] = _linked(nav, home, NavigationServer3D.map_get_closest_point(nav, at))
			(e[1] as Walker).dir = Vector2.ZERO
	for k in walkers.size():
		var e: Array = walkers[k]
		var p: Vector3 = (pts[k] as Vector3).snapped(Vector3.ONE * 0.1)
		if float(e[2]) < STUCK_M:
			out["stuck"].append(p)
		elif not e[3]:
			out["islands"].append(p)
		(e[0] as Node).queue_free()
	return out
