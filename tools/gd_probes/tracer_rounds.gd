extends Node
# T551 probe (user 2026-11-21: "Add tracer round pilot skill, sibling of scope, you pick a hotkey to toggle
# tracers that anyone can see. Applies to every projectile weapon except shotgun."): a mech whose pilot owns
# Tracer Rounds and has them on fires tracer shots -- rifle, sniper, MG, missile salvo, mortar shell -- and
# the FX pool draws a streak for each; off, or without the skill, or from a shotgun: none. The skill is one
# level (an unlock) and its "i" says so (probe skill_info).

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const InputSource := preload("res://scripts/InputSource.gd")

func _fail(msg: String) -> void:
	push_error("[probe] tracer_rounds FAIL: " + msg)
	get_tree().quit(1)

func _shots() -> Array:
	return get_tree().current_scene.find_children("*", "Node3D", true, false).filter(func(n): return n is Projectile)

func _fire(m: Node3D, scene: String, skills: Dictionary, on: bool) -> Array:
	var slot := SlotDef.new()
	slot.slot_size = 1 if scene.ends_with("Heavy") else 0
	slot.position = Vector3(0.7, 1.5, 0.3)
	slot.weapon_scene = load("res://scenes/weapons/%s.tscn" % scene)
	m.call("configure_weapons", [slot])
	m.set("pilot_skills", skills)
	m.set("tracers_on", on)
	await get_tree().physics_frame
	var before := _shots()
	var w: Node = m.get_weapons()[0]
	if w is Mortar:
		w.call("launch_at", m.global_position - m.global_transform.basis.z * 30.0)
	else:
		w.call("_do_fire")
	await get_tree().process_frame
	return _shots().filter(func(p): return not before.has(p))

func _ready() -> void:
	if Game.skill_max("tracer_rounds") != 1 or Game.SKILL_TREE["tracer_rounds"]["parents"] != ["spread_reduction"]:
		_fail("tracer_rounds: max %d, parents %s (want 1, spread_reduction)" % [Game.skill_max("tracer_rounds"),
			Game.SKILL_TREE["tracer_rounds"]["parents"]])
		return
	if not InputMap.has_action("toggle_tracers"):
		_fail("no toggle_tracers input action")
		return
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 3
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var m: Node3D = arena.get("_team_mechs")[1][0]
	var src: Node = InputSource.new()
	add_child(src)
	m.call("set_input_source", src)
	var fx: Node = VFX._fx()
	var own := {"spread_reduction": 1, "tracer_rounds": 1}
	var bad: Array = []
	# [weapon, skills, on, want tracer]
	for c in [["RifleLight", own, true, true], ["SniperHeavy", own, true, true], ["MachineGunLight", own, true, true],
			["MissileLauncherLight", own, true, true], ["MortarHeavy", own, true, true],
			["RifleLight", own, false, false], ["RifleLight", {"spread_reduction": 1}, true, false],
			["ShotgunLight", own, true, false]]:
		var s0: int = fx.call("streaks") if fx != null else 0
		var shots: Array = await _fire(m, c[0], c[1], c[2])
		if shots.is_empty():
			bad.append("%s fired no projectile" % c[0])
			continue
		var traced: bool = shots.any(func(p): return p.get("tracer"))
		if traced != c[3]:
			bad.append("%s (skills %s, on %s): tracer %s (want %s)" % [c[0], c[1].keys(), c[2], traced, c[3]])
		if fx != null and c[3] and int(fx.call("streaks")) <= s0:
			bad.append("%s: tracer shots but no streak in the FX pool" % c[0])
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] tracer_rounds done (rifle / sniper / MG / missiles / mortar traced; off, unowned, shotgun not)")
	get_tree().quit(0)
