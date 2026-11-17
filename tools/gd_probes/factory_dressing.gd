extends Node
# T447 probe (user 2026-11-17: yes to Factory's "pipe runs along the bulkheads, hazard stripes on
# the ramp edges, a gantry crane over the deck, painted deck numbers by the beacons"): Factory has
# pipes on the bulkheads, hazard-striped strips at the ramps, a crane whose beam is high over the
# deck and whose legs stand outside the boundary, and painted digits by each beacon -- all visual:
# the colliders are exactly those Factory had before.
const BODIES_BEFORE := 57  # Factory at da5b481 (before T447)

func _fail(msg: String) -> void:
	push_error("[probe] factory_dressing: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Factory.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	var map: Node = arena.get("_map")
	var half: float = map.get_script().get_script_constant_map()["HALF"]
	var beacons: Array = map.get_script().get_script_constant_map()["BEACONS"]
	var bad := 0
	var pipes := 0
	var hazard := 0
	var beam := false
	var legs_out := 0
	var paint: Array = []
	var bodies := 0
	for n in map.find_children("*", "", true, false):
		if n is CollisionShape3D:
			bodies += 1
		if not n is MeshInstance3D or n.get_parent() != map:
			continue
		var mi := n as MeshInstance3D
		var m := mi.material_override as StandardMaterial3D
		var box := mi.global_transform * mi.get_aabb()
		if mi.mesh is CylinderMesh and absf(mi.rotation.x - PI * 0.5) < 0.01:
			pipes += 1
		if m != null and m.albedo_texture != null and m.albedo_texture.get_width() == 8:
			hazard += 1
		if box.size.x > half * 2.0 and box.position.y > 20.0:
			beam = true
		if box.size.y > 20.0 and absf(box.get_center().x) > half:
			legs_out += 1
		if box.size.y < 0.03 and box.size.x < 0.7 and box.position.y > 0.06:
			paint.append(box.get_center())
	if pipes < 12 or hazard < 8 or not beam or legs_out != 2:
		bad += 1
		_fail("dressing missing: %d pipes, %d hazard strips, beam %s, %d legs outside the boundary" % [pipes, hazard, beam, legs_out])
	for b in beacons:
		if not paint.any(func(p: Vector3) -> bool: return Vector2(p.x, p.z).distance_to(b) < 9.0):
			bad += 1
			_fail("no painted number by the beacon at %s" % b)
	print("[probe] factory_dressing: %d pipes, %d hazard, %d paint squares, %d colliders" % [pipes, hazard, paint.size(), bodies])
	if BODIES_BEFORE >= 0 and bodies != BODIES_BEFORE:
		bad += 1
		_fail("colliders changed: %d, was %d" % [bodies, BODIES_BEFORE])
	print("[probe] factory_dressing: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)
