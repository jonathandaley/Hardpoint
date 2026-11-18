extends Node
# T473 probe (Taurus CHARGE; user 2026-11-18, their original design with SPACE a toggle: "High top
# speed, cap is good. Stop on hit. Original feel."): a press sets it off along its facing, speeding
# up linearly from walking pace to CHARGE_TOP; a second press pulls up -- the speed bleeds off at
# CHARGE_DECEL; a press out of a pull-up sets off from what it still carries along the new heading;
# ramming deals damage from the closing speed with a high floor, once, then stops it dead; walls
# stop it with no damage; bots charge at a target straight ahead. On a deck high above the map, side
# by side (300 m apart), all at once:
#  R charges a standing enemy 20 m ahead: one ram of RAM_FLOOR..top-speed damage, then it stands
#    CHARGE_HIT_S and the charge is over;
#  W charges a wall 10 m ahead: stops at the wall, nobody hurt;
#  F charges into the open for 4 s: the speed climbs at CHARGE_ACCEL, caps at CHARGE_TOP; pulled up,
#    it's at rest within CHARGE_TOP / CHARGE_DECEL; the distance matches the curve;
#  P charges 2 s, pulls up, turns 30 deg and presses again 0.1 s later: it sets off well above
#    walking pace (the boost it kept);
#  B is a Hard bot with the charge and a target 15 m ahead: it charges on its own, without flicking
#    the toggle on and off.

const Charge := preload("res://resources/abilities/Charge.tres")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] charge FAIL: " + msg)
	_quit(1)

## B124: quitting with a sound still playing leaks its stream at exit -- stop them, let the
## audio thread catch up, then quit.
func _quit(code: int) -> void:
	for n in get_tree().root.find_children("*", "", true, false):
		if n is AudioStreamPlayer3D or n is AudioStreamPlayer:
			n.stop()
	get_tree().paused = true
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_tree().quit(code)

func _inert(m: Node) -> void:  # stands still, no AI
	var src: Node = InputSource.new()
	add_child(src)  # freed with the probe (a loose node leaks at exit)
	m.call("set_input_source", src)

func _plain(m: Node) -> void:  # a target: no shields, can't die in the window
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

func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

