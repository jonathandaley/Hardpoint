extends Node
# T225 probe: on the swamp map a mech standing in the water moves at Swamp.WADE of its
# speed, and at full speed again once it's back on dry ground (spawn pad). T232: boardwalk
# decks sit just above the ground they rest on.

func _fail(msg: String) -> void:
	push_error("[probe] swamp_wade: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Swamp.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 20:
		await get_tree().physics_frame
	var m: Node3D = arena.get("player_mech")
	var map: Node = arena.get("_map")
	var full := float(m.get("walk_speed"))
	if absf(float(m.get("terrain_speed")) - 1.0) > 0.001:
		_fail("slowed on the dry spawn pad (terrain_speed %s)" % m.get("terrain_speed"))
	var wet := Vector2(-60, 0)  # open water: away from every hummock, pad and boardwalk
	m.global_position = Vector3(wet.x, map.call("ground_y", wet.x, wet.y) + 0.2, wet.y)
	for i in 20:
		await get_tree().physics_frame
	var wade := float(m.get("walk_speed"))
	var want: float = map.get_script().get_script_constant_map()["WADE"]
	if absf(wade / full - want) > 0.01:
		_fail("in the water walk_speed is %.2f of dry (want %.2f)" % [wade / full, want])
	# T232 (HUMAN_FOUND_ISSUES 2026-11-04: boardwalks flicker, "same level as the floor"):
	# every deck clears the ground under it by DECK_GAP..STEP (no z-fight, still a step up)
	var decks := 0
	for b in map.get_children():
		if not (b is StaticBody3D) or b.get_child_count() == 0 or not (b.get_child(0) is CollisionShape3D):
			continue
		var bs := (b.get_child(0) as CollisionShape3D).shape as BoxShape3D
		if bs == null or not is_equal_approx(bs.size.x, 4.0) or not is_equal_approx(bs.size.y, 0.3):
			continue
		decks += 1
		var top: float = (b as Node3D).global_position.y + bs.size.y * 0.5
		var along: Vector3 = (b as Node3D).global_transform.basis.z.normalized()
		var lowest_gap := INF
		for k in 21:
			var q: Vector3 = (b as Node3D).global_position + along * bs.size.z * (k / 20.0 - 0.5)
			lowest_gap = minf(lowest_gap, top - float(map.call("ground_y", q.x, q.z)))
		if lowest_gap < 0.05 or lowest_gap > 0.3:
			_fail("boardwalk at %s: deck top %.2f clears the ground by %.2f (want 0.05..0.3)" % [(b as Node3D).global_position, top, lowest_gap])
	if decks != 8:
		_fail("found %d boardwalk decks, want 8" % decks)
	print("[probe] swamp_wade done (dry %.2f, wading %.2f, %d boardwalks)" % [full, wade, decks])
	get_tree().quit(0)
