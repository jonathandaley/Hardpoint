extends Node
# T434 probe (user 2026-11-16: "Write beacon rush, have the game modes be a menu"): in BEACON RUSH
# the spawn picker adds a button on each beacon the team holds (none at the start); picking one
# lands the next mech on that beacon's pad; a beacon lost while picking sends it home; bots never
# pick a beacon they don't hold. Every map: each of 5 lanes round every beacon is open floor.

const CAP_R := 0.5   # Mech.tscn capsule
const CAP_H := 2.0

func _fail(msg: String) -> void:
	push_error("[probe] beacon_rush FAIL: " + msg)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _buttons(hud: Node) -> Array:
	return hud.get("_spawn_ui").filter(func(n) -> bool: return n is Button and String(n.name) != "SpawnBack")  # names get @-mangled while the last set frees

func _player(arena: Node) -> Node3D:
	return arena.get("player_mech")

func _flow(arena: Node) -> void:  # on the first map
	var hud: Node = arena.get("hud")
	var homes: int = (arena.get("_map") as Node).call("spawn_points", 0).size()
	var bs: Array = arena.get("_rush_beacons")
	if bs.size() != 5 or arena.spawn_points(0).size() != homes + 5:
		_fail("rush spawn list %d (homes %d + beacons %d)" % [arena.spawn_points(0).size(), homes, bs.size()])
		return
	if arena.spawn_open(0, homes):
		_fail("a neutral beacon is open to spawn at")
	hud.show_spawn_picker(arena.spawn_choices(0))
	if _buttons(hud).size() != homes:
		_fail("start: picker shows %d spawns, want the %d home points" % [_buttons(hud).size(), homes])
	hud.hide_spawn_picker()
	await get_tree().process_frame  # the old buttons free first (their names are reused)
	var b: Node3D = bs[0]
	b.set("owner_team", 0)
	b.set("state", 1)  # TEAM_A
	hud.show_spawn_picker(arena.spawn_choices(0))
	var btns := _buttons(hud)
	var mm: Control = hud.get("minimap")
	var on_b := btns.filter(func(n) -> bool: return (n as Button).text == str(homes + 1))
	if btns.size() != homes + 1 or on_b.is_empty() \
			or ((on_b[0] as Control).position + (on_b[0] as Control).size * 0.5).distance_to(mm.to_map(b.global_position)) > 1.0:
		_fail("held beacon: picker shows %d spawns (want %d), beacon button %s" % [btns.size(), homes + 1, on_b])
	hud.hide_spawn_picker()
	b.set("state", 3)  # CONTESTED
	if arena.spawn_open(0, homes):
		_fail("a contested beacon is open")
	b.set("state", 1)
	# die, respawn on the beacon
	arena.call("_self_destruct", 1)
	await _frames(5)
	arena.call("_process_pick_next_mech", 1, 1, homes)
	await _frames(40)
	var m := _player(arena)
	var d := Vector2(m.global_position.x - b.global_position.x, m.global_position.z - b.global_position.z).length()
	if m.is_dead or d > arena.RUSH_SPAWN_R + 1.0 or absf(m.global_position.y - b.global_position.y) > 2.0 or not m.is_on_floor():
		_fail("respawn at held beacon: %.1f m from it, dy %.1f, on floor %s" % [d, m.global_position.y - b.global_position.y, m.is_on_floor()])
	# T496: a mech on a beacon pad faces the enemy's side
	var foe: Vector3 = arena.spawn_points(1)[0]
	var fwd: Vector3 = -(m as Node3D).global_transform.basis.z
	var to_foe := Vector2(foe.x - m.global_position.x, foe.z - m.global_position.z).normalized()
	if Vector2(fwd.x, fwd.z).normalized().dot(to_foe) < 0.9:
		_fail("respawned at a beacon facing %.0f deg off the enemy's side" % rad_to_deg(acos(clampf(Vector2(fwd.x, fwd.z).normalized().dot(to_foe), -1.0, 1.0))))
	# T501: contested after the click -> still spawns there
	b.set("state", 3)  # CONTESTED, still ours
	arena.call("_self_destruct", 1)
	await _frames(5)
	arena.call("_process_pick_next_mech", 1, 2, homes)
	await _frames(40)
	m = _player(arena)
	if m.is_dead or Vector2(m.global_position.x - b.global_position.x, m.global_position.z - b.global_position.z).length() > arena.RUSH_SPAWN_R + 1.0:
		_fail("a pick at a beacon contested after the click didn't spawn there (%s)" % m.global_position)
	# T501: lost outright while picking -> back to the picker, the slot unspent, no home spawn
	b.set("owner_team", 1)
	b.set("state", 2)  # TEAM_B
	if arena.bot_spawn(0) >= homes:
		_fail("a team-0 bot picked spawn %d (beacons all neutral / enemy)" % arena.bot_spawn(0))
	arena.call("_self_destruct", 1)
	await _frames(5)
	var used_before: Array = (arena.get("_peer_slot_used")[1] as Array).duplicate()
	arena.call("_process_pick_next_mech", 1, 3, homes)
	await _frames(10)
	var alive := false
	for mm2 in arena.get("_team_mechs")[0]:
		if is_instance_valid(mm2) and int(mm2.get("owner_peer_id")) == 1 and not mm2.get("is_dead"):
			alive = true
	var picker = hud.get("_squad_picker")
	if alive or picker == null or not is_instance_valid(picker) or arena.get("_peer_slot_used")[1] != used_before:
		_fail("a pick at a lost beacon: spawned %s, picker open %s, slots %s -> %s (want no spawn, the picker back, the slot unspent)" % [alive, picker != null and is_instance_valid(picker), used_before, arena.get("_peer_slot_used")[1]])
	b.set("owner_team", 1)
	if arena.spawn_open(1, homes) == false:
		_fail("team 1's own beacon not open to it")

