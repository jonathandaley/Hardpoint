extends Node
# T520(b) probe (user: Elites "Should be using jump to get to beacons faster" -- "ignore ledges"): a
# Pegasus bot with nothing to fight, healthy and moving, hops toward its claimed beacon when it's 35 m+
# away -- not when close, hurt, standing, or with a target (the 16 s jump-heal stays for fights).

func _fail(msg: String) -> void:
	push_error("[probe] bot_jump_travel FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 2
	Game.loadout["mode"] = "beacons"
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:
		if int(e["peer_id"]) == 0:
			e["squad"] = [{"mech": "res://resources/mechs/Pegasus.tres", "weapons": []}]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 20:
		await get_tree().physics_frame
	var bot_m: Node3D = arena.get("_team_mechs")[1][0]
	var ai: Node = null
	for a in get_tree().get_nodes_in_group("ai_input_sources"):
		if a.get_parent() != null and a.get_parent().get("pawn") == bot_m:
			ai = a
	if ai == null or not ai.has_method("jump_travel_wanted") or not (bot_m as CharacterBody3D).is_on_floor():
		_fail("setup: no AI with jump_travel_wanted, or the bot isn't standing")
		return
	var b := Node3D.new()
	arena.add_child(b)
	b.global_position = bot_m.global_position + Vector3(60, 0, 0)
	ai.set("_claimed_beacon", b)
	ai.set("_move_dir", Vector2(0, -1))
	var bad: Array = []
	if not ai.call("jump_travel_wanted", bot_m, false, 1.0):
		bad.append("no hop 60 m from its beacon")
	if ai.call("jump_travel_wanted", bot_m, true, 1.0):
		bad.append("hopped with a target")
	if ai.call("jump_travel_wanted", bot_m, false, 0.5):
		bad.append("hopped while hurt (50%)")
	b.global_position = bot_m.global_position + Vector3(20, 0, 0)
	if ai.call("jump_travel_wanted", bot_m, false, 1.0):
		bad.append("hopped 20 m from its beacon")
	b.global_position = bot_m.global_position + Vector3(60, 0, 0)
	ai.set("_move_dir", Vector2.ZERO)
	if ai.call("jump_travel_wanted", bot_m, false, 1.0):
		bad.append("hopped standing still")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] bot_jump_travel done")
	get_tree().quit(0)
