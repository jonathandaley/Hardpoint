extends Node
# T237 probe (HUMAN_FOUND_ISSUES 2026-11-04: "Vesuvius crosshair is obstructed by his giant
# shoulder"): for every roster mech, in its armed kit look, the over-the-shoulder camera's
# crosshair ray (screen centre, straight ahead) misses every triangle of the player's own
# mech -- both shoulders, level and looking down.

const MechVisuals := preload("res://scripts/MechVisuals.gd")

func _fail(msg: String) -> void:
	push_error("[probe] crosshair_clear: " + msg)

func _hits_self(m: Node3D, from: Vector3, dir: Vector3) -> String:
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var n := mi as MeshInstance3D
		if n.mesh == null or not n.is_visible_in_tree():
			continue
		var xf := n.global_transform
		var faces := n.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			if Geometry3D.ray_intersects_triangle(from, dir, xf * faces[i], xf * faces[i + 1], xf * faces[i + 2]) != null:
				return String(n.get_path()).get_slice("/", -1) if n.get_parent() == null else "%s/%s" % [n.get_parent().name, n.name]
	return ""

func _ready() -> void:
	var hangar: Script = load("res://scripts/Hangar.gd")
	var roster: Array = hangar.get_script_constant_map()["ROSTER"]
	var checked := 0
	for path in roster:
		var md: Resource = load(path)
		if md == null or String(md.display_name) == "DEBUG":
			continue
		var m: Node3D = md.scene.instantiate()
		m.scale = Vector3.ONE * md.body_scale
		MechVisuals.apply(m, md.display_name)
		m.set("owner_peer_id", multiplayer.get_unique_id())  # runs the shoulder camera like the player's own
		add_child(m)
		m.set_physics_process(false)
		m.weapon_scale = md.weapon_scale  # its default weapons: guns on a shoulder block the view too
		m.configure_weapons(md.weapon_slots)
		var cam: Camera3D = m.get("camera")
		for side in [0.0, 1.0, -1.0]:  # T252: center view (0) too
			Game.shoulder = side
			# the eased swap (6 u/s, <= 3.6 u) settles in 0.6 s; pitch applies next frame. B135: one wait
			# per side, not per pitch -- 10 mechs x 4.2 s ran past the suite's 6000-frame cap
			await get_tree().create_timer(0.7).timeout
			for pitch in [0.0, -0.6]:
				m.set("_camera_pitch", pitch)
				await get_tree().process_frame
				await get_tree().process_frame
				var dir := -cam.global_transform.basis.z
				var hit := _hits_self(m, cam.global_position, dir)
				if hit != "":
					_fail("%s (side %+.0f, pitch %.1f): the crosshair ray hits its own %s" % [md.display_name, side, pitch, hit])
		checked += 1
		m.queue_free()
	Game.shoulder = 1.0
	print("[probe] crosshair_clear done (%d mechs)" % checked)
	get_tree().quit(0)