func _lanes(arena: Node, map: String) -> int:  # every lane round every beacon: floor, nothing solid
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_R
	cap.height = CAP_H
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	var ex: Array[RID] = []
	for mm in get_tree().get_nodes_in_group("mechs"):
		ex.append((mm as CollisionObject3D).get_rid())
	q.exclude = ex
	var homes: int = (arena.get("_map") as Node).call("spawn_points", 0).size()
	var bad := 0
	for k in (arena.get("_rush_beacons") as Array).size():
		var by: float = (arena.get("_rush_beacons")[k] as Node3D).global_position.y
		for t in 2:
			for idx in 5:
				var at: Vector3 = arena.spawn_position(t, idx, 5, homes + k)
				var y: float = arena.call("_ground_y", at.x, at.z, by)
				q.transform = Transform3D(Basis(), Vector3(at.x, y + CAP_R + CAP_H * 0.5 + 0.1, at.z))
				var hits := space.intersect_shape(q, 4)
				if not hits.is_empty() or absf(y - by) > 1.5:
					bad += 1
					_fail("%s beacon %d lane %d team %d: %s, floor dy %.1f" % [map, k, idx, t,
						"inside %s" % hits[0]["collider"].name if not hits.is_empty() else "clear", y - by])
	return bad

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scenes := {}
	for f in DirAccess.get_files_at("res://resources/maps"):
		if f.ends_with(".tres"):
			var md: Resource = load("res://resources/maps/" + f)
			if not scenes.has(md.scene_path):
				scenes[md.scene_path] = md
	var first := true
	var bad := 0
	for sp in scenes:
		Game.mp_active_match["roster"] = []
		Game.loadout["team_size"] = 5
		Game.loadout["sp_bots"] = [4, 5]
		Game.loadout["mode"] = "rush"
		Game.loadout["map_def"] = scenes[sp]
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child.call_deferred(arena)
		for i in 2:
			await get_tree().process_frame
		if not arena.get("rush"):
			_fail("mode 'rush' didn't reach the arena")
			get_tree().quit(1)
			return
		if arena.get("_start_pick_open"):
			arena.get("hud").squad_slot_selected.emit(0)
			arena.get("hud").spawn_selected.emit(0)
		await _frames(5)
		for t in 2:  # bots parked: nobody walks into a beacon mid-check
			for m in arena.get("_team_mechs")[t]:
				if m != _player(arena):
					m.invincible = true
					m.process_mode = Node.PROCESS_MODE_DISABLED
		bad += _lanes(arena, String(sp).get_file().get_basename())
		if first:
			first = false
			await _flow(arena)
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	Game.loadout["mode"] = "beacons"
	print("[probe] beacon_rush done (%d maps, %d blocked lanes)" % [scenes.size(), bad])
	get_tree().quit(0)
