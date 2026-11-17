extends Node
# T441 probe (user 2026-11-17: "the various smaller buildings are boring"): on City, every
# street-level building up to 20 m tall (kiosks, block podiums) has a lit shopfront band round its
# foot, podiums a parapet, the short towers on them (< 20 m) a parapet and roof plant -- and the dressing is
# visual only: the colliders are exactly the ones City had before (count + total volume), so the
# T221 lanes and bot paths are untouched.
const BODIES_BEFORE := 125  # City at 4709c9e (before T441)
const VOLUME_BEFORE := 525901.0

func _fail(msg: String) -> void:
	push_error("[probe] city_lowrise: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/City.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	var map: Node = arena.get("_map")
	var deco := {"Shopfront": [], "Parapet": [], "RoofPlant": []}
	for n in map.get_children():
		if n is MeshInstance3D and deco.has(n.get_meta(&"deco", "")):
			deco[n.get_meta(&"deco")].append((n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb())
	print("[probe] city_lowrise: deco %d shopfronts %d parapets %d plant" % [deco["Shopfront"].size(), deco["Parapet"].size(), deco["RoofPlant"].size()])
	var bodies := 0
	var volume := 0.0
	var bad := 0
	var checked := 0
	for b in map.get_children():
		if not b is StaticBody3D:
			continue
		for c in b.get_children():
			if c is CollisionShape3D:
				bodies += 1
				if c.shape is BoxShape3D:
					volume += (c.shape as BoxShape3D).size.x * (c.shape as BoxShape3D).size.y * (c.shape as BoxShape3D).size.z
		var box := _box_of(b)
		var on_podium := absf(box.position.y - 6.0) < 0.05
		if box.size.y < 2.5 or box.size.y > 20.0 or not (absf(box.position.y) < 0.05 or on_podium) or box.size.x < 3.0 or box.size.x > 40.0:
			continue  # not a low building (ground plate, trunks, walls, skyscrapers)
		checked += 1
		var foot := box.get_center() * Vector3(1, 0, 1) + Vector3(0, 1.2, 0)
		if not on_podium and not deco["Shopfront"].any(func(a: AABB) -> bool: return a.has_point(foot)):
			bad += 1
			if bad <= 3:
				_fail("building at %s (%.0f m tall) has no shopfront" % [foot, box.size.y])
		var podium := box.size.x > 30.0
		if podium or on_podium or box.size.y > 5.0:  # podiums: a parapet; short towers / infill: + roof plant
			var top := box.get_center() * Vector3(1, 0, 1) + Vector3(0, box.end.y + 0.3, 0)
			var roof := AABB(box.position + Vector3(0, box.size.y, 0), Vector3(box.size.x, 4.0, box.size.z))
			if not deco["Parapet"].any(func(a: AABB) -> bool: return a.intersects(roof)) \
					or not podium and not deco["RoofPlant"].any(func(a: AABB) -> bool: return a.intersects(roof)):
				bad += 1
				if bad <= 3:
					_fail("low building at %s has no parapet / roof plant" % top)
	if checked < 30:
		bad += 1
		_fail("only %d street-level buildings found" % checked)
	print("[probe] city_lowrise: bodies %d volume %.0f checked %d" % [bodies, volume, checked])
	if BODIES_BEFORE >= 0 and (bodies != BODIES_BEFORE or absf(volume - VOLUME_BEFORE) > 1.0):
		bad += 1
		_fail("colliders changed: %d bodies / %.0f m3, was %d / %.0f" % [bodies, volume, BODIES_BEFORE, VOLUME_BEFORE])
	print("[probe] city_lowrise: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)

static func _box_of(b: StaticBody3D) -> AABB:
	for c in b.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			var s := (c.shape as BoxShape3D).size
			return AABB(b.global_position + c.position - s * 0.5, s)
	return AABB()
