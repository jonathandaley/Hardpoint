extends Node
# B138 probe (bot_lock@bad server log: "Invalid access of index '3'" in Arena._on_bot_mech_died): a
# bot's respawn waits BOT_RESPAWN_S, and the match's roster can be replaced meanwhile (match over,
# back to the lobby); the respawn then read a roster entry that was gone. It must just stand down.
# (A script error in the coroutine fails this probe through the suite's crash_scan.)

class RacePilot extends Node:
	var lives := 3

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 2
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var roster: Array = Game.mp_active_match["roster"]
	var bp := RacePilot.new()
	add_child(bp)
	arena.call("_on_bot_mech_died", bp, roster.size() - 1)  # the last roster entry dies...
	Game.mp_active_match["roster"] = [roster[0]]            # ...and the roster shrinks before its respawn
	for i in 260:  # past BOT_RESPAWN_S (3 s)
		await get_tree().physics_frame
	Game.mp_active_match["roster"] = roster
	print("[probe] bot_respawn_race done")
	get_tree().quit(0)
