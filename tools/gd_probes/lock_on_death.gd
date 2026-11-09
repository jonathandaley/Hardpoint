extends Node
# B128 probe (bot_lock@wifi lock_target: "Mech_1_2 locks dead 'Mech_0_1' (hp 0.0) at tick 3659"): a
# mech locked onto another drops the lock the moment its target dies -- the same frame, not on its
# next lock update (the kill can land after that update within one tick).

func _fail(msg: String) -> void:
	push_error("[probe] lock_on_death FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["mode"] = "deathmatch"
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	var foe: Node = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	foe.set("invincible", false)
	me.call("_set_locked_target", foe)
	me.set("lock_progress", 1.0)
	foe.call("take_damage", 99999.0, null)
	if not foe.get("is_dead"):
		_fail("the target didn't die")
		return
	if me.get("locked_target") != null:
		_fail("still locked on the wreck right after the kill")
		return
	print("[probe] lock_on_death done")
	get_tree().quit(0)
