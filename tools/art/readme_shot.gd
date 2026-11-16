extends Node
# T435: the README's in-match screenshot -- a 5v5 bot match on <map>, the player's own mech on
# autopilot (a Hard bot drives it) so the shot is from the fight, with the HUD. Saves a frame every
# 4 s from 20 s in: <out_prefix>_<n>.png; pick the best by eye.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/readme_shot.tscn -- <out_prefix> [map path]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Game.loadout["team_size"] = 5
	Game.loadout["sp_bots"] = [4, 5]
	Game.loadout["mode"] = "beacons"
	Game.settings["bot_difficulty"] = 3
	if args.size() > 1:
		Game.loadout["map_def"] = load(args[1])
	Game.mp_active_match["roster"] = []
	Game.setup_sp_match()
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	await get_tree().process_frame
	var me: Node = arena.get("player_mech")
	var pl: Node = arena.get("_player")
	arena.call("_add_nav_agent", me)
	var ai := Node.new()
	ai.set_script(load("res://scripts/AIInputSource.gd"))
	ai.set("bot_id", 999)
	pl.add_child(ai)
	ai.set("difficulty", 3)
	pl.set("input_source", ai)
	pl.call("possess", me)
	me.set("invincible", true)
	var t := 0.0
	var n := 0
	while n < 8:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t >= 20.0 + n * 4.0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [args[0], n])
			n += 1
	get_tree().quit(0)
