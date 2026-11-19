extends Node
# T456 probe (Etna STOMP; user 2026-11-17: "add as many mechs as you think are good"): the server hits
# every living enemy within Mech.STOMP_R, STOMP_DMG falling to half at the edge, and slows it to
# STOMP_SLOW_K for STOMP_SLOW_S; T478: while slowed its hits deal x STOMP_WEAKEN_K and the
# stomped player's HUD says STOMPED. On a deck:
#  S stomps: enemy N at 4 m takes ~the falloff damage and walks at half speed, back to full after the
#    slow; enemy M at 11 m takes less; enemy F at 14 m nothing; ally A at 4 m nothing; S nothing;
#  B is a Hard bot Etna: an enemy walks to 6 m -> it stomps on its own.

const Stomp := preload("res://resources/abilities/Stomp.tres")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] stomp FAIL: " + msg)
	_quit(1)

func _quit(code: int) -> void:  # B124: stop sounds before quitting
	for n in get_tree().root.find_children("*", "", true, false):
		if n is AudioStreamPlayer3D or n is AudioStreamPlayer:
			n.stop()
	get_tree().paused = true
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_tree().quit(code)

func _inert(m: Node) -> void:
	var src: Node = InputSource.new()
	add_child(src)
	m.call("set_input_source", src)

func _place(m: Node3D, at: Vector3) -> void:
	m.global_position = at
	m.set("velocity", Vector3.ZERO)

