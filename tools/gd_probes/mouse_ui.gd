extends Node
# T497 / T498 probe (HUMAN_FOUND 2026-11-19: "In multiplayer, mouse is not freed to pick spawnpoints or
# exit the results screen. Sometimes." / "Back to lobby doesn't work."): with the mech picker, the spawn
# picker or the results screen up, a possess (a human input source attached: what took the pointer)
# leaves the mouse free; the results screen frees a captured mouse; closing the pickers captures again.

func _fail(msg: String) -> void:
	push_error("[probe] mouse_ui FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 3:
		await get_tree().process_frame
	var hud: Node = arena.get("hud")
	if not arena.get("_start_pick_open"):
		_fail("no start pick to test with")
		return
	var bad: Array = []
	var me: Node = arena.get("player_mech")
	var human: Node = load("res://scripts/PlayerInputSource.gd").new()
	add_child(human)
	hud.squad_slot_selected.emit(0)  # the mech picker hands over to the spawn picker
	await get_tree().process_frame
	me.call("set_input_source", human)  # a possess while the spawn picker is up
	if Game.get("_want_captured"):
		bad.append("a possess captured the mouse under the spawn picker")
	hud.spawn_selected.emit(0)  # picked: the pickers close, the mech is ours
	await get_tree().process_frame
	if not Game.get("_want_captured"):
		bad.append("the mouse stayed free after the spawn pick (playing)")
	hud.show_result_mp(0, [])
	if Game.get("_want_captured"):
		bad.append("the results screen left the mouse captured (BACK TO LOBBY unclickable)")
	me.call("set_input_source", human)  # a late possess at match end
	if Game.get("_want_captured"):
		bad.append("a possess captured the mouse under the results screen")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] mouse_ui done")
	get_tree().quit(0)
