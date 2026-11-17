extends Node
# T416 probe (user 2026-11-16: bots "stuck at an intersection of walkway and wall near the center
# beacon (slightly to the right, from the perspective I spawned at)"): nothing solid stands across
# any Swamp boardwalk -- rays along each deck (centre and both edges, 1-3 m up) hit nothing. The
# sunken ruin's side slabs crossed the two centre walkways at (-16.6, 8.3) / (16.6, -8.3).
const Swamp := preload("res://scripts/maps/Swamp.gd")
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	for i in 3:
		await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	for m in get_tree().get_nodes_in_group("mechs"):
		ex.append(m.get_rid())
	var bad: Array = []
	for bw in Swamp.BOARDWALKS:
		for s in [1.0, -1.0]:
			var a: Vector2 = bw[0] * s
			var b: Vector2 = bw[1] * s
			for h in [1.0, 2.0, 3.0]:
				for off in [-1.5, 0.0, 1.5]:
					var dir := (b - a).normalized()
					var side: Vector2 = Vector2(-dir.y, dir.x) * off
					var q := PhysicsRayQueryParameters3D.create(Vector3(a.x + side.x, Swamp.DECK_TOP + h, a.y + side.y), Vector3(b.x + side.x, Swamp.DECK_TOP + h, b.y + side.y))
					q.exclude = ex
					var hit: Dictionary = space.intersect_ray(q)
					if not hit.is_empty():
						bad.append("%s->%s %.0f m up, %.1f m off-centre: blocked at %s" % [a, b, h, off, (hit.position as Vector3).snapped(Vector3.ONE * 0.1)])
	if not bad.is_empty():
		push_error("[probe] swamp_walkways FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] swamp_walkways done (%d walkways clear)" % (Swamp.BOARDWALKS.size() * 2))
	get_tree().quit(0)
