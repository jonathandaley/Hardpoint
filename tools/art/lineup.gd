extends Node3D
# T178 art review: renders the mech roster in a row (half "a" or "b") to a PNG.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/lineup.tscn -- <out.png> <yaw deg, 180 = facing camera> <a|b|Name,Name,...>
# T340: a comma list renders exactly those mechs (tools/new_mech.py: a new one among the roster).
func _ready() -> void:
	var all := ["Slip", "Cesh", "Seeker", "Hornet", "Hippogriff", "Kestrel", "Pegasus", "Everest", "Vesuvius"]
	var pick: String = OS.get_cmdline_user_args()[2]
	var names: Array = all.slice(0, 5) if pick == "a" else all.slice(5) if pick == "b" else Array(pick.split(","))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.38, 0.45)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 20)
	ground.mesh = pm
	add_child(ground)
	var angle := float(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 200.0
	for i in names.size():
		var md: Resource = load("res://resources/mechs/%s.tres" % names[i])
		var m: Node3D = md.scene.instantiate()
		m.scale = Vector3.ONE * md.body_scale
		MechVisuals.apply(m, md.display_name)
		m.position = Vector3((i - (names.size() - 1) * 0.5) * 2.8, 0, 0)
		m.rotation_degrees.y = angle
		add_child(m)
		m.set_physics_process(false)
		m.configure_weapons(md.weapon_slots)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.6, 9.5)
	cam.fov = 60
	add_child(cam)
	cam.look_at(Vector3(0, 1.2, 0))
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit(0)
