extends Node3D
# T342 art review: the Taurus lunge as a frame strip -- standing, mid-crouch, full crouch, and
# the dash speeding up -- side on, glow included.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 995x560 \
#     res://tools/art/lunge_strip.tscn -- <out.png> [Name]
const TIMES := [0.0, 0.1, 0.2, 0.35, 0.7, 1.5]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mname: String = args[1] if args.size() > 1 else "Taurus"
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
	pm.size = Vector2(80, 20)
	ground.mesh = pm
	add_child(ground)
	var md: Resource = load("res://resources/mechs/%s.tres" % mname)
	var dt := 1.0 / 60.0
	for i in TIMES.size():
		var m: Node3D = md.scene.instantiate()
		m.scale = Vector3.ONE * md.body_scale
		MechVisuals.apply(m, md.display_name)
		m.position = Vector3((i - (TIMES.size() - 1) * 0.5) * 2.5, 0, 0)
		m.rotation_degrees.y = 270.0  # facing +x: the dash runs left to right
		add_child(m)
		m.set_physics_process(false)
		m.configure_weapons(md.weapon_slots)
		var legs: Node = m.get("legs")
		var dir: Vector3 = -m.global_transform.basis.z
		m.set("lunging", true)
		var t := 0.0
		while t < float(TIMES[i]) - 0.0001:  # play the clock up to the frame: the stride phase is real
			t += dt
			m.set("lunge_t", t)
			legs.call("update_gait", dir * Mech.lunge_speed(t), m.global_transform.basis, 15.0, md.walk_speed, dt, false, m.call("lunge_pose"))
		m.set("lunge_t", float(TIMES[i]))
		if float(TIMES[i]) == 0.0:
			m.set("lunging", false)
		legs.call("update_gait", dir * Mech.lunge_speed(float(TIMES[i])), m.global_transform.basis, 15.0, md.walk_speed, dt, false, m.call("lunge_pose"))
		m.call("_set_lunge_glow", Mech.lunge_speed(float(TIMES[i])) / Mech.LUNGE_PEAK)
		var lbl := Label3D.new()
		lbl.text = "%.2f s  %.0f m/s" % [TIMES[i], Mech.lunge_speed(float(TIMES[i]))]
		lbl.font_size = 48
		lbl.pixel_size = 0.005
		lbl.position = Vector3(m.position.x, 3.3, 0)
		add_child(lbl)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 11.5)
	cam.fov = 40
	add_child(cam)
	cam.look_at(Vector3(0, 1.2, 0))
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0])
	get_tree().quit(0)
