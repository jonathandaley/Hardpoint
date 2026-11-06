extends Node
# T289 / T333 probe (HUMAN_FOUND 2026-11-05: rocket launcher "didn't work in Sydney"; 2026-11-06:
# "Make rockets be smarter to avoid hitting obstacles"): on every map, light rockets fired from
# where mechs stand (team 0 spawns + beacons) at a locked mech where enemies stand (beacons + team 1
# spawns), 25..170 m apart, must hit it at least MIN_RATE of the time on each map.

const MAPS := ["MathTemple", "Badlands", "City", "Forest", "Giza", "Swamp", "Factory", "Corvette"]
const HOMING := preload("res://scenes/weapons/HomingProjectile.tscn")
const MIN_RATE := 0.75
const MUZZLE_UP := 3.0

var _hits := {}

func _fail(msg: String) -> void:
	push_error("[probe] rocket_maps FAIL: " + msg)
	get_tree().quit(1)

func _rate(map: String) -> Vector2i:  # (hits, rockets)
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 4]  # one enemy per target spot: every spot at once
	Game.loadout["mode"] = "beacons"
	Game.loadout["map_def"] = load("res://resources/maps/%s.tres" % map)
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	var me: Node3D = arena.get("player_mech")
	var enemies: Array = arena.get("_team_mechs")[1 - int(me.get("team"))]
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
			m.process_mode = Node.PROCESS_MODE_DISABLED
			m.set("invincible", true)
	me.global_position = Vector3(0, -500, 0)  # out of the way
	var beacons: Array = []
	for b in get_tree().get_nodes_in_group("beacons"):
		beacons.append((b as Node3D).global_position)
	var origins: Array = arena.call("spawn_points", 0) + beacons
	var all_t: Array = beacons + arena.call("spawn_points", 1)
	var targets: Array = []
	for i in mini(4, all_t.size()):  # up to 4 spread over the list (beacons first)
		targets.append(all_t[i * all_t.size() / mini(4, all_t.size())])
	var shot := 0
	var hit := 0
	for k in enemies.size():
		(enemies[k] as Node3D).global_position = targets[k] if k < targets.size() else Vector3(0, -900 - 50 * k, 0)
	for i in 2:
		await get_tree().physics_frame
	var live: Array = []
	for k in mini(targets.size(), enemies.size()):
		var tp: Vector3 = targets[k]
		var enemy: Node3D = enemies[k]
		for op in origins:
			var d: float = (op as Vector3).distance_to(tp)
			if d < 25.0 or d > 170.0:
				continue
			var proj: Node3D = HOMING.instantiate()
			proj.speed = 18.0
			proj.lifetime = 180.0 / 18.0
			proj.team = 0
			proj.target = enemy
			proj.arc_time = 0.8
			proj.arc_up_blend = 0.65
			proj.turn_rate = 2.1
			var key := shot
			proj.on_hit = func(body, _pos) -> void:
				if body == enemy:
					_hits[key] = true
			add_child(proj)
			var from: Vector3 = op + Vector3.UP * MUZZLE_UP
			var flat: Vector3 = tp - from
			flat.y = 0.0
			proj.global_transform = Transform3D(Basis(), from).looking_at(from + flat.normalized())
			live.append(proj)
			shot += 1
	for i in 660:
		await get_tree().physics_frame
		if live.all(func(p): return not is_instance_valid(p)):
			break
	for p in live:  # none should be left; never quit with rockets in flight
		if is_instance_valid(p):
			p.queue_free()
	for k in _hits:
		hit += 1
	_hits.clear()
	arena.queue_free()
	for i in 3:
		await get_tree().process_frame
	return Vector2i(hit, shot)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 8.0  # rockets fly 10 s; the physics is the same, just sooner
	var rows := []
	var worst := 1.0
	var worst_map := ""
	for map in MAPS:
		var r: Vector2i = await _rate(map)
		var rate := float(r.x) / maxf(1.0, float(r.y))
		rows.append("%s %d/%d" % [map, r.x, r.y])
		print("[rocket_maps] " + rows[-1])  # not "[probe]": the suite reads that as finished
		if rate < worst:
			worst = rate
			worst_map = map
	Engine.time_scale = 1.0
	if worst < MIN_RATE:
		_fail("rockets hit only %.0f%% on %s (min %.0f%%): %s" % [worst * 100.0, worst_map, MIN_RATE * 100.0, ", ".join(rows)])
		return
	print("[probe] rocket_maps done (" + ", ".join(rows) + ")")
	get_tree().quit(0)
