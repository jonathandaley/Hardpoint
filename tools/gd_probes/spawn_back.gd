extends Node
# T322 probe (HUMAN_FOUND 2026-11-05: "During a match, the spawnpoint picker should have a back
# button that goes back to the mech picker"): after picking a mech, the spawn picker has BACK;
# BACK closes it, reopens the mech picker and drops the pending pick; picking again still works.

func _fail(msg: String) -> void:
	push_error("[probe] spawn_back FAIL: " + msg)
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
	hud.squad_slot_selected.emit(0)
	await get_tree().process_frame
	var back := hud.find_child("SpawnBack", true, false) as Button
	if back == null:
		_fail("the spawn picker has no BACK button")
		return
	back.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var picker = hud.get("_squad_picker")
	if picker == null or not is_instance_valid(picker) or picker.is_queued_for_deletion():
		_fail("BACK didn't reopen the mech picker")
		return
	if hud.find_child("Spawn0", true, false) != null and not hud.find_child("Spawn0", true, false).is_queued_for_deletion():
		_fail("the spawn picker is still up after BACK")
		return
	if int(arena.get("_pending_slot")) != -1:
		_fail("BACK left the mech pick pending")
		return
	hud.squad_slot_selected.emit(0)
	hud.spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	if arena.get("_start_pick_open"):
		_fail("picking again after BACK didn't start the match")
		return
	print("[probe] spawn_back done")
	get_tree().quit(0)
