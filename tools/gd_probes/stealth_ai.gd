extends Node
# T295 probe (HUMAN_FOUND 2026-11-05 late: "Cesh bots should use stealth more intelligently"):
# a Cesh bot cloaks to close on a target out of range, when it's locked (or a lock is building on
# it), when hurt, and to cross 25-90 m to a beacon its team doesn't hold -- not while trading
# shots in range at full health with nobody locking it (before: any fight).

func _fail(msg: String) -> void:
	push_error("[probe] stealth_ai FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.settings["bot_difficulty"] = 3  # Hard: abilities on
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 1]
	Game.loadout["mode"] = "beacons"
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:
		if int(e["peer_id"]) == 0:
			e["squad"] = [{"mech": "res://resources/mechs/Cesh.tres", "weapons": []}]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	var bot_m: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	var ai: Node = null
	for a in get_tree().get_nodes_in_group("ai_input_sources"):
		if a.get_parent() != null and a.get_parent().get("pawn") == bot_m:
			ai = a
	if ai == null or not ai.has_method("stealth_wanted"):
		_fail("no stealth decision on the Cesh bot's AI")
		return
	var rng := 60.0
	var cases := [
		["trading shots in range, full health, no lock", true, 40.0, 1.0, false],
		["target 1.5x out of range (close in)", true, 90.0, 1.0, true],
		["hurt (35%) with a target", true, 40.0, 0.35, true],
	]
	for c in cases:
		var got: bool = ai.call("stealth_wanted", bot_m, c[1], c[2], rng, c[3])
		if got != c[4]:
			_fail("%s: cloak %s, want %s" % [c[0], got, c[4]])
			return
	me.set("locked_target", bot_m)
	if not ai.call("stealth_wanted", bot_m, true, 40.0, rng, 1.0):
		_fail("locked by the player and not cloaking")
		return
	me.set("locked_target", null)
	var b: Node3D = null
	for bb in get_tree().get_nodes_in_group("beacons"):
		if bb.get("owner_team") != bot_m.get("team"):
			b = bb
			break
	ai.set("_claimed_beacon", b)
	bot_m.global_position = b.global_position + Vector3(50, 0, 0)
	if not ai.call("stealth_wanted", bot_m, false, INF, rng, 1.0):
		_fail("no cloak for a 50 m run to a beacon it doesn't hold")
		return
	bot_m.global_position = b.global_position + Vector3(8, 0, 0)
	if ai.call("stealth_wanted", bot_m, false, INF, rng, 1.0):
		_fail("cloaked standing at the beacon (8 m) with nothing around")
		return
	print("[probe] stealth_ai done")
	get_tree().quit(0)
