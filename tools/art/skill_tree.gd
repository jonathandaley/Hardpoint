extends Node
# T347 art review: the hangar's pilot tab with the skill tree, a few skills owned.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 res://tools/art/skill_tree.tscn -- <out.png>
func _ready() -> void:
	Game.profile["level"] = 9
	Game.profile["coins"] = 2000
	Game.profile["skills"] = {"health": 4, "damage": 2, "repair_rate": 1, "move_speed": 3, "ability_recharge": 1}
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	add_child(h)
	for i in 3:
		await get_tree().process_frame
	h.call("_show_tab", 1)
	h.call("_build_progression_nodes")
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit(0)
