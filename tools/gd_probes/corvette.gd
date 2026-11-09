extends Node
# T235 probe (ship interior, roofed; T303: 30% smaller): the map loads with 5 beacons and 3
# spawns a side, all inside the hull, and
# the shoulder camera never ends up in or touching a wall / the ceiling: with the mech's
# back to a corridor wall, looking steeply down under the ceiling, and dropping from 5 m,
# the camera keeps CLEAR m from every solid (a ray-only spring arm parks it 1 cm off the
# wall and the near plane cuts through).

const CLEAR := 0.1

class AimSrc extends "res://scripts/InputSource.gd":
	var aim := Vector2.ZERO
	func get_abs_aim():
		return aim

func _fail(msg: String) -> void:
	push_error("[probe] corvette: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Corvette.tres")
	Game.loadout["squad"] = ["res://resources/mechs/Everest.tres"]  # the biggest: longest arm
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	if get_tree().get_nodes_in_group("beacons").size() != 5 or arena.spawn_points(0).size() != 2 or arena.spawn_points(1).size() != 2:
		_fail("want 5 beacons and 2 spawns a side (T358)")
	# T358 (user on T303: spawns "partly inside the wall ... Make sure mechs can't stick into the
	# walls"): every spot of a full 6-mech team line at every spawn has room for the biggest mech
	# (Everest: capsule r 0.5 x 1.25) -- no wall, crate or other team spot in it
	await get_tree().physics_frame
	var room := CapsuleShape3D.new()
	room.radius = 0.5 * 1.25 + 0.3
	room.height = 2.0 * 1.25
	var rq := PhysicsShapeQueryParameters3D.new()
	rq.shape = room
	rq.collision_mask = 1
	var sspace: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	for t in 2:
		for sp in arena.spawn_points(t).size():
			var spots: Array = []
			for idx in 6:
				var p: Vector3 = arena.spawn_position(t, idx, 6, sp)
				rq.transform = Transform3D(Basis(), p + Vector3.UP * (room.height * 0.5 + 0.05))
				for h in sspace.intersect_shape(rq, 4):
					if not (h["collider"] as Node).is_in_group("mechs"):
						_fail("team %d spawn %d slot %d at %s is inside %s" % [t, sp, idx, p, (h["collider"] as Node).name])
				for q2 in spots:
					if Vector2(p.x - q2.x, p.z - q2.z).length() < 2.6:
						_fail("team %d spawn %d: two slots %.1f m apart at %s" % [t, sp, Vector2(p.x - q2.x, p.z - q2.z).length(), p])
				spots.append(p)
	# T303 (user 2026-11-05: "feels very spread out, shrink it by 30%"): the hull is 0.7 x the
	# T235 184 x 92 m, and every beacon and spawn is inside it
	var map: Node = arena.get("_map")
	var hx: float = map.get("HX")
	var hz: float = map.get("HZ")
	if absf(hx * 2.0 - 184.0 * 0.7) > 0.5 or absf(hz * 2.0 - 92.0 * 0.7) > 0.5:
		_fail("hull %.1f x %.1f m, want 0.7 x 184 x 92" % [hx * 2.0, hz * 2.0])
	var inside: Array = []
	for b in get_tree().get_nodes_in_group("beacons"):
		inside.append((b as Node3D).global_position)
	inside.append_array(arena.spawn_points(0) + arena.spawn_points(1))
	for p in inside:
		if absf(p.x) > hx or absf(p.z) > hz:
			_fail("%s is outside the %.1f x %.1f m hull" % [p, hx * 2.0, hz * 2.0])
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = true
			if m != arena.get("player_mech"):
				m.process_mode = Node.PROCESS_MODE_DISABLED
	var m: CharacterBody3D = arena.get("player_mech")
	var src := AimSrc.new()
	m.add_child(src)
	m.set_input_source(src)
	var cam: Camera3D = m.get("camera")
	var space: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
	var ball := SphereShape3D.new()
	ball.radius = CLEAR
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.collision_mask = 1
	q.exclude = [m.get_rid()]
	# [position, yaw, pitch, label]: corridor z = -30 spans -35.5..-24.5
	var cases := [[Vector3(-40, 0.2, -26.0), 0.0, -0.3, "back to a corridor wall"],
		[Vector3(-40, 0.2, -26.0), PI * 0.5, -0.3, "side to a corridor wall"],
		[Vector3(-40, 0.2, -34.0), PI, -0.3, "back to the other wall"],
		[Vector3(0, 0.2, 0), 0.0, -1.2, "looking straight down under the ceiling"],
		[Vector3(-40, 5.0, -30.0), 0.0, -1.2, "dropping from 5 m, looking down"]]
	var worst := INF
	for c in cases:
		m.global_position = c[0]
		m.velocity = Vector3.ZERO
		src.aim = Vector2(c[1], c[2])
		for i in 40:
			await get_tree().physics_frame
			if i < 2:
				continue  # the case just snapped aim / position; the arm re-casts on the next tick
			q.transform = Transform3D(Basis(), cam.global_position)
			var hits := space.intersect_shape(q, 4)
			if not hits.is_empty():
				_fail("%s: camera at %s touches %s" % [c[3], cam.global_position, (hits[0]["collider"] as Node).name])
				break
			if cam.global_position.y > 10.0 - CLEAR:
				_fail("%s: camera at y %.2f, above the ceiling" % [c[3], cam.global_position.y])
				break
	print("[probe] corvette done (%d camera cases)" % cases.size())
	get_tree().quit(0)
