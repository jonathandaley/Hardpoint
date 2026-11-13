extends Node
# T379 probe (HUMAN_FOUND 2026-11-09: "TAB sometimes starts spectating from a mech ... It's happened
# a couple of times"): after one death (the camera spectates a teammate) and a respawn into the next
# mech, TAB no longer cycles spectating -- the spectator rig outlived the respawn and TAB checked
# only that it existed. While spectating, TAB still cycles.

func _fail(msg: String) -> void:
	push_error("[probe] tab_spectate FAIL: " + msg)

func _tab() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 3
	Game.loadout["mode"] = "beacons"
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = true
	var me: Node = arena.get("player_mech")
	me.invincible = false
	me.call("_apply_damage", 1e9)  # die: the camera goes to a teammate
	for i in 120:
		await get_tree().physics_frame
	var spec: Camera3D = arena.get("_spec_cam")
	if spec == null or arena.get("_spectated_mech") == me:
		_fail("not following a teammate after dying (setup)")
	else:
		var first: Node = arena.get("_spectated_mech")
		_tab()
		for i in 3:
			await get_tree().process_frame
		if arena.get("_spectated_mech") == first:
			_fail("TAB doesn't cycle while spectating")
	arena.get("hud").squad_slot_selected.emit(1)  # back in, in the next squad mech
	arena.get("hud").spawn_selected.emit(0)
	for i in 30:
		await get_tree().physics_frame
	var mine: Node = arena.get("player_mech")
	if mine == me or mine == null or mine.get("is_dead"):
		_fail("no respawn into the next mech (setup)")
	else:
		var cam := get_viewport().get_camera_3d()
		_tab()
		for i in 3:
			await get_tree().process_frame
		if get_viewport().get_camera_3d() != cam or (spec != null and spec.current):
			_fail("TAB in a mech switched the camera to spectating %s" % arena.get("_spectated_mech"))
	print("[probe] tab_spectate done")
	get_tree().quit(0)
