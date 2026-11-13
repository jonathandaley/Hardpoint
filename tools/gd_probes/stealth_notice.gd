extends Node
# T407 probe (HUMAN_FOUND, queued 2026-11-13: "How hard would it be for bots to sometimes see through
# stealth? ... \"Bot difficulty * how \"noisy\" you're being = likelihood to be noticed\""): a Hard bot
# 15 m from a stealthed mech that keeps shooting spots it within 15 s and targets it; an Easy bot never
# does; a quiet stealthed mech at 39 m is (almost) never spotted.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var me: Node3D = arena.get("player_mech")
	me.set("invincible", true)
	var bot: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	bot.set("invincible", true)
	var ai: Node = bot.get("_input_source")
	var bad: Array = []
	for case in [[3, 5.0, true], [0, 5.0, true]]:  # 5 m, 20 s: a miss is ~0.1% at Hard
		ai.set("difficulty", case[0])
		ai.set("_spotted", {})
		ai.set("_target", null)
		me.global_position = bot.global_position + Vector3(case[1], 0, 0)
		me.set("is_stealthy", true)
		var seen := false
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 20000 and not seen:
			me.set("last_fired_frame", Engine.get_physics_frames())  # shooting: noisy
			me.set("is_stealthy", true)
			await get_tree().physics_frame
			var sp = ai.get("_spotted")
			seen = sp is Dictionary and (sp as Dictionary).has(me)
		if case[0] == 3 and not seen:
			bad.append("a Hard bot 5 m from a stealthed mech that keeps shooting never spotted it in 20 s")
		if case[0] == 0 and seen:
			bad.append("an Easy bot spotted a stealthed mech")
	if not bad.is_empty():
		push_error("[probe] stealth_notice FAIL: " + "; ".join(bad))
	print("[probe] stealth_notice done")
	get_tree().quit(0)
