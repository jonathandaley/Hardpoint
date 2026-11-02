extends Node
# T169 probe: bot combat behaviour in a single-player Arena.
#  1. bots get varied loadouts (not all rifles) and heavy slots get heavy weapons;
#  2. a bot shot by someone other than its target turns on the attacker, unless its
#     current target is nearly dead; a second shooter can't flip it straight back;
#  3. a bot carrying a lock weapon acquires a lock through the shared lock system (V15).

const Lobby := preload("res://scripts/Lobby.gd")

func _fail(msg: String) -> void:
	push_error("[probe] bot_combat: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []  # SP path
	Game.loadout["mech_def"] = load("res://resources/mechs/Hippogriff.tres")
	Game.loadout["bot_def"] = load("res://resources/mechs/Hippogriff.tres")
	Game.loadout["team_size"] = 3
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 30:
		await get_tree().physics_frame

	var team0: Array = []
	var team1: Array = []
	var paths := {}
	for m in get_tree().get_nodes_in_group("mechs"):
		(team0 if m.team == 0 else team1).append(m)
		if m.name != "PlayerMech":
			for w in m.get_weapons():
				paths[w.scene_file_path] = true
	# 1. loadouts: 5 bots x 3 light slots from 8 light weapons -> all-rifle odds ~1e-14
	if paths.keys() == ["res://scenes/weapons/RifleLight.tscn"]:
		_fail("every bot still carries only rifles")
	var rng := RandomNumberGenerator.new()
	for p in Lobby.bot_weapon_paths(load("res://resources/mechs/Vesuvius.tres"), rng):
		if not String(p).ends_with("Heavy.tscn"):
			_fail("heavy slot got a non-heavy weapon: %s" % p)

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
	print("[probe] bot_combat done (weapons seen: %d, locked: %s, roles: %s)" % [paths.size(), locked, roles])
	get_tree().quit(0)
