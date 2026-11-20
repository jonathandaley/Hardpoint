extends Node3D
# T528: one mech close up -- front, side, back at rest, then front mid-stride -- side by side, to compare a
# mech's look before / after a change (deterministic: --fixed-fps 60).
#   xvfb-run -a -s "-screen 0 800x600x24" ~/bin/godot --fixed-fps 60 --resolution 400x400 \
#     --rendering-driver opengl3 --path . res://tools/art/mech_shot.tscn -- <out.png> <Mech>
#   ... -- diff <a.png> <b.png>   prints the share of pixels that differ (> 8/255 on any channel)
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args[0] == "diff":
		var a := Image.load_from_file(args[1])
		var b := Image.load_from_file(args[2])
		var n := 0
		for y in a.get_height():
			for x in a.get_width():
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				if absf(ca.r - cb.r) > 0.032 or absf(ca.g - cb.g) > 0.032 or absf(ca.b - cb.b) > 0.032:
					n += 1
		print("[diff] %.3f%% of pixels differ (%d)" % [100.0 * n / (a.get_width() * a.get_height()), n])
		get_tree().quit(0)
		return
	var md: Resource = load("res://resources/mechs/%s.tres" % args[1])
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.2, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var m: Node3D = md.scene.instantiate()
	m.scale = Vector3.ONE * md.body_scale
	MechVisuals.apply(m, md.display_name)
	add_child(m)
	m.set_physics_process(false)
	m.remove_from_group("mechs")
	var ks := m.get_node_or_null("KitSkin")
	print("[mech_shot] %s: KitSkin %s, surfaces %d, bones %d" % [args[1], ks != null,
		(ks.get_node("KitBody") as MeshInstance3D).mesh.get_surface_count() if ks != null else 0, (ks as Skeleton3D).get_bone_count() if ks != null else 0])
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var h: float = 2.2 * md.body_scale
	var shots := []
	for yaw in [0.0, 90.0, 180.0, -1.0]:
		if yaw < 0.0:  # mid-stride: left leg forward, right back, knees bent
			var legs: Node = m.get_node("Legs")
			(legs.get_node("LeftHip") as Node3D).rotation.x += 0.7
			(legs.get_node("RightHip") as Node3D).rotation.x -= 0.6
			(legs.get_node("LeftHip/LeftKnee1") as Node3D).rotation.x -= 0.8
			yaw = 60.0
		var d: float = 3.2 * md.body_scale
		cam.position = Vector3(sin(deg_to_rad(yaw)) * d, h, -cos(deg_to_rad(yaw)) * d)
		cam.look_at(Vector3(0, h * 0.75, 0))
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots.append(get_viewport().get_texture().get_image())
	var w: int = shots[0].get_width()
	var img := Image.create(w * 4, shots[0].get_height(), false, shots[0].get_format())
	for i in 4:
		img.blit_rect(shots[i], Rect2i(0, 0, w, shots[0].get_height()), Vector2i(i * w, 0))
	img.save_png(args[0])
	get_tree().quit(0)