func _plain(m: Node) -> void:  # no shields soaking the hit, plenty of health
	var es: Node = m.get("_energy_shield")
	if es != null:
		es.set("_active", false)
	var ps: Node = m.get("_shield")
	if is_instance_valid(ps) and ps.visible:
		ps.call("_break")
	m.set("invincible", false)
	m.set("max_health", 1.0e5)
	m.set("health", 1.0e5)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 4
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
	box.size = Vector3(2400, 2, 400)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(600, DECK_Y - 1.0, 0)
	var t1: Array = arena.get("_team_mechs")[1]
	var t0: Array = arena.get("_team_mechs")[0]
	var s: Node3D = t1[0]
	var a: Node3D = t1[1]
	var b: Node3D = t1[3]
	var n: Node3D = t0[1]
	var mm: Node3D = t0[2]
	var f: Node3D = t0[3]
	for m in [s, a, t1[2], n, mm, f, t0[0]]:
		_inert(m)
	for m in [s, a, n, mm, f]:
		_plain(m)
	for m in [s, b]:
		m.call("configure_abilities", [Stomp])
	_place(t0[0], Vector3(0, DECK_Y + 0.5, 150))
	_place(t1[2], Vector3(300, DECK_Y + 0.5, 150))
	_place(s, Vector3(0, DECK_Y + 0.5, 0))
	_place(n, Vector3(4, DECK_Y + 0.5, 0))
	_place(mm, Vector3(0, DECK_Y + 0.5, 11))
	_place(f, Vector3(-14, DECK_Y + 0.5, 0))
	_place(a, Vector3(0, DECK_Y + 0.5, -4))
	_place(b, Vector3(1500, DECK_Y + 0.5, 0))
	await get_tree().physics_frame
	var hp := {}
	for m in [s, a, n, mm, f]:
		hp[m] = float(m.get("health"))
	var ws_n: float = n.get("walk_speed")
	var dn: float = n.global_position.distance_to(s.global_position)
	var dm: float = mm.global_position.distance_to(s.global_position)
	s.call("_activate_ability", Stomp)
	var wf := float(Engine.physics_ticks_per_second)
	# T480: the right leg rears up first -- nothing lands before the slam
	await get_tree().physics_frame
	if float(n.get("health")) < hp[n]:
		_fail("the stomp hit before the slam")
		return
	if float((s.get("legs") as Node).get("stomp_lift")) <= 0.0 and float(s.get("_stomp_t")) > 0.0:
		await get_tree().physics_frame
	for k in int((Mech.STOMP_RAISE_S + Mech.STOMP_SLAM_S) * wf) + 2:
		await get_tree().physics_frame
	var bad: Array = []
	var want_n := Mech.STOMP_DMG * (1.0 - Mech.STOMP_FALLOFF * dn / Mech.STOMP_R)
	var want_m := Mech.STOMP_DMG * (1.0 - Mech.STOMP_FALLOFF * dm / Mech.STOMP_R)
	var got_n: float = hp[n] - float(n.get("health"))
	var got_m: float = hp[mm] - float(mm.get("health"))
	if absf(got_n - want_n) > 2.0:
		bad.append("N at %.1f m took %.1f (want %.1f)" % [dn, got_n, want_n])
	if absf(got_m - want_m) > 2.0:
		bad.append("M at %.1f m took %.1f (want %.1f)" % [dm, got_m, want_m])
	for m in [f, a, s]:
		if float(m.get("health")) < hp[m]:
			bad.append("%s took %.1f (out of reach / own team)" % [("F" if m == f else ("A" if m == a else "S")), hp[m] - float(m.get("health"))])
	var slowed: float = n.get("walk_speed")
	if float(n.get("_shake_timer")) < Mech.STOMP_SHAKE_S * 0.5:  # T478: the stomped camera shakes
		bad.append("N's camera didn't shake (timer %.2f)" % float(n.get("_shake_timer")))
	Game.settings["camera_shake"] = false
	mm.set("_shake_timer", 0.0)
	mm.call("apply_camera_shake", 0.1, 1.0)
	if float(mm.get("_shake_timer")) > 0.0:
		bad.append("CAMERA SHAKE off and the camera still shook")
	Game.settings["camera_shake"] = true
	if absf(slowed - ws_n * Mech.STOMP_SLOW_K) > 0.01:
		bad.append("N walks at %.2f after the stomp (want %.2f)" % [slowed, ws_n * Mech.STOMP_SLOW_K])
	if absf(float(f.get("walk_speed")) - float(f.get("base_walk_speed"))) > 0.01 and float(f.get("terrain_speed")) == 1.0:
		bad.append("F (out of reach) slowed")
	# T478: stomped, N's hits deal x STOMP_WEAKEN_K; after the slow, full again
	var wn: Node = (n.call("get_weapons") as Array)[0]
	var dmg: float = float(wn.get("damage"))
	var s0: float = s.get("health")
	s.call("request_damage", dmg, wn)
	var cut: float = s0 - float(s.get("health"))
	if absf(cut - dmg * Mech.STOMP_WEAKEN_K) > 0.01:
		bad.append("stomped N's %.1f hit dealt %.2f (want x%.2f = %.2f)" % [dmg, cut, Mech.STOMP_WEAKEN_K, dmg * Mech.STOMP_WEAKEN_K])
	var me: Node = t0[0]
	me.set("slow_s", 5.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var lbl := arena.get("hud").find_child("Stomped", true, false) as Label  # under the minimap (T371's list)
	if lbl == null or not lbl.is_visible_in_tree() or not lbl.text.begins_with("STOMPED"):
		bad.append("a stomped player's HUD doesn't say STOMPED")
	for k in int((Mech.STOMP_SLOW_S + 0.2) * wf):
		await get_tree().physics_frame
	if absf(float(n.get("walk_speed")) - ws_n) > 0.01:
		bad.append("N still at %.2f after the slow (want %.2f)" % [n.get("walk_speed"), ws_n])
	var s1: float = s.get("health")
	s.call("request_damage", dmg, wn)
	if absf((s1 - float(s.get("health"))) - dmg) > 0.01:
		bad.append("N's hit after the slow dealt %.2f (want the full %.1f)" % [s1 - float(s.get("health")), dmg])
	if lbl != null and lbl.is_visible_in_tree():
		bad.append("the HUD still says STOMPED after the slow")
	# bot: an enemy walks to 6 m
	b.get("_input_source").set("difficulty", 3)
	_place(n, b.global_position + Vector3(6, 0, 0))
	var b_at := -1.0
	var n_hp: float = n.get("health")
	for k in int(3.0 * wf):
		await get_tree().physics_frame
		if float(n.get("slow_s")) > 0.0 and float(n.get("health")) < n_hp:
			b_at = k / wf
			break
	if b_at < 0.0:
		bad.append("the bot Etna never stomped an enemy 6 m off")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] stomp done (%.0f at %.1f m, %.0f at %.1f m, slowed %.2f -> back %.2f, bot at %.2f s)" % [got_n, dn, got_m, dm, slowed, ws_n, b_at])
	_quit(0)
