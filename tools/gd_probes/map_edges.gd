extends Node
# T374 probe (HUMAN_FOUND 2026-11-09: a Kestrel bot fell off the back of Redwood Forest -- "the dip
# in the back can be walked off by any bot"): on every map, at every 2 m of the minimap outline, a
# ray from 4 m inside to 4 m outside at foot and chest height over the floor hits something (the
# boundary wall reached only down to y 0, and the rolling floor dips below that at the edge). And a
# mech that falls below Mech.FALL_KILL_Y anyway dies, so a match can't hang on a lost bot.

func _fail(msg: String) -> void:
	push_error("[probe] map_edges: " + msg)

func _arena(md: Resource) -> Node:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = md
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	return arena

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scenes := {}
	for f in DirAccess.get_files_at("res://resources/maps"):
		if f.ends_with(".tres"):
			var md: Resource = load("res://resources/maps/" + f)
			if not scenes.has(md.scene_path):
				scenes[md.scene_path] = md
	var summary: Array = []
	for sp in scenes:
		var arena: Node = await _arena(scenes[sp])
		var map: Node = arena.get("_map")
		var outline: PackedVector2Array = map.minimap_outline() if map != null else PackedVector2Array()
		var mapname := String(sp).get_file().get_basename()
		if outline.size() < 3:
			summary.append("%s: no outline" % mapname)
			arena.queue_free()
			await get_tree().process_frame
			continue
		var mid := Vector2.ZERO
		for p in outline:
			mid += p
		mid /= outline.size()
		var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
		var gaps: Array = []
		var tested := 0
		for i in outline.size():
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % outline.size()]
			var along := (b - a).normalized()
			var out := Vector2(along.y, -along.x)
			if out.dot((a + b) * 0.5 - mid) < 0.0:
				out = -out
			var n := int(a.distance_to(b) / 2.0)
			for k in n + 1:
				var p := a.lerp(b, float(k) / maxf(n, 1))
				var gy: float = map.ground_y(p.x - out.x * 4.0, p.y - out.y * 4.0)
				for h in [0.5, 2.0]:
					var from := Vector3(p.x - out.x * 4.0, gy + h, p.y - out.y * 4.0)
					var to := Vector3(p.x + out.x * 4.0, gy + h, p.y + out.y * 4.0)
					tested += 1
					if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)).is_empty():
						gaps.append("(%.0f, %.0f) y %.1f" % [p.x, p.y, gy + h])
		if not gaps.is_empty():
			_fail("%s: %d of %d edge rays leave the map, e.g. %s" % [mapname, gaps.size(), tested, ", ".join(gaps.slice(0, 4))])
		summary.append("%s %d rays" % [mapname, tested])
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	# a mech that falls out of the world anyway is destroyed
	var arena: Node = await _arena(load("res://resources/maps/Forest.tres"))
	var me: Node3D = arena.get("player_mech")
	var enemy: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	enemy.invincible = false
	enemy.global_position = Vector3(0, -200.0, 0)
	for i in 30:
		await get_tree().physics_frame
	if not enemy.get("is_dead"):
		_fail("a mech at y %.0f is still alive" % enemy.global_position.y)
	print("[probe] map_edges done (%s)" % "; ".join(summary))
	get_tree().quit(0)
