extends Node
# T450 probe (user 2026-11-17: yes to "a plinth at the base and a team-coloured light at the top"):
# a beacon has a plinth at its foot and a lamp at the top of its beam whose colour follows the
# beacon's state (neutral / team A / team B / contested) through the existing visuals update; on the
# roofed Corvette the lamps hang under the ceiling (T451).

func _fail(msg: String) -> void:
	push_error("[probe] beacon_look: " + msg)

func _ready() -> void:
	var b: Node3D = load("res://scenes/beacon/Beacon.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	var bad := 0
	var lamp: MeshInstance3D = null
	var plinth := false
	for c in b.get_node("Visual").get_children():
		if c is MeshInstance3D and c.mesh is SphereMesh and c.position.y > 20.0:
			lamp = c
		elif c is MeshInstance3D and c.mesh is CylinderMesh and c.position.y < 1.0:
			plinth = true
	if lamp == null or not plinth:
		bad += 1
		_fail("plinth %s, lamp %s" % [plinth, lamp])
	else:
		var seen := {}
		for st in [0, 1, 2, 3]:
			b.set("state", st)
			b.call("_update_visuals")
			var m := lamp.get_surface_override_material(0) as StandardMaterial3D
			seen[m.emission.to_html()] = st
		if seen.size() != 4:
			bad += 1
			_fail("the lamp shows %d colours over the 4 states, want 4" % seen.size())
		# T506 (user: "All players should see their own side, beacon colors, etc as blue."): from team 1's
		# screen a team-1 beacon is blue and a team-0 one red -- and the top-strip dot agrees
		var lamp_col := func(st: int) -> Color:
			b.set("state", st)
			b.call("_update_visuals")
			return (lamp.get_surface_override_material(0) as StandardMaterial3D).albedo_color
		Game.local_team = 1
		var own: Color = lamp_col.call(2)
		var foe: Color = lamp_col.call(1)
		if not (own.b > own.r and foe.r > foe.b):
			bad += 1
			_fail("viewer on team 1: its own beacon %s, the enemy's %s -- want blue / red" % [own, foe])
		if Game.team_color(1) != Color(0.2, 0.5, 1.0) or Game.team_color(0) != Color(1.0, 0.3, 0.2):
			bad += 1
			_fail("Game.team_color from team 1: own %s, other %s" % [Game.team_color(1), Game.team_color(0)])
		Game.local_team = 0
		if lamp_col.call(1).b <= lamp_col.call(1).r:
			bad += 1
			_fail("viewer on team 0: its own beacon isn't blue")
	b.queue_free()  # and let it go before the arena's HUD lists the beacons group
	for i in 3:
		await get_tree().process_frame
	# T451: on the roofed Corvette (10 m ceiling) every lamp hangs under the ceiling, in sight
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Corvette.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 6:
		await get_tree().physics_frame
	var lamps := 0
	for beacon in get_tree().get_nodes_in_group("beacons"):
		for c in beacon.get_node("Visual").get_children():
			if c is MeshInstance3D and c.mesh is SphereMesh:
				lamps += 1
				if c.global_position.y > 9.0:
					bad += 1
					_fail("Corvette: a lamp at y %.1f, above the 10 m ceiling" % c.global_position.y)
	if lamps < 5:
		bad += 1
		_fail("Corvette: %d beacon lamps found" % lamps)
	print("[probe] beacon_look: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)
