extends Node
# T409 art review: the hangar's mech detail screen (slot 1): preview with its rotate buttons.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 res://tools/art/hangar_detail.tscn -- <out.png>
func _ready() -> void:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	add_child(h)
	for i in 3:
		await get_tree().process_frame
	h.call("_show_detail_screen", 0)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit(0)
