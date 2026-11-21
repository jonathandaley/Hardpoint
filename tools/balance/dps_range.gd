extends Node
# T539 (user 2026-11-20: "make a better weapon-balance test. Burst damage can be left alone for the first
# pass, but a sustained dps vs range vs accuracy one would be good."): ONE weapon's sustained DPS at five
# distances, measured in the engine -- spread, falloff, projectile travel, splash, lock time and reloads
# all count (tools/weapon_table.py assumes every hit lands). Run by tools/weapon_dps_range.py.
#   godot --headless --path . res://tools/balance/dps_range.tscn --fixed-bots=Pegasus -- weapon=<path> motion=still|strafe secs=60
# Prints shots too (magazine drops: trigger pulls) and how far each shooter drifted (sanity).
# Five Elite bots (team 1) are the shooters, held in place (no walking, no ability), each with only that
# weapon; each has its own target (team 0, no shields, 1e6 HP) DIST m away, pairs 900 m apart on a flat deck
# so nobody reaches another pair. "strafe": the targets walk left / right across the line of fire, turning
# every 1.5 s. Prints one line per distance:  [dps] {"weapon", "motion", "d", "dmg", "secs"}

const DIST := [10.0, 30.0, 60.0, 110.0, 180.0]  # inside 95% of the 120 / 200 m ranges: bots fire out to 0.95 x range (AIInputSource._fire_range)
const GAP := 900.0
const DECK_Y := 400.0
const SETTLE_S := 5.0
const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const InputSource := preload("res://scripts/InputSource.gd")

class Strafe extends "res://scripts/InputSource.gd":
	var t := 0.0
	var on := false
	func _physics_process(delta: float) -> void:
		t += delta
	func get_move_direction() -> Vector2:
		return Vector2(1.0 if int(t / 1.5) % 2 == 0 else -1.0, 0.0) if on else Vector2.ZERO

var _arg := {"weapon": "", "motion": "still", "secs": "60"}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_arg[kv[0]] = kv[1]
	var wpath: String = _arg["weapon"]
	var secs := float(_arg["secs"])
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 5
	Game.loadout["mode"] = "deathmatch"
	Game.settings["bot_difficulty"] = 4
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
	box.size = Vector3(GAP * DIST.size() + 400.0, 2.0, 600.0)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(GAP * (DIST.size() - 1) * 0.5, DECK_Y - 1.0, 0.0)
	var t0: Array = []
	var t1: Array = []
	for m in get_tree().get_nodes_in_group("mechs"):
		(t0 if int(m.get("team")) == 0 else t1).append(m)
	if t0.size() < DIST.size() or t1.size() < DIST.size():
		push_error("[dps] need %d mechs a team, have %d / %d" % [DIST.size(), t0.size(), t1.size()])
		get_tree().quit(1)
		return
	var w: Node = (load(wpath) as PackedScene).instantiate()
	var slot := SlotDef.new()
	slot.slot_size = 1 if String(wpath).ends_with("Heavy.tscn") else 0
	slot.position = Vector3(0.6, 1.8, -0.3)
	slot.weapon_scene = load(wpath)
	var wrange := float(w.get("range"))
	w.free()
	var pairs: Array = []
	for i in DIST.size():
		var sh: Node3D = t1[i]
		var tg: Node3D = t0[i]
		sh.call("configure_weapons", [slot])
		sh.set("base_walk_speed", 0.0)  # held in place: only aiming and firing
		var src := Strafe.new()
		src.on = _arg["motion"] == "strafe"
		add_child(src)
		tg.call("set_input_source", src)
		tg.call("configure_weapons", [])
		_plain(tg)
		var base := Vector3(GAP * i, DECK_Y + 0.5, 0.0)
		_place(sh, base)
		_place(tg, base + Vector3(0, 0, -DIST[i]))
		(tg.get("torso") as Node3D).global_rotation.y = 0.0  # facing along -z: its strafe (x) crosses the line of fire
		pairs.append([sh, tg, DIST[i]])
	for m in t0.slice(DIST.size()) + t1.slice(DIST.size()):
		_place(m as Node3D, Vector3(-3000, DECK_Y + 0.5, 0))
	var wf := float(Engine.physics_ticks_per_second)
	for k in int(SETTLE_S * wf):
		await get_tree().physics_frame
	var hp0: Array = []
	for p in pairs:
		hp0.append(float(p[1].get("health")))
	var fired: Array = []
	var last_ammo: Array = []
	for p in pairs:
		fired.append(0)
		last_ammo.append(int((p[0].call("get_weapons")[0]).get("ammo")))
	for k in int(secs * wf):
		await get_tree().physics_frame
		for i in pairs.size():  # trigger pulls: every drop in the magazine
			var a := int((pairs[i][0].call("get_weapons")[0]).get("ammo"))
			if a < last_ammo[i]:
				fired[i] += last_ammo[i] - a
			last_ammo[i] = a
	for i in pairs.size():
		var p: Array = pairs[i]
		var dmg: float = hp0[i] - float(p[1].get("health"))
		var out: bool = p[2] > wrange * 0.95 - 0.5  # bots fire out to 0.95 x range (AIInputSource._fire_range)
		if out:
			dmg = 0.0  # out of its range: nothing that counts (a stray splash)
		print("[dps] " + JSON.stringify({"weapon": wpath.get_file().get_basename(), "motion": _arg["motion"],
			"d": p[2], "dmg": snappedf(dmg, 0.1), "secs": secs, "shots": fired[i], "out": out,
			"jumps": int(p[0].get("_jump_count")) if p[0].get("_jump_count") != null else -1,
			"moved": snappedf((p[0] as Node3D).global_position.distance_to(Vector3(GAP * i, DECK_Y + 0.5, 0.0)), 0.1)}))
	get_tree().quit(0)

func _plain(m: Node) -> void:
	var es: Node = m.get("_energy_shield")
	if es != null:
		es.set("_active", false)
	var ps: Node = m.get("_shield")
	if is_instance_valid(ps) and ps.visible:
		ps.call("_break")
	m.set("invincible", false)
	m.set("max_health", 1.0e6)
	m.set("health", 1.0e6)

func _place(m: Node3D, at: Vector3) -> void:
	m.global_position = at
	m.set("velocity", Vector3.ZERO)
