extends Node
# T339 probe (user 2026-11-08: the T243 balance proposals "should wait until we're sure bots use
# lock-on correctly"): bots with lock weapons (rocket, aerial strike, arc light / heavy) duel
# standing, shieldless targets on a deck high above the map, five duels side by side (300 m
# apart: outside every lock and weapon range). Per duel: seconds to the lock, to the first damage,
# and the damage dealt. Found and fixed with it:
#  - homing missiles expired before reaching the far end of their lock range (lifetime was
#    range / speed, but they climb first): rockets reached ~150 of 180 m, aerial strikes ~120 of 200;
#  - Easy..Medium bots held fire on a lock outside their old fire range (half the weapon's range).
#  - B125: an aim point (Mech.center_mass) outside the target's hit capsule -- the arc's ray to it
#    met nothing; on a failure the bot's end state says what its own ray meets.
# Default: round 1 at 50 m (every lock weapon used), round 2 near full range. User arg `measure`
# prints the whole weapon x difficulty x distance table instead.

const CASE_S := 12.0
const LONG_CASE_S := 22.0
const WEAPONS := ["RocketLauncherLight", "AerialStrikeHeavy", "ArcWeaponLight", "ArcWeaponHeavy"]
const DIFF_NAMES := ["Easy", "Normal", "Medium", "Hard", "Elite"]
const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0
const EASY := 0
const NORMAL := 1
const MEDIUM := 2
const HARD := 3
const ELITE := 4

func _fail(msg: String) -> void:
	push_error("[probe] bot_lock_weapons FAIL: " + msg)
	get_tree().quit(1)

func _mech_name(m: Node) -> String:
	return String(load(m.get_meta("spawn")[0]).display_name) if m.has_meta("spawn") else String(m.name)

func _range(wname: String) -> float:
	var w: Node = (load("res://scenes/weapons/%s.tscn" % wname) as PackedScene).instantiate()
	var r: float = w.get("range")
	w.free()
	return r

func _ready() -> void:
	var measure := "measure" in OS.get_cmdline_user_args()
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 5
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
	var deck := StaticBody3D.new()  # a flat, open deck above the map: clear sight, no cover
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1600, 2, 400)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(600, DECK_Y - 1.0, 0)
	var shooters: Array = arena.get("_team_mechs")[1]
	var targets: Array = arena.get("_team_mechs")[0]
	for t in targets:  # the targets stand still, never shoot back, and carry no shields
		# an inert input: a disabled AI node still hands the mech its last move (it kept walking)
		var src: Node = InputSource.new()
		add_child(src)
		t.call("set_input_source", src)
		var es: Node = t.get("_energy_shield")
		if es != null:
			es.set("_active", false)
		var ps: Node = t.get("_shield")
		if is_instance_valid(ps) and ps.visible:
			ps.call("_break")
	var rounds: Array = []  # each round: up to 5 duels [weapon, difficulty, distance]
	if measure:
		for wname in WEAPONS:
			for d in [30.0, 60.0, snappedf(_range(wname) * 0.9, 1.0)]:
				rounds.append(range(5).map(func(i): return [wname, i, d]))
	else:
		rounds.append([["RocketLauncherLight", ELITE, 50.0], ["AerialStrikeHeavy", ELITE, 50.0],
			["ArcWeaponLight", ELITE, 50.0], ["ArcWeaponHeavy", HARD, 50.0], ["ArcWeaponLight", MEDIUM, 50.0]])
		rounds.append([["RocketLauncherLight", ELITE, 0.9 * _range("RocketLauncherLight")],
			["AerialStrikeHeavy", ELITE, 0.9 * _range("AerialStrikeHeavy")],
			["AerialStrikeHeavy", HARD, 0.9 * _range("AerialStrikeHeavy")],
			["RocketLauncherLight", MEDIUM, 0.8 * _range("RocketLauncherLight")],
			["ArcWeaponHeavy", MEDIUM, 0.8 * _range("ArcWeaponHeavy")]])
	var rows: Array = []
	var bad: Array = []
	for cases in rounds:
		var res := await _duels(shooters, targets, cases)
		for i in res.size():
			var c: Array = cases[i]
			var r: Dictionary = res[i]
			var row := "%s %s %dm (%s at %s): lock %s, first dmg %s, dmg %.0f" % [c[0], DIFF_NAMES[c[1]], int(c[2]),
				_mech_name(shooters[i]), _mech_name(targets[i]),
				("%.1fs" % r["lock"]) if r["lock"] >= 0.0 else "never", ("%.1fs" % r["hit"]) if r["hit"] >= 0.0 else "never", r["dmg"]]
			rows.append(row)
			if not measure and (r["lock"] < 0.0 or r["lock"] > 5.0 or r["dmg"] <= 0.0):
				bad.append(row + " " + str(r["end"]))
	if not bad.is_empty():
		print("\n".join(rows))
		_fail("want a lock within 5 s and hits: " + "; ".join(bad))
		return
	print("[probe] bot_lock_weapons done\n" + "\n".join(rows))
	get_tree().quit(0)

