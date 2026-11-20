extends Node
# T521 probe (user 2026-11-19: "Swarm: similar to aerial strike, but the bullets that miss circle around and
# strike again. 10% of hits spawn two more that find another target within 40m and hit that one
# instead."): SWARM HV is in the catalog; with the split forced (split_chance 1), an enemy hit with two
# other enemies within 40 m sends two new homing rockets, one at each, never at the one hit; none with
# nobody else in range; a teammate hit never splits; a split rocket doesn't split again.
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] swarm FAIL: " + msg)
	get_tree().quit(1)

func _rockets(arena: Node) -> Array:
	return arena.get_children().filter(func(n): return n is HomingProjectile and not n.is_ghost)

func _ready() -> void:
	var lobby: Script = load("res://scripts/Lobby.gd")
	var names: Array = (lobby.get_script_constant_map()["WEAPON_CATALOG"] as Array).map(func(w): return w["name"])
	if not names.has("SWARM HV"):
		_fail("SWARM HV isn't in the catalog")
		return
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 3
	Game.loadout["mode"] = "deathmatch"
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	get_tree().current_scene = arena  # rockets go under the current scene
	var shooter: Node3D = arena.get("_team_mechs")[1][0]
	var mate: Node3D = arena.get("_team_mechs")[1][1]
	var en: Array = arena.get("_team_mechs")[0]
	var InputSource := load("res://scripts/InputSource.gd")
	for m in [shooter] + en:
		var src: Node = InputSource.new()
		add_child(src)
		m.call("set_input_source", src)
	var slot = load("res://scripts/WeaponSlotDef.gd").new()
	slot.slot_size = 1
	slot.position = Vector3(0.7, 1.5, 0.3)
	slot.weapon_scene = load("res://scenes/weapons/SwarmHeavy.tscn")
	shooter.call("configure_weapons", [slot])
	for i in 5:
		await get_tree().physics_frame
	var w: Node = shooter.get_weapons()[0]
	w.set("split_chance", 1.0)
	var bad: Array = []
	# the hit enemy at the origin, two others 20 m and 30 m off; the shooter far
	shooter.global_position = Vector3(0, DECK_Y, 150)
	en[0].global_position = Vector3(0, DECK_Y, 0)
	en[1].global_position = Vector3(20, DECK_Y, 0)
	en[2].global_position = Vector3(0, DECK_Y, 30)
	var before := _rockets(arena).size()
	w.call("_maybe_split", en[0], Vector3(0, DECK_Y + 1.0, 0))
	var made: Array = _rockets(arena).slice(before)
	var aims: Array = made.map(func(r): return r.target)
	if made.size() != 2 or aims.has(en[0]) or not (aims.has(en[1]) and aims.has(en[2])):
		bad.append("an enemy hit with 2 others in range made %d rockets at %s (want one at each of the others)" % [made.size(), aims])
	for r in made:
		if r.on_hit.is_valid():
			var n0 := _rockets(arena).size()
			r.on_hit.call(en[1], (en[1] as Node3D).global_position)
			if _rockets(arena).size() != n0:
				bad.append("a split rocket split again")
			break
	# nobody else within 40 m
	en[1].global_position = Vector3(80, DECK_Y, 0)
	en[2].global_position = Vector3(0, DECK_Y, 90)
	before = _rockets(arena).size()
	w.call("_maybe_split", en[0], Vector3(0, DECK_Y + 1.0, 0))
	if _rockets(arena).size() != before:
		bad.append("a split with nobody else within 40 m")
	# a teammate hit never splits
	en[1].global_position = Vector3(10, DECK_Y, 0)
	before = _rockets(arena).size()
	w.call("_maybe_split", mate, Vector3(0, DECK_Y + 1.0, 0))
	if _rockets(arena).size() != before:
		bad.append("a teammate hit split")
	for r in _rockets(arena):
		r.queue_free()
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] swarm done")
	get_tree().quit(0)
