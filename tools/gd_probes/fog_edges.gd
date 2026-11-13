extends Node
# T405 probe (HUMAN_FOUND, queued 2026-11-13: "Make the edges of the maps disappear into fog, so the hard
# world border isn't as jarring. The physical edges are good where they are now, just visual needs an
# upgrade."): every square outdoor map (Forest, Giza, Factory, Swamp, Badlands) gets fog curtains on all
# four edges in its own fog colour, the outermost opaque; the walls themselves don't move.

const MAPS := ["Forest", "Giza", "Factory", "Swamp", "Badlands"]

func _fail(msg: String) -> void:
	push_error("[probe] fog_edges FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for mname in MAPS:
		Game.mp_active_match["roster"] = []
		Game.loadout["team_size"] = 1
		Game.loadout["map_def"] = load("res://resources/maps/%s.tres" % mname)
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child.call_deferred(arena)
		for i in 3:
			await get_tree().process_frame
		var map: Node = arena.get("_map")
		var curtains: Array = map.find_children("FogEdge_*", "MeshInstance3D", false, false) if map != null else []
		var sides := {}
		var opaque := 0
		for c in curtains:
			var tint: Color = (c as MeshInstance3D).material_override.get_shader_parameter("tint")
			sides[String(c.name).get_slice("_", 2)] = true
			if tint.a >= 0.99:
				opaque += 1
		if sides.size() < 4 or opaque < 4:
			_fail("%s: fog curtains on %d sides, %d opaque (want 4 and 4)" % [mname, sides.size(), opaque])
		var env: Environment = (arena.get_node("WorldEnvironment") as WorldEnvironment).environment
		if env.fog_enabled and not curtains.is_empty():
			var t: Color = (curtains[0] as MeshInstance3D).material_override.get_shader_parameter("tint")
			if not Color(t.r, t.g, t.b).is_equal_approx(Color(env.fog_light_color.r, env.fog_light_color.g, env.fog_light_color.b)):
				_fail("%s: curtains %s, the map's fog %s" % [mname, t, env.fog_light_color])
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	print("[probe] fog_edges done")
	get_tree().quit(0)
