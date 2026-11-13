extends Node
# T264 probe (HUMAN_FOUND 2026-11-05: drops from destroyed bots; user: coins scaled by bot
# difficulty + powerups repair / ammo / damage boost / speed boost) + T362 (2026-11-08 late:
# "coins should be awarded to players on kill, in addition to dropping coins. Powerups should
# randomly spawn on the battlefield, not be dropped by bots"): our kill banks the bot's coin
# value at once; the destroyed bot drops one coin worth the same and no powerup; walking over
# the coin banks it too (all paid with the match result); powerups appear on the navmesh on a
# timer, never more than the cap; every powerup kind does its job; the damage boost multiplies
# our hits; a pickup left alone expires.

func _fail(msg: String) -> void:
	push_error("[probe] bot_drops FAIL: " + msg)

func _pickups(arena: Node) -> Array:  # on the ground (a taken one pops for a moment first, T351)
	return arena.get_children().filter(func(n): return String(n.name).begins_with("Pickup_") and not n.get("collected"))

func _new_since(arena: Node, pre: Array) -> Array:
	return _pickups(arena).filter(func(n): return not pre.has(n))

func _walk_to(me: Node3D, p: Vector3) -> void:
	me.global_position = Vector3(p.x, me.global_position.y, p.z)
	for i in 6:
		await get_tree().physics_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.loadout["team_size"] = 3
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:  # B135: T365 squads are random -- a shield soaked the boosted test hit
		if int(e["peer_id"]) == 0:
			e["squad"] = range(5).map(func(_i): return {"mech": "res://resources/mechs/Pegasus.tres", "weapons": ["res://scenes/weapons/RifleLight.tscn", "res://scenes/weapons/RifleLight.tscn"]})
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
	arena.set("powerup_every_s", 1000.0)  # T362: no map powerups until the timer check below
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
		var pre := _pickups(arena)
		var pre_kill: int = int(arena.get("coins_picked").get(pid, 0))
		var my_ri: int = int(me.get("roster_idx"))
		var pre_kc: int = int(arena.get("kill_coins_by_ri").get(my_ri, 0))
		foe.set("last_attacker", me)  # our kill
		foe.call("take_damage", 99999.0, null)
		for i in 10:
			await get_tree().physics_frame
		var drops: Array = _new_since(arena, pre)
		var coin = drops.filter(func(p): return p.get("kind") == "coin")
		var pw = drops.filter(func(p): return p.get("kind") != "coin")
		if coin.size() != 1 or int(coin[0].get("value")) != want_coin or pw.size() != 0:
			_fail("bot %d dropped %s, want one %d-coin and no powerup (T362)" % [k, drops.map(func(p): return "%s:%s" % [p.get("kind"), p.get("value")]), want_coin])
			bad = true
			continue
		var banked: int = int(arena.get("coins_picked").get(pid, 0))
		var kc: int = int(arena.get("kill_coins_by_ri").get(my_ri, 0)) - pre_kc
		if kc != want_coin or banked != pre_kill:  # T364: counted as a kill, paid at match end -- not a pickup
			_fail("our kill counted %d kill coins (want %d) and moved the pickups %d -> %d (T364)" % [kc, want_coin, pre_kill, banked])
			bad = true
		await _walk_to(me, (coin[0] as Node3D).global_position)
		if arena.get("_pickups").values().has(coin[0]):
			_fail("walking over the coin didn't pick it up")
			bad = true
		elif int(arena.get("coins_picked").get(pid, 0)) != banked + want_coin:
			_fail("coin not banked (%d -> %d)" % [banked, int(arena.get("coins_picked").get(pid, 0))])
			bad = true
	# T362: powerups come from the map -- on the navmesh, on a timer, under the cap
	var nr: NavigationRegion3D = arena.get("_nav_region")
	for i in 600:
		if nr != null and nr.navigation_mesh.get_polygon_count() > 0 and i > 5:
			break
		await get_tree().physics_frame
	var nav_map: RID = arena.get_world_3d().navigation_map
	for kind in arena.get_script().get_script_constant_map()["POWERUPS"]:
		var pw: Array = []
		for attempt in 3:  # a random navmesh point can land under a mech, which takes it the same frame
			var pre := _pickups(arena)
			if not arena.call("spawn_map_powerup", kind):
				break
			await get_tree().physics_frame
			pw = _new_since(arena, pre)
			if pw.size() == 1:
				break
		if pw.is_empty() and not bad and arena.get("_nav_region").navigation_mesh.get_polygon_count() == 0:
			_fail("no map powerup (navmesh missing?)")
			bad = true
			break
		if pw.size() != 1:
			_fail("spawning a %s put %d pickups down" % [kind, pw.size()])
			bad = true
			continue
		var pw_at: Vector3 = (pw[0] as Node3D).global_position
		if NavigationServer3D.map_get_closest_point(nav_map, pw_at).distance_to(pw_at) > 0.6:
			_fail("a map %s sits off the navmesh at %s" % [kind, pw_at])
			bad = true
		kinds_seen[kind] = true
		var w: Node = me.get_weapons()[0]
		me.set("health", 10.0)
		if int(w.get("max_ammo")) > 0:
			w.set("ammo", 0)
		var labels: Array = (pw[0] as Node).find_children("*", "Label3D", true, false)
		if labels.is_empty() or (labels[0] as Label3D).text == "":
			_fail("a %s pickup has no label saying what it does (T351)" % kind)
			bad = true
		var node: Node = pw[0]
		me.global_position = pw_at + Vector3.UP * 0.6  # it may be on a ledge: stand right on it
		for i in 6:
			await get_tree().physics_frame
		# T351: taken -> it pops (still there, collected) and the toast names the effect
		if not is_instance_valid(node) or not node.get("collected"):
			_fail("a taken %s vanished without its pop" % kind)
			bad = true
		var toast: Label = arena.get("hud").get("_toast")
		if toast == null or not toast.text.to_upper().contains(kind.to_upper()):
			_fail("no toast for the %s (%s)" % [kind, toast.text if toast != null else "none"])
			bad = true
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
	if float(arena.get_script().get_script_constant_map()["PICKUP_LIFE_S"]) != 120.0:
		_fail("pickups last %s s on the ground, the user asked for 60 (T351)" % arena.get_script().get_script_constant_map()["PICKUP_LIFE_S"])
		bad = true
	# T414 (HUMAN_FOUND: "Powerups should appear 50% more often."): every 10 s, not 15; the cap
	# grows with it (4 -> 6) so a full map doesn't eat the extra spawns
	var consts: Dictionary = arena.get_script().get_script_constant_map()
	if float(consts["POWERUP_EVERY_S"]) != 10.0 or int(consts["POWERUP_CAP"]) != 6:
		_fail("map powerups every %s s, cap %s (want 10 s, 6: 50%% more often)" % [consts["POWERUP_EVERY_S"], consts["POWERUP_CAP"]])
		bad = true
	# the timer, capped
	arena.set("powerup_every_s", 0.05)
	for i in 90:
		await get_tree().physics_frame
	arena.set("powerup_every_s", 1000.0)
	var cap: int = arena.get_script().get_script_constant_map()["POWERUP_CAP"]
	var on_ground: int = _pickups(arena).filter(func(p): return p.get("kind") != "coin").size()
	if on_ground < 1 or on_ground > cap:
		_fail("%d map powerups on the ground after a fast timer, want 1..%d" % [on_ground, cap])
		bad = true
	# paid with the match result
	var stats: Array = arena.call("_build_mp_stats")
	var mine = stats.filter(func(e): return int(e.get("peer_id", -1)) == pid)
	if mine.is_empty() or int(mine[0].get("coins", 0)) != int(arena.get("coins_picked").get(pid, 0)):
		_fail("match stats don't carry the picked-up coins (%s)" % str(mine))
		bad = true
	else:
		var after: Dictionary = Game._apply_match_to({"coins": 0, "elo": 1000}, int(me.get("team")), int(me.get("team")), stats, pid)
		if int(after.get("coins", 0)) != Game.apply_coin_pickup_bonus(75 + int(mine[0]["coins"]) + int(mine[0].get("kill_coins", 0))):
			_fail("match result paid %d coins, want 75 + %d picked + %d kills" % [int(after.get("coins", 0)), int(mine[0]["coins"]), int(mine[0].get("kill_coins", 0))])
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
