extends Node
# T179 art review: an SP arena (team_size 3 of <Mech>) seen from beside team 1's spawn.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/arena_shot.tscn -- <out.png> <Mech> [map path]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var md: Resource = load("res://resources/mechs/%s.tres" % args[1])
	Game.loadout["team_size"] = 3
	if args.size() > 2:
		Game.loadout["map_def"] = load(args[2])
	Game.setup_sp_match()  # T184: then every slot runs <Mech>
	for e in Game.mp_active_match["roster"]:
		e["squad"] = [{"mech": md.resource_path, "weapons": []}]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 20:
		await get_tree().physics_frame
	var team1: Array = arena.get("_team_mechs")[1]
	var c := Vector3.ZERO
	for m in team1:
		c += m.global_position
	c /= team1.size()
	var cam := Camera3D.new()
	arena.add_child(cam)
	var fwd: Vector3 = -(team1[0] as Node3D).global_transform.basis.z
	cam.global_position = c + fwd * 7.0 + Vector3.UP * 2.5 + (team1[0] as Node3D).global_transform.basis.x * 3.0
	cam.look_at(c + Vector3.UP * 1.3)
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0])
	get_tree().quit(0)
