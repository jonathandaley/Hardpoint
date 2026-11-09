extends Node3D
# T351 art review: every pickup kind side by side (coin, repair, ammo, damage, speed) with labels.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 995x560 res://tools/art/pickups.tscn -- <out.png>
const Pickup := preload("res://scripts/Pickup.gd")
func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.22, 0.24, 0.28)
	add_child(env)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 10)
	ground.mesh = pm
	add_child(ground)
	var kinds := ["coin", "repair", "ammo", "damage", "speed"]
	for i in kinds.size():
		var p := Pickup.new()
		p.setup(kinds[i], 4)
		add_child(p)
		p.position = Vector3((i - 2) * 1.6, 0, 0)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 5.2)
	add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.current = true
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit(0)
