extends Node3D
# T180 art review: every weapon scene (light row front, heavy row back) after
# WeaponVisuals.apply, side-on (muzzle to the right).
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/weapon_rack.tscn -- <out.png>
const WeaponVisuals := preload("res://scripts/WeaponVisuals.gd")

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.58, 0.64)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var fams := ["Rifle", "Sniper", "MachineGun", "Shotgun", "MissileLauncher", "RocketLauncher", "LaserCannon", "ArcWeapon", "Patience", "AerialStrike"]
	for i in fams.size():
		for size in ["Light", "Heavy"]:
			var path := "res://scenes/weapons/%s%s.tscn" % [fams[i], size]
			if not ResourceLoader.exists(path):
				continue
			var w: Node3D = load(path).instantiate()
			WeaponVisuals.apply(w)
			w.position = Vector3((i % 5) * 2.6 - 5.2, 1.2 - (i / 5) * 1.9, 0.0 if size == "Light" else -1.4)
			w.rotation_degrees.y = -90.0  # muzzle (-Z) -> +X, to the right
			add_child(w)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.6, 9.5)
	cam.fov = 55
	add_child(cam)
	cam.look_at(Vector3(0, 0.3, -0.7))
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit(0)
