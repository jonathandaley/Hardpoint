extends Node
# T234 probe (HUMAN_FOUND_ISSUES 2026-11-04: keep the flight deck, rename it "Factory",
# burnt orange-red sky): the map is listed as Factory (no Flight Deck left in the Hangar /
# Lobby lists) and its sky is a warm orange-red, not the starfield.

func _fail(msg: String) -> void:
	push_error("[probe] factory_map: " + msg)

func _ready() -> void:
	var md: Resource = load("res://resources/maps/Factory.tres")
	if md == null or md.map_name != "Factory":
		_fail("no Factory MapDef (%s)" % md)
		get_tree().quit(0)
		return
	var hangar_maps: Array = load("res://scripts/Hangar.gd").get_script_constant_map()["MAPS"]
	var lobby_maps: Array = load("res://scripts/Lobby.gd").get_script_constant_map()["_MAP_OPTIONS"]
	if not hangar_maps.has(md.resource_path) or lobby_maps.filter(func(o): return o["path"] == md.resource_path).is_empty():
		_fail("Factory missing from the Hangar / Lobby map lists")
	if str(hangar_maps).contains("FlightDeck") or str(lobby_maps).contains("Flight"):
		_fail("a Flight Deck entry is still listed")
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = md
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 3:
		await get_tree().process_frame
	var env: Environment = (arena as Node3D).get_world_3d().environment
	if env == null:
		var we := arena.find_children("*", "WorldEnvironment", true, false)
		env = (we[0] as WorldEnvironment).environment if we.size() > 0 else null
	var sky_mat: Material = env.sky.sky_material if env != null and env.sky != null else null
	if not (sky_mat is ProceduralSkyMaterial):
		_fail("Factory sky is %s, want the orange-red procedural sky" % sky_mat)
	else:
		var h: Color = (sky_mat as ProceduralSkyMaterial).sky_horizon_color
		if not (h.r > 0.6 and h.g < h.r * 0.6 and h.b < h.g):
			_fail("Factory horizon %s is not burnt orange-red" % h)
	print("[probe] factory_map done")
	get_tree().quit(0)
