extends Node3D
# T525: the VFX pieces (flash, sparks, tracer, death explosion) at 0.05 s and 0.2 s, side by side -- to
# compare effect looks before / after a change. Deterministic with --fixed-fps 60:
#   xvfb-run -a -s "-screen 0 800x450x24" ~/bin/godot --fixed-fps 60 --resolution 640x360 \
#     --rendering-driver opengl3 --path . res://tools/art/fx_shot.tscn -- <out.png> [fancy]
func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	Game.settings["fancy_effects"] = "fancy" in OS.get_cmdline_user_args()  # T523: -- <out.png> fancy
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.5, 5)
	cam.look_at(Vector3(0, 1, 0))
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.2)
	env.environment = e
	add_child(env)
	for i in 5:
		await get_tree().process_frame
	seed(42)
	VFX.muzzle_flash(Vector3(-2.2, 1.6, 0), Color(1.0, 0.8, 0.3), false, 0.3)
	VFX.hit_sparks(Vector3(-1.0, 1.0, 0))
	VFX.tracer(Vector3(-3, 0.4, 0), Vector3(3, 0.4, -1), Color(0.75, 0.5, 1.0), 0.35, false, 0.08)
	VFX.death_explosion(Vector3(1.6, 1.0, 0))
	var shots := []
	for want in [3, 9]:  # --fixed-fps 60: 3 frames = 0.05 s, then 12 = 0.2 s
		for f in want:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots.append(get_viewport().get_texture().get_image())
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var img := Image.create(w * 2, h, false, shots[0].get_format())
	for i in 2:
		img.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	img.save_png(out)
	get_tree().quit(0)
