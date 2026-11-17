extends Node
# T346 probe (GL texture leak at exit, 4 x 349524 B = two skies' 256 px radiance maps, after playing
# Factory): Factory's red sky is its own Sky -- the arena scene's shared Sky (cached in Arena.tscn)
# keeps its material through a Factory match. Factory used to swap the shared Sky's material and swap
# it back in _exit_tree, i.e. during teardown.

func _shared_sky() -> Sky:
	var st: SceneState = (load("res://scenes/arena/Arena.tscn") as PackedScene).get_state()
	for n in st.get_node_count():
		if String(st.get_node_name(n)) == "WorldEnvironment":
			for p in st.get_node_property_count(n):
				if String(st.get_node_property_name(n, p)) == "environment":
					return (st.get_node_property_value(n, p) as Environment).sky
	return null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sky := _shared_sky()
	if sky == null:
		push_error("[probe] factory_sky FAIL: no WorldEnvironment sky in Arena.tscn")
		get_tree().quit(1)
		return
	var mat_before: Material = sky.sky_material
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["mode"] = "beacons"
	Game.loadout["map_def"] = load("res://resources/maps/Factory.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 3:
		await get_tree().process_frame
	var env: Environment = (arena.get_node("WorldEnvironment") as WorldEnvironment).environment
	var bad: Array = []
	if sky.sky_material != mat_before:
		bad.append("Factory changed the arena scene's shared Sky material")
	if env.sky == sky:
		bad.append("Factory's environment still uses the shared Sky")
	if not env.sky.sky_material is ProceduralSkyMaterial or (env.sky.sky_material as ProceduralSkyMaterial).sky_top_color != Color("#5e1a0c"):
		bad.append("Factory's sky isn't its red one")
	if not bad.is_empty():
		push_error("[probe] factory_sky FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] factory_sky done")
	get_tree().quit(0)
