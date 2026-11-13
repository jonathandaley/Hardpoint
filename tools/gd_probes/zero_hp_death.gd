extends Node
# B139 probe (bot_lock lock_target 2026-11-13: a mech "locked while dead" -- its health was 1.8 -> 0.9 ->
# ~1e-16 from three 0.9 arc ticks: float rounding left a sliver above 0, so `health <= 0` didn't fire,
# the mech kept shooting at "0 HP" until the next hit): hits that add up to the health kill.

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
	var me: Node = arena.get("player_mech")
	var bad: Array = []
	for start in [2.7, 1.8, 3.3, 9.9]:
		var enemy: Node = null
		for m in arena.get("_team_mechs")[1 - int(me.get("team"))]:
			if is_instance_valid(m) and not m.get("is_dead"):
				enemy = m
		if enemy == null:
			break
		enemy.invincible = false
		enemy.set("health", start)
		var hits := 0
		while not enemy.get("is_dead") and hits < 20:
			enemy.call("_apply_damage", 0.3 if start == 3.3 else 0.9, null)
			hits += 1
		var want := int(round(start / (0.3 if start == 3.3 else 0.9)))
		if hits != want:
			bad.append("%.1f HP took %d hits of %.1f, want %d (left %s)" % [start, hits, 0.3 if start == 3.3 else 0.9, want, enemy.get("health")])
		for i in 3:
			await get_tree().physics_frame
	if not bad.is_empty():
		push_error("[probe] zero_hp_death FAIL: " + "; ".join(bad))
	print("[probe] zero_hp_death done")
	get_tree().quit(0)
