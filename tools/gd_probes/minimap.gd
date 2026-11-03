extends Node
# T202 probe: the corner minimap shows every live non-stealthed mech where it is in
# the world (team colours from the local side), beacons coloured by owner from the
# local side, and drops a stealthed enemy.

func _fail(msg: String) -> void:
	push_error("[probe] minimap: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 3
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 60:
		await get_tree().physics_frame
	var mm: Control = arena.get("hud").get("minimap")
	if mm == null or not mm.visible or mm.size.x < 60.0:
		_fail("no visible minimap in the HUD")
		get_tree().quit(0)
		return
	var team: Array = arena.get("_team_mechs")
	var live := 0
	for t in 2:
		for m in team[t]:
			if is_instance_valid(m) and not m.is_dead:
				live += 1
	var shown: Array = mm.shown_mechs()
	if shown.size() != live or live < 6:
		_fail("shows %d mechs, %d alive" % [shown.size(), live])
	var rect := Rect2(Vector2.ZERO, mm.size)
	for m in shown:
		var p: Vector2 = mm.to_map(m.global_position)
		if not rect.has_point(p):
			_fail("%s maps outside the minimap (%s)" % [m.name, p])
		# north-up: world -Z is up, +X right
		var q: Vector2 = mm.to_map(m.global_position + Vector3(10, 0, -10))
		if not (q.x > p.x and q.y < p.y):
			_fail("map axes wrong: +X/-Z moved %s -> %s" % [p, q])
		if mm.team_color(m.team) != (mm.ALLY if m.team == arena.get("_local_team") else mm.ENEMY):
			_fail("%s team colour not from the local side" % m.name)
	# a stealthed enemy drops off the map; the local mech stays even when stealthed
	var foe: Node = team[1][0]
	foe.is_stealthy = true
	if foe in mm.shown_mechs():
		_fail("stealthed enemy %s still on the minimap" % foe.name)
	foe.is_stealthy = false
	# beacons: owner colour from the local side
	var b: Node = mm.beacons[0]
	var cases := [[0, mm.NEUTRAL], [1, mm.ALLY], [2, mm.ENEMY], [3, mm.CONTESTED]]
	for c in cases:
		b.state = c[0]
		if mm.beacon_color(b) != c[1]:
			_fail("beacon state %d drew %s" % [c[0], mm.beacon_color(b)])
	mm.local_team = 1
	b.state = 2
	if mm.beacon_color(b) != mm.ALLY:
		_fail("team-B beacon not blue for a team-B player")
	print("[probe] minimap done (%d mechs, %d beacons)" % [shown.size(), mm.beacons.size()])
	get_tree().quit(0)