func _ready() -> void:
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
	var deck := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1800, 2, 400)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(600, DECK_Y - 1.0, 0)
	var t1: Array = arena.get("_team_mechs")[1]
	var t0: Array = arena.get("_team_mechs")[0]
	var r: Node3D = t1[0]
	var w: Node3D = t1[1]
	var f: Node3D = t1[2]
	var p: Node3D = t1[3]
	var b: Node3D = t1[4]
	var tr: Node3D = t0[1]  # R's target
	var tb: Node3D = t0[2]  # B's target
	for m in t0 + [r, w, f, p]:
		_inert(m)
	for m in t0:
		_plain(m)
	for m in [r, w, f, p, b]:
		m.call("configure_abilities", [Charge])
		m.set("invincible", true)
	_place(t0[0], Vector3(0, DECK_Y + 0.5, 150))  # the player's mech, out of everyone's way
	_place(t0[3], Vector3(0, DECK_Y + 0.5, -150))
	_place(t0[4], Vector3(300, DECK_Y + 0.5, -150))
	_place(r, Vector3(0, DECK_Y + 0.5, 0))
	_place(w, Vector3(300, DECK_Y + 0.5, 0))
	_place(f, Vector3(600, DECK_Y + 0.5, 0))
	_place(p, Vector3(900, DECK_Y + 0.5, 0))
	_place(b, Vector3(1200, DECK_Y + 0.5, 0))
	await get_tree().physics_frame
	var fr: Vector3 = r.call("_lunge_facing")
	_place(tr, r.global_position + fr * 20.0)
	var fw: Vector3 = w.call("_lunge_facing")
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(8, 6, 1)
	wcs.shape = wbox
	wall.add_child(wcs)
	arena.add_child(wall)
	wall.global_position = w.global_position + fw * 10.0 + Vector3.UP * 3.0
	wall.look_at(w.global_position + Vector3.UP * 3.0)
	var fb: Vector3 = -(b.call("get_aim_basis") as Basis).z
	fb.y = 0.0
	_place(tb, b.global_position + fb.normalized() * 15.0)
	b.get("_input_source").set("difficulty", 3)
	for m in [tr, tb]:
		m.set("velocity", Vector3.ZERO)
	await get_tree().physics_frame

	var w0 := w.global_position
	var f0 := f.global_position
	var dmg0: float = tr.get("damage_taken_total")
	for m in [r, w, f, p]:
		m.call("_charge_press")
	var fv0: float = f.get("_charge_v0")  # standing: its walking pace (probes fly Pegasus)
	var pw: float = p.get("walk_speed")
	var wf := float(Engine.physics_ticks_per_second)
	var hits: Array = []  # damage steps on R's target
	var last_dmg := dmg0
	var r_hit_at := -1.0
	var r_over_at := -1.0
	var f_v1 := -1.0      # F's speed at 1 s
	var f_vmax := 0.0
	var f_rest_at := -1.0
	var f_pull := 4.0
	var p_v0 := -1.0
	var b_starts := 0
	var b_was := false
	for k in int(6.0 * wf):
		await get_tree().physics_frame
		var t := (k + 1) / wf
		var d: float = tr.get("damage_taken_total")
		if d > last_dmg:
			hits.append(d - last_dmg)
			last_dmg = d
			if r_hit_at < 0.0:
				r_hit_at = t
		if r_hit_at >= 0.0 and r_over_at < 0.0 and not r.get("lunging"):
			r_over_at = t
		var fv := _flat(f.get("velocity"))
		if absf(t - 1.0) < 0.5 / wf:
			f_v1 = fv
		if f.call("charging"):
			f_vmax = maxf(f_vmax, fv)
		if absf(t - f_pull) < 0.5 / wf:
			f.call("_charge_press")
		if t > f_pull and f_rest_at < 0.0 and not f.get("lunging"):
			f_rest_at = t
		if absf(t - 2.0) < 0.5 / wf:
			p.call("_charge_press")  # pull up
		if absf(t - 2.1) < 0.5 / wf:
			(p.get("torso") as Node3D).rotation.y += deg_to_rad(30.0)
			p.call("_charge_press")  # and set off again
			p_v0 = float(p.get("_charge_v0"))
		var bc: bool = b.call("charging")
		if bc and not b_was:
			b_starts += 1
		b_was = bc
	var bad: Array = []
	if hits.size() != 1:
		bad.append("R's target took %d ram hits %s (want exactly 1)" % [hits.size(), str(hits)])
	elif hits[0] < Mech.RAM_FLOOR - 0.01 or hits[0] > Mech.RAM_K * Mech.CHARGE_TOP + 1.0:
		bad.append("ram hit %.1f outside %.0f..%.0f" % [hits[0], Mech.RAM_FLOOR, Mech.RAM_K * Mech.CHARGE_TOP])
	if r_over_at < 0.0 or r_over_at - r_hit_at > Mech.CHARGE_HIT_S + 0.1:
		bad.append("R's charge didn't end CHARGE_HIT_S after the ram (hit %.2f, over %.2f)" % [r_hit_at, r_over_at])
	if _flat(r.get("velocity")) > 0.5:
		bad.append("R moving %.1f m/s after the ram" % _flat(r.get("velocity")))
	var wd := _flat(w.global_position - w0)
	if wd > 10.0 or wd < 7.0:
		bad.append("W went %.1f m toward a wall 10 m off (want stopped at it)" % wd)
	if w.get("lunging"):
		bad.append("W still charging after meeting the wall")
	if absf(fv0 - float(f.get("walk_speed"))) > 0.01:
		bad.append("F set off at %.2f m/s standing (want its walking pace %.2f)" % [fv0, f.get("walk_speed")])
	var want_v1: float = fv0 + Mech.CHARGE_ACCEL * 1.0
	if absf(f_v1 - want_v1) > 0.3:
		bad.append("F at %.1f m/s after 1 s (want %.1f: linear from walking pace)" % [f_v1, want_v1])
	if f_vmax > Mech.CHARGE_TOP + 0.01 or f_vmax < Mech.CHARGE_TOP - 0.01:
		bad.append("F topped out at %.2f m/s (want the cap %.1f)" % [f_vmax, Mech.CHARGE_TOP])
	var stop_s: float = Mech.CHARGE_TOP / Mech.CHARGE_DECEL
	if f_rest_at < 0.0 or f_rest_at - f_pull > stop_s + 0.05 or f_rest_at - f_pull < stop_s - 0.1:
		bad.append("F pulled up at %.2f s and was at rest at %.2f s (want ~%.2f s later)" % [f_pull, f_rest_at, stop_s])
	var want := 0.0
	var tt := 0.0
	while tt < f_pull + stop_s:
		tt += 1.0 / wf
		var v := minf(Mech.CHARGE_TOP, fv0 + Mech.CHARGE_ACCEL * minf(tt, f_pull))
		if tt > f_pull:
			v = maxf(0.0, v - Mech.CHARGE_DECEL * (tt - f_pull))
		want += v / wf
	var fd := _flat(f.global_position - f0)
	if absf(fd - want) > 1.0:
		bad.append("F covered %.1f m (curve says %.1f)" % [fd, want])
	if p_v0 < pw * 2.5:
		bad.append("P set off again at %.1f m/s 0.1 s after a pull-up (want the boost it kept, not walking pace)" % p_v0)
	if b_starts < 1:
		bad.append("the Hard bot never charged a target 15 m straight ahead")
	elif b_starts > 3:
		bad.append("the bot set off %d times in 6 s (flicking the toggle)" % b_starts)
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] charge done (ram %.0f at %.2f s, wall stop %.1f m, open %.1f m / %.1f, top %.1f, re-press %.1f m/s, bot %d)" % [hits[0], r_hit_at, wd, fd, want, f_vmax, p_v0, b_starts])
	_quit(0)
