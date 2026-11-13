extends Node
# T405 art review: a map's edge from 40 m inside it, at a mech's eye height, looking out (fog curtains).
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/edge_shot.tscn -- <out.png> <Map> [half]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/%s.tres" % args[1])
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 20:
		await get_tree().physics_frame
	var map: Node = arena.get("_map")
	var half: float = float(args[2]) if args.size() > 2 else float(map.get("edge_half") if map.get("edge_half") else 140.0)
	var at := Vector3(20.0, 0.0, half - 40.0)
	at.y = float(map.call("ground_y", at.x, at.z)) + 4.0
	var cam := Camera3D.new()
	arena.add_child(cam)
	cam.global_position = at
	cam.look_at(Vector3(-10.0, at.y - 1.0, half + 10.0))
	cam.current = true
	arena.get("hud").visible = false
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0])
	get_tree().quit(0)
