extends Node
# T285 probe (user 2026-11-05: "Death match just runs each team out of lives. No score at all
# beyond last man standing" + a match timer; time-out: more mechs left wins, equal = draw):
# a death match has no beacons and no score bars, shows the match clock, a legacy (Easy..Medium)
# bot with nothing in sight still goes hunting, and at the limit the team with more mechs left
# (alive + unspent squad = Player.lives) wins -- equal ends it as a draw (-1, "DRAW").

func _fail(msg: String) -> void:
	push_error("[probe] deathmatch FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.loadout["mode"] = "beacons"
	# through the SP picker: DEATH MATCH ticked, 0 allies / 1 enemy
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	get_tree().current_scene = h  # the SP start replaces the hangar, not this probe
	(h.get_node("MatchmakingButton") as Button).pressed.emit()
	(h.get_node("FindMatchPanel/Choices/SinglePlayerBtn") as Button).pressed.emit()
	await get_tree().process_frame
	var box: Node = h.get_node("FindMatchPanel/MapChoices")
	(box.find_child("AllyBots", true, false) as SpinBox).value = 0
	(box.find_child("EnemyBots", true, false) as SpinBox).value = 1
	var dm: CheckBox = box.find_child("SpDeathMatch", true, false)
	if dm == null:
		_fail("no DEATH MATCH option in the SP picker")
		return
	dm.button_pressed = true
	(box.find_child("SpPlay", true, false) as Button).pressed.emit()
	for i in 6:
		await get_tree().process_frame
	var arena: Node = get_tree().current_scene
	if arena == null or arena.get("match_node") == null:
		_fail("no arena after PLAY (%s)" % arena)
		return
	if not get_tree().get_nodes_in_group("beacons").is_empty():
		_fail("beacons in a death match")
		return
	var mn: Node = arena.get("match_node")
	if float(mn.get("time_limit")) != 900.0:
		_fail("death match limit %.0f s, the user picked 15:00 (T338)" % float(mn.get("time_limit")))
		return
	var hud: Node = arena.get("hud")
	if arena.get("_start_pick_open"):
		hud.squad_slot_selected.emit(0)
		hud.spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	for bar in hud.get("_score_bars"):
		if (bar["fg"] as Control).visible or (bar["bg"] as Control).visible:
			_fail("score bars shown in a death match")
			return
	var clock = hud.get("_clock_label")
	if clock == null or not (clock as Label).visible or not (clock as Label).text.contains(":"):
		_fail("no match clock on the HUD (%s)" % ("missing" if clock == null else "'%s'" % clock.text))
		return
	# a legacy bot with no target and no beacon moves toward the enemy
	var bot: Node = null
	for ai in get_tree().get_nodes_in_group("ai_input_sources"):
		if is_instance_valid(ai.get_parent()) and ai.get_parent().get("pawn") != null:
			bot = ai
	if bot == null:
		_fail("no bot")
		return
	var bm: Node3D = bot.get_parent().get("pawn")
	var mv: Vector2 = bot.call("_legacy_move", bm, false, INF, 1.0, 0.016)
	if mv == Vector2.ZERO:
		_fail("a legacy bot stands still with no beacon to go to")
		return
	# time-out: more mechs left wins
	var players: Array = arena.get("_players")
	for p in players:
		p.set("lives", 3 if p.get("team") == 0 else 2)
	if int(mn.get("time_out_winner").call()) != 0:
		_fail("team 0 has more mechs left but doesn't win the time-out")
		return
	for p in players:
		p.set("lives", 2)
	var won := [99]
	mn.match_ended.connect(func(w: int) -> void: won[0] = w)
	mn.set("elapsed", float(mn.get("time_limit")) + 1.0)
	for i in 30:
		await get_tree().physics_frame
	if won[0] != -1:
		_fail("equal mechs left at the time limit ended %s, not a draw" % str(won[0]))
		return
	for i in 10:
		await get_tree().process_frame
	var header: Label = null
	for l in hud.find_children("*", "Label", true, false):
		if (l as Label).text == "DRAW":
			header = l
	if header == null:
		_fail("the result screen doesn't say DRAW")
		return
	print("[probe] deathmatch done")
	get_tree().quit(0)
