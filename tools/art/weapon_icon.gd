extends Node
# T457: a HUD icon (assets/hardpoint/hud-icon-*.png: 116 x 68, transparent) from a weapon scene's
# kit model, side-on, muzzle right -- for weapons added after the design kit's icon set.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot res://tools/art/weapon_icon.tscn -- <out.png> <scene path>
const WeaponVisuals := preload("res://scripts/WeaponVisuals.gd")
const SIZE := Vector2i(116, 68)
const SS := 4  # supersample, then shrink (smooth edges like the kit's icons)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var vp := SubViewport.new()
	vp.size = SIZE * SS
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.32, 0.34, 0.42)  # the kit icons are dark gunmetal
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 0.55
	vp.add_child(sun)
	var w: Node3D = load(args[1]).instantiate()
	vp.add_child(w)
	WeaponVisuals.apply(w)
	w.rotation_degrees.y = -90.0  # muzzle (-Z) -> +X
	var box := AABB()
	var first := true
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.y * 1.15, box.size.x * 1.15 * float(SIZE.y) / float(SIZE.x))
	vp.add_child(cam)
	cam.position = box.get_center() + Vector3(0, 0, 10)
	cam.current = true
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	img.save_png(args[0])
	get_tree().quit(0)
