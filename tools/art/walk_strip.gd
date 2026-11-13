extends Node3D
# T380 art review: walk cycles side by side -- one row per mech, frames every FRAME_S of a
# real walk at its walk_speed, side on. Rows share the clock, so cadence and step length compare.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 995x560 \
#     res://tools/art/walk_strip.tscn -- <out.png> Slip Cesh
const FRAMES := 6
const FRAME_S := 0.1
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var names: Array = args.slice(1) if args.size() > 1 else ["Slip", "Cesh"]
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
	var dt := 1.0 / 60.0
	for r in names.size():
		var md: Resource = load("res://resources/mechs/%s.tres" % names[r])
		var y := -float(r) * 3.6
		for i in FRAMES:
			var m: Node3D = md.scene.instantiate()
			m.scale = Vector3.ONE * md.body_scale
			MechVisuals.apply(m, md.display_name)
			m.position = Vector3((i - (FRAMES - 1) * 0.5) * 2.2, y, 0)
			m.rotation_degrees.y = 270.0  # facing +x
			add_child(m)
			m.set_physics_process(false)
			m.configure_weapons(md.weapon_slots)
			m.call("configure_legs", md.leg_hip_sweep, md.leg_bob_magnitude, md.leg_cycle_rate)
			var legs: Node = m.get("legs")
			var v: Vector3 = -m.global_transform.basis.z * md.walk_speed
			var t := 0.0
			while t < i * FRAME_S + 0.5 - 0.0001:  # 0.5 s run-up: amplitude settled
				t += dt
				legs.call("update_gait", v, m.global_transform.basis, md.leg_rotation_speed, md.walk_speed, dt, false)
		var lbl := Label3D.new()
		lbl.text = "%s  %.2f m/s  sweep %.3f" % [md.display_name, md.walk_speed, md.leg_hip_sweep]
		lbl.font_size = 48
		lbl.pixel_size = 0.005
		lbl.position = Vector3(0, y + 2.6, 0)
		add_child(lbl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.8 * names.size() + 1.0
	cam.position = Vector3(0, 1.3 - 1.8 * (names.size() - 1), 20.0)
	add_child(cam)
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0])
	get_tree().quit(0)
