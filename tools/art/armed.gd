extends Node3D
# T265 art review: each mech with its default weapons at its real weapon_scale, close up,
# from the front-left 3/4 and from the side, one PNG per mech:
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/armed.tscn -- <out_dir> [flash] [Mech ...]   (default: the 9 roster mechs;
#     "flash" fires every weapon's muzzle flash just before the capture -- T317)
const ROSTER := ["Everest", "Kestrel", "Pegasus", "Seeker", "Hornet", "Vesuvius", "Slip", "Hippogriff", "Cesh"]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var flash := args.size() > 1 and args[1] == "flash"
	var names: Array = args.slice(2 if flash else 1)
	if names.is_empty():
		names = ROSTER
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
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	for n in names:
		var md: Resource = load("res://resources/mechs/%s.tres" % n)
		var holder := Node3D.new()
		add_child(holder)
		for k in 2:  # left: 3/4 front, right: side
			var m: Node3D = md.scene.instantiate()
			m.scale = Vector3.ONE * md.body_scale
			MechVisuals.apply(m, md.display_name)
			m.position = Vector3(-1.6 if k == 0 else 1.6, 0, 0) * md.body_scale
			m.rotation_degrees.y = 210.0 if k == 0 else 270.0
			holder.add_child(m)
			m.set_physics_process(false)
			m.weapon_scale = md.weapon_scale
			m.configure_weapons(md.weapon_slots)
		var h: float = 2.0 * md.body_scale
		cam.position = Vector3(0, h * 0.9, 7.5 * md.body_scale)
		cam.look_at(Vector3(0, h * 0.62, 0))
		for i in 4:
			await get_tree().process_frame
		if flash:
			get_tree().current_scene = self  # flashes go under the current scene
			for m in holder.get_children():
				for w in m.call("get_weapons"):
					w.call("_muzzle_flash", false)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
		holder.free()
	get_tree().quit(0)
