extends Node
# T359 probe (user 2026-11-08: "RWF bots shouldn't always wait until they are full, rather, be smart
# about it (press forward if enemy has low health, hide if enemy has a reload-while-empty weapon,
# burst for a few shots)"): three Hard bots with a light laser (reload-while-firing) on a deck high
# above the map, side by side, each facing a standing target 40 m off:
#  A (healthy target, rifle): fires down to ~15%, then holds fire until 40% is back;
#  B (target at 15% health): presses on below 15%;
#  C (healthy target with a sniper -- reload-when-empty): gives ground while it refills.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] bot_rwf FAIL: " + msg)
	get_tree().quit(1)

func _arm(m: Node, wname: String) -> void:
	var slot = SlotDef.new()
	slot.slot_size = 1 if wname.ends_with("Heavy") else 0
	slot.position = Vector3(0.7, 1.5, 0.3)
	slot.weapon_scene = load("res://scenes/weapons/%s.tscn" % wname)
	m.call("configure_weapons", [slot])

func _ready() -> void:
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
	arena.set("powerup_every_s", 1000.0)
	for i in 10:
		await get_tree().physics_frame
	var deck := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1200, 2, 600)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(300, DECK_Y - 1.0, 0)
	var shooters: Array = arena.get("_team_mechs")[1]
	var targets: Array = arena.get("_team_mechs")[0]
	var target_guns := ["RifleLight", "RifleLight", "SniperLight"]
	for i in 3:
		var e: Node3D = shooters[i]
		var t: Node3D = targets[i]
		var src: Node = InputSource.new()
		add_child(src)
		t.call("set_input_source", src)
		_arm(t, target_guns[i])
		var es: Node = t.get("_energy_shield")
		if es != null:
			es.set("_active", false)
		t.set("max_health", 1000.0)
		t.set("health", 150.0 if i == 1 else 1000.0)
		t.set("invincible", true)  # its health share stays put
		_arm(e, "LaserCannonLight")
		e.set("invincible", true)
		e.get("_input_source").set("difficulty", 3)
		var base := Vector3(i * 300.0, DECK_Y + 0.5, 0.0)
		e.global_position = base
		t.global_position = base + Vector3(0, 0, 40.0)
	await get_tree().physics_frame
	var series: Array = [[], [], []]  # per tick: [ammo fraction, distance]
	for k in 60 * 14:
		await get_tree().physics_frame
		for i in 3:
			var w: Node = shooters[i].get_weapons()[0]
			series[i].append([float(w.get("ammo")) / float(w.get("max_ammo")), (shooters[i] as Node3D).global_position.distance_to(targets[i].global_position)])
	var bad: Array = []
	# A: after the first drop to <= 15%, the next shot comes only once 40% is back
	var a: Array = series[0]
	var low_at := -1
	for k in a.size():
		if a[k][0] <= 0.16:
			low_at = k
			break
	if low_at < 0:
		bad.append("A never ran its laser down (min %.2f)" % a.reduce(func(m, x): return minf(m, x[0]), 1.0))
	else:
		for k in range(low_at + 1, a.size()):
			if a[k][0] < a[k - 1][0] - 0.001:  # a shot
				if a[k - 1][0] < 0.39:
					bad.append("A fired again at %.0f%% ammo (want a hold to 40%%)" % (a[k - 1][0] * 100.0))
				break
	# B: presses on below 15% against a nearly dead target
	var b_min: float = series[1].reduce(func(m, x): return minf(m, x[0]), 1.0)
	if b_min > 0.08:
		bad.append("B stopped at %.0f%% ammo against a target at 15%% health (want it emptied)" % (b_min * 100.0))
	# C: gives ground while refilling against a reload-when-empty gun
	var c: Array = series[2]
	var c_low := -1
	for k in c.size():
		if c[k][0] <= 0.16:
			c_low = k
			break
	var c_far := 0.0  # the farthest it got during the hold (a strafe flip or a stuck-escape can stall it for a moment)
	if c_low >= 0:
		for k in range(c_low, mini(c_low + 240, c.size())):
			c_far = maxf(c_far, c[k][1])
	if c_low < 0 or c_low + 180 >= c.size():
		bad.append("C never reached its hold (min ammo %.2f)" % c.reduce(func(m, x): return minf(m, x[0]), 1.0))
	elif c_far < c[c_low][1] + 1.0:
		bad.append("C stayed within %.1f -> %.1f m of a sniper while refilling (want it backing off)" % [c[c_low][1], c_far])
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] bot_rwf done (A low at %.1f s, B min %.0f%%, C %.1f -> %.1f m)" % [low_at / 60.0, b_min * 100.0, c[c_low][1], c_far])
	get_tree().quit(0)
