extends Node
# T371 art review: the HUD with BOGGED + both boost lines under the minimap.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/hud_status_shot.tscn -- <out.png> [spawn]
# T410: "spawn" stops at the start pick's spawn picker (the SELECT SPAWN POINT banner).
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		if "spawn" in OS.get_cmdline_user_args():
			for i in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
			get_tree().quit(0)
			return
		arena.get("hud").spawn_selected.emit(0)
	for i in 30:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	me.set("terrain_speed", 0.55)
	me.set("damage_boost_s", 12.0)
	me.set("speed_boost_s", 7.0)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit(0)
