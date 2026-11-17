extends Node
# T448 probe (user 2026-11-17: yes to Badlands' "adobe-brick pixel texture plus a few rusted vehicle
# hulks or dead shrubs between the ruins"): the ruin walls draw with a nearest-filtered,
# world-triplanar brick tile; there are hulks and scrub, none on a beacon pad or a spawn; and the
# colliders are exactly what Badlands had before (hulks and scrub are visual only).
const BODIES_BEFORE := 621  # Badlands at 486ee1e (before T448)

func _fail(msg: String) -> void:
	push_error("[probe] badlands_dressing: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Badlands.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	var map: Node = arena.get("_map")
	var consts: Dictionary = map.get_script().get_script_constant_map()
	var bad := 0
	var bodies := 0
	var walls := 0
	var bricked := 0
	var hulks := 0
	var twigs := 0
	for n in map.find_children("*", "", true, false):
		if n is CollisionShape3D:
			bodies += 1
		if not n is MeshInstance3D:
			continue
		var mi := n as MeshInstance3D
		var m := mi.material_override as StandardMaterial3D
		if mi.get_parent().is_in_group(&"ruins") and mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.y > 2.0:
			walls += 1
			if m != null and m.albedo_texture != null and m.uv1_world_triplanar and m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
				bricked += 1
		elif mi.get_parent() != map and not mi.get_parent() is CollisionObject3D and mi.mesh is BoxMesh and is_equal_approx((mi.mesh as BoxMesh).size.x, 4.4):
			hulks += 1
			_check_clear(mi.global_position, consts)
		elif mi.get_parent() == map and mi.mesh is BoxMesh and is_equal_approx((mi.mesh as BoxMesh).size.x, 0.08):
			twigs += 1
	if walls == 0 or bricked < walls * 0.9:
		bad += 1
		_fail("%d of %d ruin walls bricked" % [bricked, walls])
	if hulks < 8 or twigs < 200:
		bad += 1
		_fail("dressing thin: %d hulks, %d scrub twigs" % [hulks, twigs])
	bad += _bad_spots
	print("[probe] badlands_dressing: %d/%d walls bricked, %d hulks, %d twigs, %d colliders" % [bricked, walls, hulks, twigs, bodies])
	if BODIES_BEFORE >= 0 and bodies != BODIES_BEFORE:
		bad += 1
		_fail("colliders changed: %d, was %d" % [bodies, BODIES_BEFORE])
	print("[probe] badlands_dressing: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)

var _bad_spots := 0
func _check_clear(p: Vector3, consts: Dictionary) -> void:
	for b in consts["BEACONS"]:
		if Vector2(p.x, p.z).distance_to(b) < 12.0:
			_bad_spots += 1
			_fail("a hulk at %s sits on the beacon at %s" % [p, b])
	for team in consts["SPAWNS"]:
		for s in team:
			if Vector2(p.x, p.z).distance_to(s) < 18.0:
				_bad_spots += 1
				_fail("a hulk at %s sits on the spawn at %s" % [p, s])
