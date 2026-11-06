extends Node
# T203 probe: after the mech pick the full-size minimap offers the team's spawn points;
# the pick lands the player there; bots choose by beacons + enemies; every spawn is open
# ground with a navmesh path to every beacon.

func _fail(msg: String) -> void:
	push_error("[probe] spawn_points: " + msg)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 5
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	var hud: Node = arena.get("hud")
	var mm: Control = hud.get("minimap")
	var pts: Array = arena.spawn_points(0)
	if pts.size() != 2 or arena.spawn_points(1).size() != 2:
		_fail("Math Temple should have 2 spawns per team, has %d / %d" % [pts.size(), arena.spawn_points(1).size()])
	# 1. mech pick -> spawn picker (big minimap, a button on each spawn), still paused
	hud.squad_slot_selected.emit(0)
	await get_tree().process_frame
	var btns: Array = hud.get("_spawn_ui").filter(func(n) -> bool: return n is Button and String(n.name) != "SpawnBack")  # T322 BACK is not a spawn
	if btns.size() != pts.size():
		_fail("spawn picker shows %d buttons for %d spawns" % [btns.size(), pts.size()])
	if mm.size.x < 200.0 or not get_tree().paused:
		_fail("spawn picker not full size (%s) or SP not paused" % mm.size)
	for i in btns.size():
		var c: Vector2 = (btns[i] as Control).position + (btns[i] as Control).size * 0.5
		if c.distance_to(mm.to_map(pts[i])) > 1.0 or not Rect2(Vector2.ZERO, mm.size).has_point(c):
			_fail("spawn button %d not on its spawn point" % i)
	var first: Node3D = arena.get("player_mech")
	hud.spawn_selected.emit(1)
	await _frames(30)
	var me: Node3D = arena.get("player_mech")
	if get_tree().paused or mm.size.x > 150.0:
		_fail("picker did not close (paused %s, minimap %s)" % [get_tree().paused, mm.size])
	if me == first or me.global_position.distance_to(pts[1]) > 20.0:
		_fail("player not at spawn 1 (%.1f m away)" % me.global_position.distance_to(pts[1]))
	if arena.get("_player").get("lives") != 5:
		_fail("moving spawns cost a life")
	# 2. open ground: a fresh spawn line stands still on the floor
	var start: Vector3 = me.global_position
	await _frames(60)
	if me.global_position.distance_to(start) > 1.0 or not me.is_on_floor():
		_fail("spawn-1 mech shoved %.2f m / not on the floor" % me.global_position.distance_to(start))
	# 3. every spawn reaches every beacon on the navmesh
	var nav_map: RID = arena.get_world_3d().navigation_map
	var beacons: Array = get_tree().get_nodes_in_group("beacons")
	for t in 2:
		for p in arena.spawn_points(t):
			for b in beacons:
				var path := NavigationServer3D.map_get_path(nav_map, p, b.global_position, true)
				if path.is_empty() or path[path.size() - 1].distance_to(b.global_position) > 4.0:
					_fail("no nav path from team %d spawn %s to %s" % [t, p, b.name])
	# 4. bots: home beacon free -> spawn 0; held -> the other; enemies there -> back
	for b in beacons:
		b.state = 0
	if arena.bot_spawn(0) != 0:
		_fail("all beacons neutral: bot should take spawn 0 (next to the home beacon)")
	var home: Node3D = null
	for b in beacons:
		if home == null or b.global_position.distance_to(pts[0]) < home.global_position.distance_to(pts[0]):
			home = b
	home.state = 1
	if arena.bot_spawn(0) != 1:
		_fail("home beacon held: bot should take spawn 1 (nearer the beacons still to win)")
	var foes: Array = arena.get("_team_mechs")[1]
	foes[0].global_position = pts[1] + Vector3(3, 1, 0)
	foes[1].global_position = pts[1] + Vector3(-3, 1, 0)
	if arena.bot_spawn(0) != 0:
		_fail("two enemies on spawn 1: bot should avoid it")
	foes[0].global_position = arena.spawn_points(1)[0] + Vector3(3, 1, 0)
	foes[1].global_position = arena.spawn_points(1)[0] + Vector3(-3, 1, 0)
	# 5. end to end: a team-0 bot dies with the home beacon held -> back in at spawn 1
	var bot: Node = arena.get("_team_mechs")[0][1]
	bot.take_damage(1e9)
	await _frames(int(arena.BOT_RESPAWN_S * 60.0) + 30)
	var back: Node3D = arena.get("_team_mechs")[0][-1]
	if back == bot or back.global_position.distance_to(pts[1]) > 20.0:
		_fail("respawned bot %s not at spawn 1 (%.1f m away)" % [back.name, back.global_position.distance_to(pts[1])])
	print("[probe] spawn_points done (player %.1f m from spawn 1, bot %s %.1f m)" % [
		me.global_position.distance_to(pts[1]), back.name, back.global_position.distance_to(pts[1])])
	get_tree().quit(0)
