extends Node
# T169 probe: bot combat behaviour in a single-player Arena.
#  1. bots get varied loadouts (not all rifles), heavy slots get heavy weapons, and
#     each bot carries ONE weapon family in every slot (T171);
#  2. a bot shot by someone other than its target turns on the attacker, unless its
#     current target is nearly dead; a second shooter can't flip it straight back;
#  3. a bot carrying a lock weapon acquires a lock through the shared lock system (V15);
#  4. T172/B67: the navmesh bakes from the arena (it was 0 polygons) and reaches every beacon;
#  5. T172: Elite aim leads a moving target by velocity x projectile flight time;
#  6. T172: on a team preset, a hit bot's nearby teammate hears who shot it.

const Lobby := preload("res://scripts/Lobby.gd")

func _fail(msg: String) -> void:
	push_error("[probe] bot_combat: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []  # Arena sets up SP from the loadout (T184)
	Game.loadout["team_size"] = 3
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):  # T187: keep slot 0, as a player would
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 30:
		await get_tree().physics_frame

	var team0: Array = []
	var team1: Array = []
	var paths := {}
	for m in get_tree().get_nodes_in_group("mechs"):
		(team0 if m.team == 0 else team1).append(m)
		if m != arena.get("player_mech"):
			var fams := {}
			for w in m.get_weapons():
				paths[w.scene_file_path] = true
				fams[w.scene_file_path.get_file().trim_suffix(".tscn").trim_suffix("Light").trim_suffix("Heavy")] = true
			if fams.size() != 1:
				_fail("%s has a patchwork loadout %s" % [m.name, fams.keys()])
	# 1. loadouts: 5 bots, one of 8 light families each -> all-rifle odds 8^-5 ~ 3e-5
	if paths.keys() == ["res://scenes/weapons/RifleLight.tscn"]:
		_fail("every bot still carries only rifles")
	var rng := RandomNumberGenerator.new()
	for i in 20:
		var vp: Array = Lobby.bot_weapon_paths(load("res://resources/mechs/Vesuvius.tres"), rng)
		for p in vp:
			if not String(p).ends_with("Heavy.tscn"):
				_fail("heavy slot got a non-heavy weapon: %s" % p)
		if vp.any(func(p): return p != vp[0]):
			_fail("Vesuvius got a patchwork loadout %s" % [vp])

	# 1b. every bot has its own RNG seed (one shared stream = one role for all bots)
	var ids := {}
	var roles: Array = []
	for m in team0 + team1:
		var src: Node = m.get("_input_source")
		if src != null and "bot_id" in src:
			ids[src.bot_id] = true
			roles.append(src.role)
	if ids.size() != roles.size():
		_fail("bots share RNG seeds (bot_id values %s for %d bots)" % [ids.keys(), roles.size()])

	# 2. retaliation. E = enemy bot, A = its target (player), B / C = other team-0 mechs.
	var e: Node = team1[0]
	var ai: Node = e.get("_input_source")
	var a: Node = arena.get("player_mech")
	a.invincible = true  # 1 run in 16 the bots killed this idle player mech first -> no lock target
	var others := team0.filter(func(m): return m != a)
	var b: Node = others[0]
	var c: Node = others[1]
	for m in [e, a, b, c]:
		m.invincible = false
	ai.set("_target", a)
	ai.set("_retaliate_cd", 0.0)
	# shooters within weapon range of E and hits <= 1.5x weapon damage (min 0.6), or
	# request_damage's server-side validation drops them (SP counts as server too)
	(b as Node3D).global_position = (e as Node3D).global_position + Vector3(20, 0, 0)
	(c as Node3D).global_position = (e as Node3D).global_position + Vector3(-20, 0, 0)
	e.take_damage(0.5, b.get_weapons()[0])
	if ai.get("_target") != b:
		_fail("shot by B while targeting A, still on %s" % ai.get("_target"))
	e.take_damage(0.5, c.get_weapons()[0])
	if ai.get("_target") != b:
		_fail("second shooter flipped the target straight back (no cooldown)")
	# finishing exception: A nearly dead + clear shot -> stay on A
	ai.set("_target", a)
	ai.set("_retaliate_cd", 0.0)
	ai.set("_has_clear_shot", true)
	a.health = a.max_health * 0.1
	e.take_damage(0.5, b.get_weapons()[0])
	if ai.get("_target") != a:
		_fail("dropped a nearly dead target to retaliate")
	a.health = a.max_health

	# 3. lock: mark one of E's weapons lock-only, park E 15 m from team 0, no damage.
	e.get_weapons()[0].requires_lock = true
	e.invincible = true  # no hits -> no retaliation switches during the lock window
	for m in team0:  # B115: the other bots may kill E's only targets inside the 10 s window
		m.invincible = true
	var a3 := a as Node3D
	(e as Node3D).global_position = a3.global_position - a3.global_transform.basis.z * 15.0 + Vector3.UP * 3.0  # in front of A, facing it
	var locked := false
	for i in 60 * 10:
		await get_tree().physics_frame
		var lt = e.get("locked_target")
		if lt != null and is_instance_valid(lt) and lt.team != e.team:
			locked = true
			break
	if not locked:
		_fail("bot with a lock weapon never locked an enemy in 10 s")
	# 4. navmesh
	var nr: NavigationRegion3D = arena.get("_nav_region")
	var polys := 0
	for i in 600:  # threaded bake; then a few frames for the map to sync
		polys = nr.navigation_mesh.get_polygon_count() if nr != null else 0
		if polys > 0 and i > 5:
			break
		await get_tree().physics_frame
	if polys == 0:
		_fail("navmesh baked 0 polygons (B67)")
	else:
		var map: RID = arena.get_world_3d().navigation_map
		for bcn in get_tree().get_nodes_in_group("beacons"):
			var path := NavigationServer3D.map_get_path(map, a3.global_position, bcn.global_position, true)
			if path.is_empty() or path[path.size() - 1].distance_to(bcn.global_position) > 2.0:
				_fail("no nav path from team 0 to %s" % bcn.name)

	# 5. lead: target moving 3 m/s sideways, 55 m/s rifle -> aim 3 * t_flight ahead
	var rifle: Node = load("res://scenes/weapons/RifleLight.tscn").instantiate()
	ai.set("_target", a)
	(a as CharacterBody3D).velocity = Vector3(3.0, 0.0, 0.0)
	var centre: Vector3 = a3.call("center_mass")  # T319: bots aim at centre mass
	var led: Vector3 = ai.call("_aim_point", e, rifle, 1.0)
	var want: float = 3.0 * (e as Node3D).global_position.distance_to(centre) / 55.0
	if absf((led - centre).x - want) > want * 0.15 + 0.05:
		_fail("Elite lead %.2f m, expected ~%.2f m" % [(led - centre).x, want])
	if ai.call("_aim_point", e, rifle, 0.0) != centre:
		_fail("lead 0 should aim at the centre")
	rifle.free()

	# 6. help call: E's teammate F (Elite) within 60 m hears that B shot E
	var f: Node = team1[1]
	var fai: Node = f.get("_input_source")
	ai.difficulty = 4
	fai.difficulty = 4
	fai.set("_threat", null)
	e.invincible = false
	(f as Node3D).global_position = (e as Node3D).global_position + Vector3(0, 0, 15)
	(b as Node3D).global_position = (e as Node3D).global_position + Vector3(20, 0, 0)
	e.take_damage(0.5, b.get_weapons()[0])
	if fai.get("_threat") != b:
		_fail("teammate 15 m away never heard who shot E")
	print("[probe] bot_combat done (weapons seen: %d, locked: %s, roles: %s, nav polys: %d)" % [paths.size(), locked, roles, polys])
	get_tree().quit(0)
