extends Node3D
# T533 probe (user 2026-11-20: "Found a race between a mech's shoulder and its weapon. I think it was a Denali
# with a machine gun; check that every weapon/mech combo has no same-coordinate surfaces. And a probe to
# check for future mechs and weapons."): for EVERY mech x catalog weapon x hardpoint it fits, the mech is
# built and armed as the game does (MechVisuals.apply + arm_display: kit models, weapon_scale, mounts),
# and every weapon triangle is checked against every mech-body triangle in one space: coplanar (same
# plane within PLANE_EPS) facing the SAME way AND overlapping in area (> AREA_EPS) = z-fighting. (Faces
# facing each other on one plane are flush contact: both hidden, no flicker.) Planes are bucketed by
# normal + distance, so only same-plane pairs are compared.

const PLANE_EPS := 0.001    # m (tools/art/zfight_solve.py keeps 1.5 mm: a 24-bit depth buffer parts that out to ~25 m)
const AREA_EPS := 0.0004    # m2 of in-plane overlap (2 x 2 cm)
const Lobby := preload("res://scripts/Lobby.gd")

func _fail(msg: String) -> void:
	push_error("[probe] weapon_zfight FAIL: " + msg)

## Triangles of every drawn MeshInstance3D under `root` (not under `skip`), in `space`'s frame:
## [[a, b, c, n], ...] with n the unit normal.
func _tris(root: Node, space: Node3D, skip: Array) -> Array:
	var out: Array = []
	var inv := space.global_transform.affine_inverse()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.layers == 0:
			continue
		var under := false
		for s in skip:
			if s != null and (s == mi or (s as Node).is_ancestor_of(mi)):
				under = true
		if under:
			continue
		var xf: Transform3D = inv * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var order: Array = Array(idx) if idx != null and (idx as PackedInt32Array).size() > 0 else range(v.size())
			for t in range(0, order.size() - 2, 3):
				var a: Vector3 = xf * v[order[t]]
				var b: Vector3 = xf * v[order[t + 1]]
				var c: Vector3 = xf * v[order[t + 2]]
				var nm := (b - a).cross(c - a)
				if nm.length() < 1e-7:
					continue
				out.append([a, b, c, nm.normalized(), str(space.get_path_to(mi))])
	return out

## A plane key: the (signed) normal rounded, and the distance.
func _key(n: Vector3, p: Vector3) -> Array:
	return [Vector3i(roundi(n.x * 500.0), roundi(n.y * 500.0), roundi(n.z * 500.0)), n.dot(p), n]

## In-plane overlap area of two coplanar triangles, m2.
func _overlap(t1: Array, t2: Array, n: Vector3) -> float:
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := n.cross(u)
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for i in 3:
		a.append(Vector2(u.dot(t1[i]), w.dot(t1[i])))
		b.append(Vector2(u.dot(t2[i]), w.dot(t2[i])))
	var area := 0.0
	for poly in Geometry2D.intersect_polygons(a, b):
		var s := 0.0
		for i in poly.size():
			s += poly[i].cross(poly[(i + 1) % poly.size()])
		area += absf(s) * 0.5
	return area

## --dump=<file>: for tools/art/zfight_solve.py, every same-facing axis-aligned weapon / body face pair
## that overlaps in area and lies within DUMP_MM along its axis: {"mech", "slot", "weapon", "axis", "delta"}
## (delta = body plane - weapon plane, mech-local m).
const DUMP_MM := 0.02

func _axis(n: Vector3) -> int:
	for i in 3:
		if absf(n[i]) > 0.9999:
			return i
	return -1

func _ready() -> void:
	var dump_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dump="):
			dump_path = a.substr(7)
	var dump: Array = []
	var catalog: Array = Lobby.WEAPON_CATALOG
	var bad: Array = []
	var combos := 0
	for f in DirAccess.get_files_at("res://resources/mechs"):
		if not f.ends_with(".tres") or f.begins_with("Debug"):
			continue
		var md: Resource = load("res://resources/mechs/" + f)
		for slot_i in md.weapon_slots.size():
			var size: int = int(md.weapon_slots[slot_i].slot_size)
			for w in catalog:
				if int(w["slot_size"]) != size:
					continue
				var m: Node3D = md.scene.instantiate()
				m.scale = Vector3.ONE * md.body_scale
				MechVisuals.apply(m, md.display_name)
				add_child(m)
				m.set_physics_process(false)
				m.remove_from_group("mechs")
				var paths: Array = []
				for i in md.weapon_slots.size():
					paths.append(w["path"] if i == slot_i else "")
				MechVisuals.arm_display(m, md, paths)
				var weapon: Node3D = null
				for c in (m.get("torso") as Node3D).find_children("*", "Node3D", true, false):
					if c.scene_file_path == w["path"]:
						weapon = c
						break
				if weapon == null:
					m.free()
					continue
				var others: Array = []
				for x in m.get_weapons():
					others.append(x)
				var body := _tris(m, m, others + [m.get_node_or_null("Torso/PhysicalShield")])
				var gun := _tris(weapon, m, [])
				if dump_path != "":
					for t in gun:
						var ax := _axis(t[3])
						if ax < 0:
							continue
						for t2 in body:
							if _axis(t2[3]) != ax or (t2[3] as Vector3).dot(t[3]) < 0.0:
								continue
							var delta: float = (t2[0] as Vector3)[ax] - (t[0] as Vector3)[ax]
							if absf(delta) <= DUMP_MM and _overlap(t, t2, t[3]) > AREA_EPS:
								dump.append({"mech": f, "slot": slot_i, "weapon": w["name"], "axis": ax, "delta": delta})
					combos += 1
					m.free()
					continue
				var planes := {}
				for t in body:
					var k := _key(t[3], t[0])
					for dd in [-1, 0, 1]:
						var kk := [k[0], roundi(k[1] / PLANE_EPS) + dd]
						if not planes.has(kk):
							planes[kk] = []
						planes[kk].append(t)
				var hit := ""
				var best := PLANE_EPS
				for t in gun:
					var k := _key(t[3], t[0])
					var kk := [k[0], roundi(k[1] / PLANE_EPS)]
					for t2 in planes.get(kk, []):
						var gap := absf(k[1] - (t2[0] as Vector3).dot(k[2]))
						if gap > best:
							continue
						var a := _overlap(t, t2, k[2])
						if a > AREA_EPS:
							best = gap
							hit = "%s + %s (slot %d): %s face at %s is %.1f mm off a face of %s (%.1f cm2)" % [
								md.display_name, w["name"], slot_i, t[4], ((t[0] + t[1] + t[2]) / 3.0).snapped(Vector3.ONE * 0.01),
								gap * 1000.0, t2[4], a * 10000.0]
				if hit != "":
					bad.append(hit)
				combos += 1
				m.free()
	if dump_path != "":
		var fa := FileAccess.open(dump_path, FileAccess.WRITE)
		fa.store_string(JSON.stringify(dump))
		fa.close()
		print("[probe] weapon_zfight dumped %d pairs over %d combos" % [dump.size(), combos])
		get_tree().quit(0)
		return
	if not bad.is_empty():
		_fail("%d of %d combos z-fight:\n%s" % [bad.size(), combos, "\n".join(bad)])
		get_tree().quit(1)
		return
	print("[probe] weapon_zfight done (%d mech x weapon x slot combos, no shared faces)" % combos)
	get_tree().quit(0)
