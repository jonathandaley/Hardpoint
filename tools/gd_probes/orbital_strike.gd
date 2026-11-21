extends Node
# T522 probe (user 2026-11-19: "Orbital Strike: replace aerial. Just a transponder. Makes an antenna bloop
# graphic, locks on. Big circle target graphic centered on locked target's position at time of fire,
# doesn't move. 10 seconds later, big boom from above."): fired at a locked target, the strike marks the
# ground under it (a pending entry + a ring there), nothing lands before 10 s, then the target at the
# centre takes ~the full hit and one 15 m off (outside the 10 m ring) nothing; a Medium+ enemy bot in
# the ring wants out of it. ORBITAL HV replaced AERIAL HV in the catalog.
const DECK_Y := 400.0
const Orbital := preload("res://scripts/OrbitalStrike.gd")

func _fail(msg: String) -> void:
	push_error("[probe] orbital_strike FAIL: " + msg)
	get_tree().quit(1)

func _plain(m: Node) -> void:
	var es: Node = m.get("_energy_shield")
	if es != null:
		es.set("_active", false)
	var ps: Node = m.get("_shield")
	if is_instance_valid(ps) and ps.visible:
		ps.call("_break")
	m.set("invincible", false)
	m.set("max_health", 5000.0)
	m.set("health", 5000.0)

func _ready() -> void:
	var lobby: Script = load("res://scripts/Lobby.gd")
	var names: Array = (lobby.get_script_constant_map()["WEAPON_CATALOG"] as Array).map(func(w): return w["name"])
	if not names.has("ORBITAL HV") or names.has("AERIAL HV"):
		_fail("the catalog has %s (want ORBITAL HV in place of AERIAL HV)" % str(names))
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
	var deck := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 2, 300)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(0, DECK_Y - 1.0, 0)
	var shooter: Node3D = arena.get("_team_mechs")[1][0]
	var t0: Array = arena.get("_team_mechs")[0]
	var hit: Node3D = t0[1]
	var off: Node3D = t0[2]
	var InputSource := load("res://scripts/InputSource.gd")
	for m in [shooter, hit, off]:  # the shooter too: its own AI would fire a second strike once locked
		var src: Node = InputSource.new()
		add_child(src)
		m.call("set_input_source", src)
		if m != shooter:
			_plain(m)
	shooter.global_position = Vector3(0, DECK_Y + 0.5, 60)
	hit.global_position = Vector3(0, DECK_Y + 0.5, 0)
	off.global_position = Vector3(15, DECK_Y + 0.5, 0)
	var slot = load("res://scripts/WeaponSlotDef.gd").new()
	slot.slot_size = 1
	slot.position = Vector3(0.7, 1.5, 0.3)
	slot.weapon_scene = load("res://scenes/weapons/OrbitalStrikeHeavy.tscn")
	shooter.call("configure_weapons", [slot])
	shooter.set("invincible", true)
	for i in 10:
		await get_tree().physics_frame
	var w: Node = shooter.get_weapons()[0]
	shooter.set("locked_target", hit)
	var h0: float = hit.get("health")
	w.call("_do_fire")
	var bad: Array = []
	if Orbital.pending.size() != 1:
		bad.append("%d strikes pending after one shot (want 1)" % Orbital.pending.size())
	else:
		var at: Vector3 = Orbital.pending[0][0]
		if Vector2(at.x, at.z).distance_to(Vector2(0, 0)) > 0.5 or absf(at.y - DECK_Y) > 0.6:
			bad.append("marked %s, want the ground under the target (0, %.0f, 0)" % [at, DECK_Y])
		if not is_instance_valid(Orbital.pending[0][4]):
			bad.append("no ring shown")
	hit.global_position = Vector3(0, DECK_Y + 0.5, 0)  # it stays put (a walker would leave)
	# a Medium+ enemy bot in the ring wants out
	var enemy_bot: Node3D = arena.get("_team_mechs")[0][0]
	for a in get_tree().get_nodes_in_group("ai_input_sources"):
		if a.get_parent() != null and a.get_parent().get("pawn") == hit:
			pass
	var ais: Array = get_tree().get_nodes_in_group("ai_input_sources").filter(func(a): return a.get("_own_team") == 0)
	if not ais.is_empty():
		var ai: Node = ais[0]
		var pawn: Node3D = ai.get_parent().get("pawn")
		var was: Vector3 = pawn.global_position
		pawn.global_position = Vector3(3, DECK_Y + 0.5, 0)
		if (ai.call("_strike_escape", pawn) as Vector2) == Vector2.ZERO:
			bad.append("a bot 3 m from the mark doesn't want out")
		pawn.global_position = Vector3(30, DECK_Y + 0.5, 0)
		if (ai.call("_strike_escape", pawn) as Vector2) != Vector2.ZERO:
			bad.append("a bot 30 m from the mark runs from it")
		pawn.global_position = was
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 9300:
		await get_tree().process_frame
	if float(hit.get("health")) < h0:
		bad.append("damage before 10 s (%.0f at %.1f s)" % [h0 - float(hit.get("health")), (Time.get_ticks_msec() - t) / 1000.0])
	while Time.get_ticks_msec() - t < 11500:
		await get_tree().process_frame
	var took: float = h0 - float(hit.get("health"))
	if absf(took - float(w.get("damage"))) > 40.0:
		bad.append("the target at the centre took %.0f (want ~%.0f)" % [took, float(w.get("damage"))])
	if float(off.get("health")) < 5000.0:
		bad.append("a mech 15 m off (outside the 10 m ring) took %.0f" % (5000.0 - float(off.get("health"))))
	if not Orbital.pending.is_empty():
		bad.append("the strike is still pending after it landed")
	# T541: a PLAYER's orbital -- the trigger alone fires nothing; a pick far past the range is pulled in
	# to 200 m and marked on the ground there; the shot is spent; the minimap maps clicks back to the ground
	shooter.call("configure_weapons", [slot])
	shooter.set("owner_peer_id", 1)
	for i in 3:
		await get_tree().physics_frame
	var pw: Node = shooter.get_weapons()[0]
	pw.call("fire")
	if not Orbital.pending.is_empty():
		bad.append("a player's orbital fired from the trigger alone")
	pw.call("request_strike", Vector3(0, 0, -500))
	if Orbital.pending.size() != 1:
		bad.append("%d strikes pending after a player's pick (want 1)" % Orbital.pending.size())
	else:
		var pat: Vector3 = Orbital.pending[0][0]
		var dd := Vector2(pat.x - shooter.global_position.x, pat.z - shooter.global_position.z).length()
		if absf(dd - float(pw.get("range"))) > 1.0 or absf(pat.y - DECK_Y) > 0.6:
			bad.append("a pick 560 m away marked %s (%.0f m off; want %.0f m, on the deck)" % [pat, dd, float(pw.get("range"))])
	if int(pw.get("ammo")) != 0:
		bad.append("the player's strike didn't spend its shot (ammo %d)" % int(pw.get("ammo")))
	var mm: Control = load("res://scripts/Minimap.gd").new()
	mm.size = Vector2(280, 280)
	mm.set("center", Vector2(10, -20))
	mm.set("half", 150.0)
	var wp := Vector3(60, 0, -95)
	var back: Vector3 = mm.call("from_map", mm.call("to_map", wp))
	if back.distance_to(wp) > 0.01:
		bad.append("minimap from_map(to_map(%s)) = %s" % [wp, back])
	mm.free()
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] orbital_strike done (centre took %.0f, 15 m off 0; player pick clamped to range)" % took)
	get_tree().quit(0)
