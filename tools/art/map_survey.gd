extends Node
# Visual survey: one map from several fixed viewpoints (overview, eye level, looking up) -> PNGs.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/map_survey.tscn -- <out_dir> <Map> [x,y,z ...]
# With points: one close shot of each (from 10 m off, 4 m up) instead of the fixed views,
# written as <Map>_p<n>.png -- for looking at what a probe reported.
# Writes <out_dir>/<Map>_<n>.png. Viewpoints are fractions of the map's half-size, so every map
# gets comparable shots without per-map tuning.
const VIEWS := [  # [x, z, height above ground, look-at x, look-at z, look-at height]
	[0.0, 0.0, 120.0, 0.0, 0.3, 0.0],     # 0 high overview from the centre
	[0.7, 0.7, 45.0, 0.0, 0.0, 0.0],      # 1 oblique from a corner
	[-0.7, -0.7, 45.0, 0.0, 0.0, 0.0],    # 2 oblique from the other corner
	[0.0, 0.5, 5.0, 0.0, -0.5, 5.0],      # 3 eye level across the middle
	[0.5, 0.0, 5.0, -0.5, 0.0, 5.0],      # 4 eye level, crosswise
	[-0.3, 0.3, 5.0, 0.3, -0.3, 5.0],     # 5 eye level, diagonal
	[0.2, -0.2, 4.0, 0.3, -0.25, 60.0],   # 6 looking up
	[0.6, -0.4, 12.0, -0.2, 0.2, 0.0],    # 7 low oblique
]
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
	var half: float = float(map.get("edge_half") if map.get("edge_half") else 120.0)
	var cam := Camera3D.new()
	cam.far = 2000.0
	arena.add_child(cam)
	cam.current = true
	arena.get("hud").visible = false
	if args.size() > 2:
		for i in range(2, args.size()):
			var p := str_to_var("Vector3(%s)" % args[i]) as Vector3
			cam.global_position = p + Vector3(8.0, 4.0, 6.0)
			cam.look_at(p)
			for f in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_p%d.png" % [args[0], args[1], i - 2])
		get_tree().quit(0)
		return
	for i in VIEWS.size():
		var v: Array = VIEWS[i]
		var at := Vector3(v[0] * half, 0.0, v[1] * half)
		at.y = float(map.call("ground_y", at.x, at.z)) + v[2]
		var to := Vector3(v[3] * half, 0.0, v[4] * half)
		to.y = float(map.call("ground_y", to.x, to.z)) + v[5]
		cam.global_position = at
		cam.look_at(to, Vector3.FORWARD if absf((to - at).normalized().y) > 0.95 else Vector3.UP)
		for f in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [args[0], args[1], i])
	get_tree().quit(0)
