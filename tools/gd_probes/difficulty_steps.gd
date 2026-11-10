extends Node
# T357 probe (user on T282: "Probably just shift Normal and medium up a little so that the steps are
# fairly even"): what each difficulty does to a player -- an Easy, Normal, Medium and Hard bot, the
# same rifle, each shooting a target that strafes side to side 40 m off (a player dodging), on a
# deck high above the map, side by side. The damage each lands should climb in fairly even steps.
# User arg `measure` prints the numbers only.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const Lobby := preload("res://scripts/Lobby.gd")
const DECK_Y := 400.0
const RUN_S := 30.0
const DUELS := [0, 1, 1, 2, 2, 3]  # difficulty per duel: Normal and Medium twice (Medium swings 130-275 a run)
const NAMES := ["Easy", "Normal", "Medium", "Hard"]

class Strafer extends "res://scripts/InputSource.gd":
	var t := 0.0
	func get_move_direction() -> Vector2:
		t += 1.0 / 60.0
		return Vector2(1.0 if fmod(t, 3.0) < 1.5 else -1.0, 0.0)  # side to side, 1.5 s each way

func _fail(msg: String) -> void:
	push_error("[probe] difficulty_steps FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var measure := "measure" in OS.get_cmdline_user_args()
	Game.loadout["team_size"] = 6
	Game.loadout["mode"] = "deathmatch"
	Game.setup_sp_match()
	# B135: T365 squads are random -- a slow or big strafer swung Normal past Medium. Pin the mix
	# T357 was measured on (pre-T365: pool[bot_id % pool.size()], the Normal pool).
	var pool := ["Slip", "Seeker", "Hornet", "Hippogriff", "Pegasus", "Kestrel", "Everest", "Vesuvius"]
	var rng := RandomNumberGenerator.new()
	for e in Game.mp_active_match["roster"]:
		if int(e["peer_id"]) == 0:
			var mp := "res://resources/mechs/%s.tres" % pool[int(e["bot_id"]) % pool.size()]
			e["squad"] = range(5).map(func(_i): return {"mech": mp, "weapons": Lobby.bot_weapon_paths(load(mp), rng)})
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
	box.size = Vector3(2000, 2, 400)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(750, DECK_Y - 1.0, 0)
	var shooters: Array = arena.get("_team_mechs")[1]
	var targets: Array = arena.get("_team_mechs")[0]
	var dmg0: Array = []
	for i in DUELS.size():
		var e: Node3D = shooters[i]
		var t: Node3D = targets[i]
		var slot = SlotDef.new()
		slot.slot_size = 0
		slot.position = Vector3(0.7, 1.5, 0.3)
		slot.weapon_scene = load("res://scenes/weapons/RifleLight.tscn")
		e.call("configure_weapons", [slot])
		e.get_weapons()[0].set("max_ammo", -1)  # endless: aim and trigger only (no T359 refill holds)
		e.set("invincible", true)
		e.get("_input_source").set("difficulty", DUELS[i])
		var st := Strafer.new()
		add_child(st)
		t.call("set_input_source", st)
		var es: Node = t.get("_energy_shield")
		if es != null:
			es.set("_active", false)
		var ps: Node = t.get("_shield")
		if is_instance_valid(ps) and ps.visible:
			ps.call("_break")
		t.set("invincible", false)
		t.set("max_health", 1.0e6)
		t.set("health", 1.0e6)
		var base := Vector3(i * 300.0, DECK_Y + 0.5, 0.0)
		e.global_position = base
		t.global_position = base + Vector3(0, 0, 40.0)
		dmg0.append(float(t.get("damage_taken_total")))
	for k in int(RUN_S * 60.0):
		await get_tree().physics_frame
	var dmg: Array = [0.0, 0.0, 0.0, 0.0]  # mean per difficulty
	for i in DUELS.size():
		dmg[DUELS[i]] += (float(targets[i].get("damage_taken_total")) - float(dmg0[i])) / float(DUELS.count(DUELS[i]))
	var line := ", ".join(range(4).map(func(i): return "%s %.0f" % [NAMES[i], dmg[i]]))
	if measure:
		print("[probe] difficulty_steps done (measure: %s)" % line)
		get_tree().quit(0)
		return
	# Easy -> Normal -> Medium climb in clear, similar steps; Normal can hit a dodging player (the old
	# Normal landed 35-55 here, Medium ~200); Hard's edge over Medium is play (moves, jukes, picks
	# its shots), not raw damage on a strafer -- it must not fall far behind.
	var bad: Array = []
	var s1: float = dmg[1] - dmg[0]
	var s2: float = dmg[2] - dmg[1]
	if s1 < 40.0 or s2 < 40.0:
		bad.append("a step under 40 damage (%s)" % line)
	elif dmg[1] < 80.0:
		bad.append("Normal barely hits a dodging target (%s)" % line)
	elif maxf(s1, s2) > 3.0 * minf(s1, s2):
		bad.append("uneven steps %.0f / %.0f (%s)" % [s1, s2, line])
	if dmg[3] < 0.8 * dmg[2]:
		bad.append("Hard well under Medium (%s)" % line)
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] difficulty_steps done (%s)" % line)
	get_tree().quit(0)
