extends Node
# T373 probe (HUMAN_FOUND 2026-11-09: "energy shield health visible to every peer: a blue bar under
# the health bar"): an enemy with an energy shield shows a blue bar right under its over-head health
# bar, as long as its pool; one without a shield shows none. A shield sync (a hit on the server)
# holds the client's regen like the server's.

func _fail(msg: String) -> void:
	push_error("[probe] shield_bars FAIL: " + msg)

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
	var enemy: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	enemy.invincible = true
	var stop: Node = load("res://scripts/InputSource.gd").new()  # inert: the enemy stands still
	add_child(stop)
	enemy.call("set_input_source", stop)
	var cam: Camera3D = me.get("camera")
	enemy.global_position = cam.global_position + (-cam.global_transform.basis.z * Vector3(1, 0, 1)).normalized() * 18.0
	enemy.global_position.y = me.global_position.y
	var es: Node = enemy.get_node("EnergyShield")
	var hud: Node = arena.get("hud")
	if not es.get("_active"):  # no shield on this mech: none drawn
		for i in 5:
			await get_tree().process_frame
		for r in hud.find_children("ShieldBar", "ColorRect", true, false):
			if r.visible:
				_fail("a shield bar shows for a mech without a shield")
		enemy.call("configure_energy_shield", true, 200.0, 10.0, 5.0)
	es.set("shield_hp", float(es.max_shield_hp) * 0.5)
	es.set("_regen_timer", 60.0)
	for i in 5:
		await get_tree().process_frame
	var bars: Array = hud.get("_bot_bg_bars")
	var bg: ColorRect = bars[0] if not bars.is_empty() else null
	var fill: ColorRect = null
	for r in hud.find_children("ShieldBar", "ColorRect", true, false):
		if r.visible:
			fill = r
	if bg == null or not bg.visible:
		_fail("no enemy health bar shown")
	elif fill == null:
		_fail("no shield bar under a shielded enemy's health bar")
	else:
		var w_bg := bg.offset_right - bg.offset_left
		if absf(fill.offset_top - bg.offset_bottom) > 0.5 or absf(fill.offset_left - bg.offset_left) > 0.5:
			_fail("shield bar at %s, health bar at %s (want right under it)" % [fill.get_rect(), bg.get_rect()])
		if absf((fill.offset_right - fill.offset_left) - w_bg * 0.5) > 1.0:
			_fail("shield bar %.1f px for a half-full shield (health bar %.1f)" % [fill.offset_right - fill.offset_left, w_bg])
	# a sync (= a hit on the server) holds the regen
	es.set("_regen_timer", 0.0)
	enemy.call("_sync_shield", 40.0)
	for i in 30:
		await get_tree().process_frame
	if float(es.shield_hp) > 40.5:
		_fail("shield regenerated to %.1f right after a synced hit (regen delay %.1f s)" % [float(es.shield_hp), float(es.regen_delay)])
	print("[probe] shield_bars done")
	get_tree().quit(0)
