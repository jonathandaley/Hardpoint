extends Node
# T264 probe (HUMAN_FOUND 2026-11-05: drops from destroyed bots; user: coins scaled by bot
# difficulty + powerups repair / ammo / damage boost / speed boost): a destroyed bot drops a
# coin worth its difficulty's value (and, at powerup_chance 1, a powerup); our mech walking
# over the coin banks it for the match result (paid with the match-end coins); every powerup
# kind does its job; the damage boost multiplies our hits; a pickup left alone expires.

func _fail(msg: String) -> void:
	push_error("[probe] bot_drops FAIL: " + msg)

func _pickups(arena: Node) -> Array:
	return arena.get_children().filter(func(n): return String(n.name).begins_with("Pickup_"))

func _walk_to(me: Node3D, p: Vector3) -> void:
	me.global_position = Vector3(p.x, me.global_position.y, p.z)
	for i in 6:
		await get_tree().physics_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 3
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
	var pid: int = int(me.get("owner_peer_id"))
	var foes: Array = arena.get("_team_mechs")[1 - int(me.get("team"))]
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = m == me
			if m != me:
				m.set_physics_process(false)  # parked, still solid
	arena.set("powerup_chance", 1.0)
	var bad := false
	# the damage boost multiplies our hits (server-side, after validation) -- on a live enemy
	# (a real hit: the weapon's own damage, within its range -- request_damage validates both)
	var gun: Node = me.get_weapons()[0]
	var dmg: float = gun.get("damage")
	(foes[0] as Node3D).global_position = me.global_position + Vector3(8, 0, 0)
	me.call("_rpc_boost", "damage", 5.0)
	var h0: float = foes[0].get("health")
	foes[0].call("request_damage", dmg, gun)
	if absf((h0 - float(foes[0].get("health"))) - dmg * 1.5) > 0.5:
		_fail("a boosted %.0f-damage hit took %.1f, want %.1f" % [dmg, h0 - float(foes[0].get("health")), dmg * 1.5])
		bad = true
	me.set("damage_boost_s", 0.0)
	var diff: int = int(Game.settings.get("bot_difficulty", 1))
	var want_coin: int = arena.get_script().get_script_constant_map()["DROP_COINS"][diff]
	var kinds_seen := {}
	for k in foes.size():
		var foe: Node3D = foes[k]
		foe.global_position = me.global_position + Vector3(12.0 + 6.0 * k, 0, 0)
		var before := _pickups(arena).size()
		foe.call("take_damage", 99999.0, null)
		for i in 10:
			await get_tree().physics_frame
		var drops: Array = _pickups(arena).slice(before)
		var coin = drops.filter(func(p): return p.get("kind") == "coin")
		var pw = drops.filter(func(p): return p.get("kind") != "coin")
		if coin.size() != 1 or int(coin[0].get("value")) != want_coin or pw.size() != 1:
			_fail("bot %d dropped %s, want one %d-coin + one powerup" % [k, drops.map(func(p): return "%s:%s" % [p.get("kind"), p.get("value")]), want_coin])
			bad = true
			continue
		var kind: String = pw[0].get("kind")  # read before walking: a collected pickup is freed
		var pw_at: Vector3 = (pw[0] as Node3D).global_position
		var banked: int = int(arena.get("coins_picked").get(pid, 0))
		await _walk_to(me, (coin[0] as Node3D).global_position)
		if arena.get("_pickups").values().has(coin[0]):
			_fail("walking over the coin didn't pick it up")
			bad = true
		elif int(arena.get("coins_picked").get(pid, 0)) != banked + want_coin:
			_fail("coin not banked (%d -> %d)" % [banked, int(arena.get("coins_picked").get(pid, 0))])
			bad = true
		kinds_seen[kind] = true
		var w: Node = me.get_weapons()[0]
		me.set("health", 10.0)
		if int(w.get("max_ammo")) > 0:
			w.set("ammo", 0)
		await _walk_to(me, pw_at)
		match kind:
			"repair":
				if float(me.get("health")) <= 10.0:
					_fail("repair didn't heal")
					bad = true
			"ammo":
				if int(w.get("max_ammo")) > 0 and int(w.get("ammo")) != int(w.get("max_ammo")):
					_fail("ammo pickup didn't refill (%s / %s)" % [w.get("ammo"), w.get("max_ammo")])
					bad = true
			"damage":
				if float(me.get("damage_boost_s")) <= 0.0:
					_fail("damage boost not active")
					bad = true
			"speed":
				if float(me.get("speed_boost_s")) <= 0.0 or absf(float(me.get("walk_speed")) - float(me.get("base_walk_speed")) * 1.3 * float(me.get("terrain_speed"))) > 0.01:
					_fail("speed boost not active (walk %.2f)" % float(me.get("walk_speed")))
					bad = true
	# paid with the match result
	var stats: Array = arena.call("_build_mp_stats")
	var mine = stats.filter(func(e): return int(e.get("peer_id", -1)) == pid)
	if mine.is_empty() or int(mine[0].get("coins", 0)) != int(arena.get("coins_picked").get(pid, 0)):
		_fail("match stats don't carry the picked-up coins (%s)" % str(mine))
		bad = true
	else:
		var after: Dictionary = Game._apply_match_to({"coins": 0, "elo": 1000}, int(me.get("team")), int(me.get("team")), stats, pid)
		if int(after.get("coins", 0)) != Game.apply_coin_pickup_bonus(75 + int(mine[0]["coins"])):
			_fail("match result paid %d coins, want 75 + %d picked" % [int(after.get("coins", 0)), int(mine[0]["coins"])])
			bad = true
	# expiry
	var left: Array = _pickups(arena)
	if not left.is_empty():
		(left[0] as Node).set("age", 1000.0)
		for i in 4:
			await get_tree().physics_frame
		if arena.get("_pickups").values().has(left[0]):
			_fail("an expired pickup stayed")
			bad = true
	if bad:
		get_tree().quit(1)
		return
	print("[probe] bot_drops done (%d bots, coin %d, powerups %s)" % [foes.size(), want_coin, kinds_seen.keys()])
	get_tree().quit(0)
