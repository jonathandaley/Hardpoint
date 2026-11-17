extends Node
# T449 probe (user 2026-11-17: yes to Sydney's "lane markings, crosswalks and kerbs"): City has
# dashed centre lines, zebra crossings and a kerb round its blocks, none of it inside a building or
# on a beacon plaza, and nothing new collides (city_lowrise checks the collider count).

func _fail(msg: String) -> void:
	push_error("[probe] city_streets: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/City.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	var map: Node = arena.get("_map")
	var beacons: Array = map.get_script().get_script_constant_map()["BEACONS"]
	var solids: Array = []
	for b in map.get_children():
		if b is StaticBody3D:
			for c in b.get_children():
				if c is CollisionShape3D and c.shape is BoxShape3D and (c.shape as BoxShape3D).size.y > 2.0 and (c.shape as BoxShape3D).size.x < 60.0:
					var sz := (c.shape as BoxShape3D).size
					solids.append(Rect2(b.global_position.x - sz.x * 0.5, b.global_position.z - sz.z * 0.5, sz.x, sz.z))
	var dashes := 0
	var zebra := 0
	var kerbs := 0
	var bad := 0
	for n in map.get_children():
		if not n is MeshInstance3D or not (n as MeshInstance3D).mesh is BoxMesh:
			continue
		var s := ((n as MeshInstance3D).mesh as BoxMesh).size
		var p := Vector2(n.position.x, n.position.z)
		var kind := ""
		if is_equal_approx(s.y, 0.03) and (is_equal_approx(s.x, 0.25) or is_equal_approx(s.z, 0.25)):
			kind = "dash"
			dashes += 1
		elif is_equal_approx(s.y, 0.03) and (is_equal_approx(s.x, 0.7) or is_equal_approx(s.z, 0.7)):
			kind = "zebra"
			zebra += 1
		elif is_equal_approx(s.y, 0.2) and (is_equal_approx(s.x, 0.2) or is_equal_approx(s.z, 0.2)):
			kerbs += 1
		if kind == "":
			continue
		for r in solids:
			if (r as Rect2).has_point(p):
				bad += 1
				_fail("a %s at %s lies inside a building" % [kind, p])
				break
		for b in beacons:
			if absf(p.x - b.x) < 11.0 and absf(p.y - b.y) < 11.0:
				bad += 1
				_fail("a %s at %s is on the beacon plaza at %s" % [kind, p, b])
	if dashes < 60 or zebra < 40 or kerbs < 40:
		bad += 1
		_fail("streets thin: %d dashes, %d zebra stripes, %d kerbs" % [dashes, zebra, kerbs])
	print("[probe] city_streets: %d dashes, %d zebra, %d kerbs: %s" % [dashes, zebra, kerbs, "PASS" if bad == 0 else "FAIL %d" % bad])
	get_tree().quit(1 if bad else 0)
