extends Node
# T340 probe: every code-built mech (tools/kit_mechs/<name>.js -> tools/new_mech.py) is in the
# game data -- MechKit has it, its pixel tiles exist, its MechDef (if any) has one weapon slot per
# kit mount sitting on that mount (allowing the T337 forward offsets), and the model builds with
# its torso, legs and guns.

const MechKit := preload("res://scripts/MechKit.gd")

func _fail(msg: String) -> void:
	push_error("[probe] kit_mechs FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var rows := []
	for f in DirAccess.get_files_at("res://tools/kit_mechs/"):
		if not f.ends_with(".js"):
			continue
		var low := f.get_basename()
		var name := low.capitalize()
		if not MechKit.DATA.has(name):
			_fail("%s: not in scripts/MechKit.gd -- rerun tools/kit_port.py" % f)
			return
		for ch in ["armor", "detail"]:
			if not ResourceLoader.exists("res://assets/hardpoint/textures/%s-%s.png" % [low, ch]):
				_fail("%s: no %s tile -- rerun tools/new_mech.py %s (tools/kit_tiles.gd)" % [f, ch, name])
				return
		var path := "res://resources/mechs/%s.tres" % name
		if not ResourceLoader.exists(path):
			rows.append("%s (no MechDef yet)" % name)
			continue
		var md: Resource = load(path)
		var mounts: Array = MechKit.DATA[name]["mounts"]
		if md.weapon_slots.size() != mounts.size():
			_fail("%s: %d weapon slots for %d kit mounts" % [name, md.weapon_slots.size(), mounts.size()])
			return
		for sl in md.weapon_slots:
			var best := INF
			for mp in mounts:
				best = minf(best, (sl.position as Vector3).distance_to(mp))
			if best > 0.6:
				_fail("%s: a weapon slot at %s sits %.2f m from the nearest mount" % [name, sl.position, best])
				return
		var m: Node3D = md.scene.instantiate()
		m.scale = Vector3.ONE * md.body_scale
		MechVisuals.apply(m, md.display_name)
		add_child(m)
		m.set_physics_process(false)
		m.remove_from_group("mechs")
		MechVisuals.arm_display(m, md, [])
		var boxes: int = (m.get("torso") as Node).find_children("*", "MeshInstance3D", true, false).size()
		if boxes < 5 or m.get_weapons().size() != md.weapon_slots.size():
			_fail("%s: model built %d torso meshes, %d guns for %d slots" % [name, boxes, m.get_weapons().size(), md.weapon_slots.size()])
			return
		rows.append("%s %d slots" % [name, md.weapon_slots.size()])
		m.free()
	print("[probe] kit_mechs done (%s)" % ", ".join(rows))
	get_tree().quit(0)