## One duel per case [weapon, difficulty, distance], all at once; returns per duel {lock, hit, dmg}.
func _duels(shooters: Array, targets: Array, cases: Array) -> Array:
	# shots still flying from the last round would land with a freed weapon (the game never
	# re-arms mid-match; only this probe does)
	for p in get_tree().root.find_children("*", "Node3D", true, false):
		if "source_weapon" in p:
			p.queue_free()
	await get_tree().physics_frame
	var out: Array = []
	var long := false
	for i in cases.size():
		var c: Array = cases[i]
		var e: Node3D = shooters[i]
		var t: Node3D = targets[i]
		var scene: PackedScene = load("res://scenes/weapons/%s.tscn" % c[0])
		var slot = SlotDef.new()
		slot.slot_size = 1 if String(c[0]).ends_with("Heavy") else 0
		slot.position = Vector3(0.7, 1.5, 0.3)
		slot.weapon_scene = scene
		e.call("configure_weapons", [slot])
		e.set("invincible", true)
		t.set("invincible", false)
		t.set("max_health", 1.0e6)
		t.set("health", 1.0e6)
		var base := Vector3(i * 300.0, DECK_Y + 0.5, 0.0)
		e.global_position = base
		t.global_position = base + Vector3(0, 0, float(c[2]))
		e.set("velocity", Vector3.ZERO)
		t.set("velocity", Vector3.ZERO)
		var src: Node = e.get("_input_source")
		src.set("difficulty", int(c[1]))
		src.set("_target", null)
		e.set("locked_target", null)
		e.set("_lock_candidate", null)
		e.set("_lock_timer", 0.0)
		long = long or float(c[2]) > 60.0
		out.append({"lock": -1.0, "hit": -1.0, "dmg": 0.0, "dmg0": float(t.get("damage_taken_total"))})
	for f in int((LONG_CASE_S if long else CASE_S) * 60.0):  # long shots fly for seconds
		await get_tree().physics_frame
		for i in cases.size():
			var e: Node3D = shooters[i]
			var t: Node3D = targets[i]
			var r: Dictionary = out[i]
			if r["lock"] < 0.0 and e.get("locked_target") == t:
				r["lock"] = f / 60.0
			var dmg: float = float(t.get("damage_taken_total")) - float(r["dmg0"])
			if r["hit"] < 0.0 and dmg > 0.0:
				r["hit"] = f / 60.0
			r["dmg"] = dmg
	for i in cases.size():  # the bot's state at the end, for a failing duel's message
		var e: Node3D = shooters[i]
		var src: Node = e.get("_input_source")
		var w: Node = e.get_weapons()[0] if not e.get_weapons().is_empty() else null
		var blocker := ""
		if w != null:  # what the arc's own ray (same exclusions) meets on the way to the target
			var ex: Array = e.call("get_exclude_rids")
			for m in get_tree().get_nodes_in_group("mechs"):
				if m != targets[i] and m != e and m.has_method("get_exclude_rids"):
					ex.append_array(m.get_exclude_rids())
			var q := PhysicsRayQueryParameters3D.create((w as Node3D).global_position, targets[i].call("center_mass"))
			q.exclude = ex
			var hit := e.get_world_3d().direct_space_state.intersect_ray(q)
			blocker = str(e.get_path_to(hit.collider)) + " @" + str(hit.position) if hit else "nothing"
		out[i]["end"] = {"ray_hits": blocker, "gun": str((w as Node3D).global_position) if w != null else "", "on_target": src.get("_target") == targets[i], "clear": src.get("_has_clear_shot"),
			"firing": src.get("_firing"), "locked": e.get("locked_target") == targets[i],
			"ammo": w.get("ammo") if w != null else null,
			"gap": snappedf((e.global_position - targets[i].global_position).length(), 0.1), "y": snappedf(e.global_position.y, 0.1),
			"t_cm": str(targets[i].get("_cm_local"))}
	return out
