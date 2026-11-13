extends Node
# T337 probe (user 2026-11-08: "Any mech that holds the gun from behind instead of from the bottom
# now has shells shooting through its body"; picked "eject from mid-gun" over moving the guns):
# on every roster mech, with its default guns, a casing's first 0.3 s of flight (from the game's
# own ejection point, Casings.port; mean speeds, with and without the back push) stays out of
# every torso box. A failing slot prints how far forward its port would have to be.

const Lobby := preload("res://scripts/Lobby.gd")
const Casings := preload("res://scripts/Casings.gd")

func _fail(msg: String) -> void:
	push_error("[probe] casing_clearance FAIL: " + msg)
	get_tree().quit(1)

func _boxes(m: Node) -> Array:  # [global transform, half size] of torso boxes, guns excluded
	var out := []
	for mi in (m.get("torso") as Node).find_children("*", "MeshInstance3D", true, false):
		var p: Node = mi.get_parent()
		var in_gun := false
		while p != null and p != m:
			if String(p.name).begins_with("Hardpoint"):
				in_gun = true
				break
			p = p.get_parent()
		if in_gun or not ((mi as MeshInstance3D).mesh is BoxMesh) or not (mi as Node3D).is_visible_in_tree():
			continue
		out.append([(mi as Node3D).global_transform, ((mi as MeshInstance3D).mesh as BoxMesh).size * 0.5])
	return out

# first time step at which the casing path from `w` is inside a torso box (-1 = clear), with
# the gun pushed `dz` along the mech's forward
func _hit(m: Node3D, w: Node3D, boxes: Array, dz: float) -> float:
	var b := w.global_transform.basis
	var s: float = Casings.casing_scale(w)
	var fwd := -m.global_transform.basis.z.normalized()
	var p0: Vector3 = Casings.port(w) + fwd * dz  # the game's own ejection point
	var margin := Casings.SIZE.z * 0.5 * s
	for back in [0.0, 1.0]:
		var v: Vector3 = Casings.launch(w, 0.5, 0.5, float(back))  # the game's own launch, mean spread
		for k in 16:
			var t := 0.02 * k
			var p: Vector3 = p0 + v * t + Vector3(0, -Casings.GRAVITY * 0.5 * t * t, 0)
			for bx in boxes:
				var l: Vector3 = (bx[0] as Transform3D).affine_inverse() * p
				var h: Vector3 = bx[1]
				var sc: Vector3 = (bx[0] as Transform3D).basis.get_scale()
				var mg := Vector3(margin / maxf(sc.x, 0.01), margin / maxf(sc.y, 0.01), margin / maxf(sc.z, 0.01))
				if absf(l.x) < h.x + mg.x and absf(l.y) < h.y + mg.y and absf(l.z) < h.z + mg.z:
					return t
	return -1.0

const EJECTORS := [["RifleLight", "SniperLight", "MachineGunLight", "ShotgunLight"],
	["RifleHeavy", "SniperHeavy", "MachineGunHeavy", "ShotgunHeavy"]]  # by slot size: the casing guns

func _ready() -> void:
	var bad := []
	var rows := []
	var mechs: Array = Lobby.ROSTER.duplicate()
	for f in DirAccess.get_files_at("res://tools/kit_mechs/"):  # T341: code-built mechs before the roster too
		var p := "res://resources/mechs/%s.tres" % f.get_basename().capitalize()
		if f.ends_with(".js") and ResourceLoader.exists(p) and not mechs.has(p):
			mechs.append(p)
	for path in mechs:
		var md: Resource = load(path)
		var checked := 0
		for i in md.weapon_slots.size():  # every casing gun that fits each slot
			for wname in EJECTORS[clampi(int(md.weapon_slots[i].slot_size), 0, 1)]:
				var paths := []
				paths.resize(md.weapon_slots.size())
				paths.fill("")
				paths[i] = "res://scenes/weapons/%s.tscn" % wname
				var m: Node3D = md.scene.instantiate()
				m.scale = Vector3.ONE * md.body_scale
				MechVisuals.apply(m, md.display_name)
				add_child(m)
				m.set_physics_process(false)
				m.remove_from_group("mechs")
				MechVisuals.arm_display(m, md, paths)
				var boxes := _boxes(m)
				var w: Node3D = m.get_weapons()[i] if i < m.get_weapons().size() else null
				if w != null and _hit(m, w, boxes, 0.0) >= 0.0:
					var need := -1.0
					for k in range(1, 41):
						if _hit(m, w, boxes, 0.05 * k) < 0.0:
							need = 0.05 * k
							break
					bad.append("%s slot %d %s (needs %s forward)" % [md.display_name, i, wname, ("%.2f m" % need) if need > 0.0 else ">2 m"])
				checked += 1
				m.free()
		rows.append("%s %d" % [md.display_name, checked])
	if not bad.is_empty():
		_fail("casings fly through the body: " + ", ".join(bad))
		return
	print("[probe] casing_clearance done (guns checked per mech: %s)" % ", ".join(rows))
	get_tree().quit(0)
