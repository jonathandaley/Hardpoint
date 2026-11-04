extends Node
# T225 probe: on the swamp map a mech standing in the water moves at Swamp.WADE of its
# speed, and at full speed again once it's back on dry ground (spawn pad).

func _fail(msg: String) -> void:
	push_error("[probe] swamp_wade: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Swamp.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 20:
		await get_tree().physics_frame
	var m: Node3D = arena.get("player_mech")
	var map: Node = arena.get("_map")
	var full := float(m.get("walk_speed"))
	if absf(float(m.get("terrain_speed")) - 1.0) > 0.001:
		_fail("slowed on the dry spawn pad (terrain_speed %s)" % m.get("terrain_speed"))
	var wet := Vector2(-60, 0)  # open water: away from every hummock, pad and boardwalk
	m.global_position = Vector3(wet.x, map.call("ground_y", wet.x, wet.y) + 0.2, wet.y)
	for i in 20:
		await get_tree().physics_frame
	var wade := float(m.get("walk_speed"))
	var want: float = map.get_script().get_script_constant_map()["WADE"]
	if absf(wade / full - want) > 0.01:
		_fail("in the water walk_speed is %.2f of dry (want %.2f)" % [wade / full, want])
	print("[probe] swamp_wade done (dry %.2f, wading %.2f)" % [full, wade])
	get_tree().quit(0)
