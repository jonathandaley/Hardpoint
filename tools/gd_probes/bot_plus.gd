extends Node
# T520(e) probe -- BOTS+ (Settings SMARTER ELITES, Elite bots only): the switch; an incoming explosive
# shot on a collision course gets a sidestep, one passing 10 m off doesn't; between two neutral beacons
# the nearer one with 3 enemies on it and nobody of ours headed there loses to the free one (without
# Bots+ the nearer one wins).

func _fail(msg: String) -> void:
	push_error("[probe] bot_plus FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
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
	for i in 20:
		await get_tree().physics_frame
	var bot_m: Node3D = arena.get("_team_mechs")[1][0]
	var foes: Array = arena.get("_team_mechs")[0]
	var ai: Node = null
	for a in get_tree().get_nodes_in_group("ai_input_sources"):
		if a.get_parent() != null and a.get_parent().get("pawn") == bot_m:
			ai = a
	if ai == null:
		_fail("setup: no AI")
		return
	var bad: Array = []
	ai.set("difficulty", 4)
	Game.settings["bots_plus"] = false
	if ai.call("_plus"):
		bad.append("Bots+ on with the setting off")
	Game.settings["bots_plus"] = true
	ai.set("difficulty", 3)
	if ai.call("_plus"):
		bad.append("Bots+ on for a Hard bot")
	ai.set("difficulty", 4)
	if not ai.call("_plus"):
		bad.append("Bots+ off for an Elite with the setting on")
	# dodge: a rocket 20 m off flying at the bot / one aimed 10 m to the side
	var shot: Node3D = load("res://scenes/weapons/ProjectileGrey.tscn").instantiate()
	shot.set("explode", true)
	shot.set("team", 0)
	shot.set("speed", 30.0)
	arena.add_child(shot)
	shot.set_physics_process(false)
	var at := bot_m.global_position + Vector3.UP
	shot.global_position = at + Vector3(20, 0, 0)
	shot.look_at(at)
	ai.set("_dodge_t", 0.0)
	ai.call("_check_dodge", bot_m)
	if float(ai.get("_dodge_t")) <= 0.0:
		bad.append("no sidestep from a rocket 20 m off on a collision course")
	shot.look_at(at + Vector3(0, 0, 10))
	ai.set("_dodge_t", 0.0)
	ai.call("_check_dodge", bot_m)
	if float(ai.get("_dodge_t")) > 0.0:
		bad.append("sidestepped a rocket passing 10 m off")
	shot.queue_free()
	# beacons: b0 30 m off with 3 enemies on it, b1 33 m off and free; the rest far away
	var bs: Array = get_tree().get_nodes_in_group("beacons")
	for i in bs.size():
		bs[i].set("owner_team", -1)
		(bs[i] as Node3D).global_position = bot_m.global_position + Vector3(0, 0, 500 + i * 50)
	(bs[0] as Node3D).global_position = bot_m.global_position + Vector3(30, 0, 0)
	(bs[1] as Node3D).global_position = bot_m.global_position + Vector3(-33, 0, 0)
	for i in 3:
		(foes[i] as Node3D).global_position = (bs[0] as Node3D).global_position + Vector3(0, 0, 3 * i)
	ai.set("role", "attacker")
	ai.set("_claimed_beacon", null)
	var with_plus = ai.call("_pick_target_beacon", bot_m)
	Game.settings["bots_plus"] = false
	var without = ai.call("_pick_target_beacon", bot_m)
	if without != bs[0]:
		bad.append("setup: without Bots+ the nearer beacon should win (got %s)" % without)
	if with_plus != bs[1]:
		bad.append("Bots+ walked toward the beacon 3 enemies hold (got %s)" % with_plus)
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] bot_plus done")
	get_tree().quit(0)
