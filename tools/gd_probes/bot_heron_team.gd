extends Node
# T520(d) probe (user: bots "do a good job of targeting healers, but not of staying close to their
# own"): with team play (Medium+), a hurt bot (< 60%) keeps to a friendly Heron within 60 m -- with
# nothing to fight it walks to it -- a healthy one doesn't care, and a Heron keeps to the middle of its
# team. Easy / Normal (no team play) ignore all this.

func _fail(msg: String) -> void:
	push_error("[probe] bot_heron_team FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 3
	Game.loadout["mode"] = "deathmatch"
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 20:
		await get_tree().physics_frame
	var t1: Array = arena.get("_team_mechs")[1]
	var heron: Node3D = t1[0]
	var hurt: Node3D = t1[1]
	heron.call("configure_abilities", [load("res://resources/abilities/FieldRepair.tres")])
	var ai := {}
	for a in get_tree().get_nodes_in_group("ai_input_sources"):
		if a.get_parent() != null and a.get_parent().get("pawn") in [heron, hurt]:
			ai[a.get_parent().get("pawn")] = a
			a.set("difficulty", 4)
	var ha: Node = ai.get(hurt)
	var ra: Node = ai.get(heron)
	if ha == null or ra == null:
		_fail("setup: no AI on the two team-1 bots")
		return
	hurt.global_position = heron.global_position + Vector3(40, 0, 0)
	var bad: Array = []
	var anchor: Vector3 = ha.call("_heal_anchor", hurt, 0.4)
	if anchor.distance_to(heron.global_position) > 0.01:
		bad.append("a hurt bot 40 m from a Heron keeps to %s, not the Heron" % anchor)
	if (ha.call("_heal_anchor", hurt, 1.0) as Vector3).x != INF:
		bad.append("a healthy bot keeps to a Heron")
	# nothing to fight: the move goes toward the Heron
	var mv: Vector2 = ha.call("_tactical_move", hurt, false, INF, 60.0, null, 0.4, 1.0 / 60.0)
	var want: Vector2 = ha.call("_to_move", hurt, heron.global_position - hurt.global_position)
	if mv.dot(want) < 0.7:
		bad.append("a hurt bot with nothing to fight moves %s, toward the Heron is %s" % [mv, want])
	var mid: Vector3 = ra.call("_heal_anchor", heron, 1.0)
	var want_mid: Vector3 = ra.call("_allies_middle", heron)
	if mid.x == INF or mid.distance_to(want_mid) > 0.01:
		bad.append("the Heron keeps to %s, not its team's middle %s" % [mid, want_mid])
	ha.set("difficulty", 1)
	if (ha.call("_heal_anchor", hurt, 0.4) as Vector3).x != INF:
		bad.append("a Normal bot (no team play) keeps to a Heron")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] bot_heron_team done")
	get_tree().quit(0)
