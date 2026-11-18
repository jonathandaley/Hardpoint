extends Node
# T471 probe (HUMAN_FOUND 2026-11-18: "Too easy to double-click the spawnpoint and respawn
# immediately."): a spawn button pressed right after the picker opens (the second half of the
# double-click that chose the mech) does nothing; pressed after SPAWN_ARM_MS it spawns.

func _fail(msg: String) -> void:
	push_error("[probe] spawn_arm FAIL: " + msg)
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
	var picked: Array = []
	hud.spawn_selected.connect(func(i: int) -> void: picked.append(i))
	hud.squad_slot_selected.emit(0)
	await get_tree().process_frame
	var b := hud.find_child("Spawn0", true, false) as Button
	if b == null:
		_fail("the spawn picker has no spawn button")
		return
	b.pressed.emit()  # the double-click's second half
	if not picked.is_empty():
		_fail("a press right after the picker opened spawned at once (the double-click's second half)")
		return
	var arm_ms: int = hud.get_script().get_script_constant_map()["SPAWN_ARM_MS"]
	await get_tree().create_timer(arm_ms / 1000.0 + 0.1, true, false, true).timeout
	if not is_instance_valid(b) or b.is_queued_for_deletion():
		_fail("the spawn picker closed on the early press")
		return
	b.pressed.emit()
	if picked != [0]:
		_fail("a press after the arm delay didn't spawn (%s)" % str(picked))
		return
	print("[probe] spawn_arm done")
	get_tree().quit(0)
