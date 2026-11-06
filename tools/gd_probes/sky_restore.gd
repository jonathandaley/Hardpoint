extends Node
# T320 probe: Factory recolours the arena's own Sky (a new Sky leaked two radiance maps at exit
# in the compatibility renderer -- checked under Xvfb, not visible headless). That Sky is shared
# through the resource cache, so a later match on another map must get its own colours back.

func _fail(msg: String) -> void:
	push_error("[probe] sky_restore FAIL: " + msg)
	get_tree().quit(1)

func _top(map: String) -> Color:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 1]
	Game.loadout["mode"] = "beacons"
	Game.loadout["map_def"] = load("res://resources/maps/%s.tres" % map)
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 3:
		await get_tree().process_frame
	var env: Environment = (arena.get_node("WorldEnvironment") as WorldEnvironment).environment
	var c: Color = (env.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	arena.queue_free()
	for i in 3:
		await get_tree().process_frame
	return c

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var before: Color = await _top("MathTemple")
	var factory: Color = await _top("Factory")
	var after: Color = await _top("MathTemple")
	if factory.is_equal_approx(before):
		_fail("Factory didn't get its own sky (%s)" % factory)
		return
	if not after.is_equal_approx(before):
		_fail("after Factory, MathTemple's sky top is %s, was %s (Factory's leaked into the shared Sky)" % [after, before])
		return
	print("[probe] sky_restore done (factory %s, others %s)" % [factory.to_html(false), before.to_html(false)])
	get_tree().quit(0)
