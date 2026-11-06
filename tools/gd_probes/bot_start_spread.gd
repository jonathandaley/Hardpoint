extends Node
# T281 probe (HUMAN_FOUND 2026-11-05: "Bots should pick spawnpoints instead of all spawning
# together"): at match start a team's bots stand at more than one of the team's spawn points
# (round-robin), each within reach of a spawn point; the human starts at the first spawn.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 4
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 3:
		await get_tree().process_frame
	var bad: Array = []
	for t in 2:
		var pts: Array = arena.spawn_points(t)
		var used := {}
		for m in arena.get("_team_mechs")[t]:
			if int(m.get("owner_peer_id")) != 0:
				continue
			var best := -1
			var bd := INF
			for i in pts.size():
				var d: float = Vector2(m.global_position.x - pts[i].x, m.global_position.z - pts[i].z).length()
				if d < bd:
					bd = d
					best = i
			if bd > 15.0:
				bad.append("team %d bot %s is %.0f m from any spawn" % [t, m.name, bd])
			used[best] = true
		if pts.size() > 1 and used.size() < 2:
			bad.append("team %d: every bot started at spawn %s (of %d)" % [t, used.keys(), pts.size()])
	if not bad.is_empty():
		push_error("[probe] bot_start_spread FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] bot_start_spread done")
	get_tree().quit(0)
