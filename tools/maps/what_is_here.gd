extends Node
# T416 investigation tool: what solid bodies sit within 3 m of given points on a map (and the ground there).
#   ~/bin/godot --headless --path . res://tools/maps/what_is_here.tscn -- <Map> x,z x,z ...
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/%s.tres" % args[0])
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 3:
		await get_tree().physics_frame
	var map: Node = arena.get("_map")
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	for a in args.slice(1):
		var x := float(a.get_slice(",", 0))
		var z := float(a.get_slice(",", 1))
		var gy: float = map.call("ground_y", x, z)
		var sh := SphereShape3D.new()
		sh.radius = 3.0
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sh
		q.transform = Transform3D(Basis(), Vector3(x, gy + 1.0, z))
		var names: Array = []
		for r in space.intersect_shape(q, 16):
			var c: Node = r.collider
			if c.is_in_group("mechs"):
				continue
			names.append("%s@%s" % [c.name, (c as Node3D).global_position.snapped(Vector3.ONE * 0.1)])
		print("[here] (%.0f, %.0f) ground %.2f: %s" % [x, z, gy, names])
	get_tree().quit(0)
