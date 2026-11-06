extends Node
# T251 probe (HUMAN_FOUND_ISSUES 2026-11-05: "Bot fill should be optional in singleplayer,
# including # of bots"): the SP map step sets ally and enemy bot counts; a match started
# with 0 / 0 has just the player, with 2 / 3 has 3 on the player's side and 3 enemies; the
# counts are kept in the loadout for next time.

func _fail(msg: String) -> void:
	push_error("[probe] sp_bots: " + msg)

func _start(ally: int, enemy: int) -> Node:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	get_tree().current_scene = h  # the SP start replaces the hangar, not this probe
	(h.get_node("MatchmakingButton") as Button).pressed.emit()
	(h.get_node("FindMatchPanel/Choices/SinglePlayerBtn") as Button).pressed.emit()
	await get_tree().process_frame
	var box: Node = h.get_node("FindMatchPanel/MapChoices")
	(box.find_child("AllyBots", true, false) as SpinBox).value = ally
	(box.find_child("EnemyBots", true, false) as SpinBox).value = enemy
	(box.find_child("Map0", true, false) as Button).pressed.emit()
	(box.find_child("SpPlay", true, false) as Button).pressed.emit()  # T277: a pick only selects
	for i in 6:
		await get_tree().process_frame
	return get_tree().current_scene

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var got := []
	for case in [[0, 0], [2, 3]]:
		var arena: Node = await _start(case[0], case[1])
		var tm = arena.get("_team_mechs") if arena != null else null
		if tm == null:
			_fail("no arena after picking a map (%s)" % arena)
			break
		var me_team: int = int(arena.get("player_mech").get("team")) if arena.get("player_mech") != null else 0
		var own: int = (tm[me_team] as Array).size()
		var opp: int = (tm[1 - me_team] as Array).size()
		got.append("%d/%d -> %d v %d" % [case[0], case[1], own, opp])
		if own != 1 + int(case[0]) or opp != int(case[1]):
			_fail("ally %d / enemy %d bots gave %d on our side, %d enemies (want %d, %d)" % [case[0], case[1], own, opp, 1 + case[0], case[1]])
		if Game.loadout.get("sp_bots") != [case[0], case[1]]:
			_fail("the counts weren't kept in the loadout (%s)" % [Game.loadout.get("sp_bots")])
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	print("[probe] sp_bots done (%s)" % ", ".join(got))
	get_tree().quit(0)
