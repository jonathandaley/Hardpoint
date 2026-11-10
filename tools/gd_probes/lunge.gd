extends Node
# T342 probe (Taurus LUNGE; user 2026-11-08: crouch windup, a straight dash that speeds up along a
# fixed curve, a quick stop; ramming deals damage from the closing speed with a high floor, once,
# then stops; walls stop it with no damage; bots lunge at a target straight ahead). On a deck high
# above the map, side by side (300 m apart), all at once:
#  R rams a standing enemy 12 m ahead: no motion in the windup (and the legs crouch), one ram of
#    RAM_FLOOR..full-speed damage, then it stands;
#  W lunges at a wall 8 m ahead: stops at the wall, nobody hurt;
#  F lunges into the open: covers the curve's distance and is done after LUNGE_TOTAL_S;
#  B is a Hard bot with the lunge and a target 10 m ahead: it lunges on its own; the cooldown
#    then holds it off for the ability's 5.5 s.

const Lunge := preload("res://resources/abilities/Lunge.tres")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] lunge FAIL: " + msg)
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
	box.size = Vector3(1600, 2, 400)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(600, DECK_Y - 1.0, 0)
	var t1: Array = arena.get("_team_mechs")[1]
	var t0: Array = arena.get("_team_mechs")[0]
	var r: Node3D = t1[0]
	var w: Node3D = t1[1]
	var f: Node3D = t1[2]
	var b: Node3D = t1[3]
	var tr: Node3D = t0[1]  # R's target
	var tb: Node3D = t0[2]  # B's target
	for m in t0 + [r, w, f]:
		_inert(m)
	for m in t0:
		_plain(m)
	for m in [r, w, f, b]:
		m.call("configure_abilities", [Lunge])
		m.set("invincible", true)
	_place(t0[0], Vector3(0, DECK_Y + 0.5, 150))  # the player's mech, out of everyone's way
	_place(t0[3], Vector3(0, DECK_Y + 0.5, -150))
	_place(r, Vector3(0, DECK_Y + 0.5, 0))
	_place(w, Vector3(300, DECK_Y + 0.5, 0))
	_place(f, Vector3(600, DECK_Y + 0.5, 0))
	_place(b, Vector3(900, DECK_Y + 0.5, 0))
	await get_tree().physics_frame
	var fr: Vector3 = r.call("_lunge_facing")
	_place(tr, r.global_position + fr * 12.0)
	var fw: Vector3 = w.call("_lunge_facing")
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(8, 6, 1)
	wcs.shape = wbox
	wall.add_child(wcs)
	arena.add_child(wall)
	wall.global_position = w.global_position + fw * 8.0 + Vector3.UP * 3.0
	wall.look_at(w.global_position + Vector3.UP * 3.0)
	var fb: Vector3 = -(b.call("get_aim_basis") as Basis).z
	fb.y = 0.0
	_place(tb, b.global_position + fb.normalized() * 10.0)
	b.get("_input_source").set("difficulty", 3)
	for m in [tr, tb]:
		m.set("velocity", Vector3.ZERO)
	await get_tree().physics_frame

	var r0 := r.global_position
	var w0 := w.global_position
	var f0 := f.global_position
	var dmg0: float = tr.get("damage_taken_total")
	for m in [r, w, f]:
		m.call("_activate_ability", Lunge)
	var crouched := false
	var windup_move := 0.0
	var hits: Array = []  # damage steps on R's target
	var last_dmg := dmg0
	var r_stopped_at := -1.0
	var f_done_at := -1.0
	var b_lunge_at := -1.0
	var b_again := false
	var wf := float(Engine.physics_ticks_per_second)
	for k in int(3.5 * wf):
		await get_tree().physics_frame
		var t := (k + 1) / wf
		if t < Mech.LUNGE_WINDUP_S - 0.01:  # T366: windups follow the knob (0.2 -> 0.12 s)
			windup_move = maxf(windup_move, Vector2(r.global_position.x - r0.x, r.global_position.z - r0.z).length())
		if t > 0.6 * Mech.LUNGE_WINDUP_S and t < Mech.LUNGE_WINDUP_S and float((r.get("legs") as Node).get("left_knee1").rotation.x) < -2.094 - 0.5:
			crouched = true
		var d: float = tr.get("damage_taken_total")
		if d > last_dmg:
			hits.append(d - last_dmg)
			last_dmg = d
		if r_stopped_at < 0.0 and not r.get("lunging"):
			r_stopped_at = t
		if f_done_at < 0.0 and not f.get("lunging"):
			f_done_at = t
		if b_lunge_at < 0.0 and b.get("lunging"):
			b_lunge_at = t
	# B again within its cooldown? watch until the cooldown since its first PRESS is about to end -- a
	# long first lunge put a legal second one inside a fixed 3 s window (T365: random mechs, other timings)
	if b_lunge_at >= 0.0:
		var was: bool = b.get("lunging")
		for k in int(maxf(0.0, b_lunge_at + float(Lunge.cooldown) - 0.1 - 3.5) * wf):
			await get_tree().physics_frame
			var now: bool = b.get("lunging")
			if now and not was:
				b_again = true
			was = now
	var bad: Array = []
	if windup_move > 0.05:
		bad.append("R moved %.2f m in the windup (want it planted)" % windup_move)
	if not crouched:
		bad.append("R's knees didn't fold in the windup")
	if hits.size() != 1:
		bad.append("R's target took %d ram hits %s (want exactly 1)" % [hits.size(), str(hits)])
	elif hits[0] < Mech.RAM_FLOOR - 0.01 or hits[0] > Mech.RAM_K * Mech.LUNGE_PEAK + 1.0:
		bad.append("ram hit %.1f outside %.0f..%.0f" % [hits[0], Mech.RAM_FLOOR, Mech.RAM_K * Mech.LUNGE_PEAK])
	if r_stopped_at < 0.0 or r_stopped_at > 2.2:
		bad.append("R still lunging at %.2f s (want it stopped by the ram)" % r_stopped_at)
	var rv: Vector3 = r.get("velocity")
	if Vector2(rv.x, rv.z).length() > 0.5:
		bad.append("R moving %.1f m/s after the ram" % Vector2(rv.x, rv.z).length())
	var wd := Vector2(w.global_position.x - w0.x, w.global_position.z - w0.z).length()
	if wd > 8.0 or wd < 5.0:
		bad.append("W went %.1f m toward a wall 8 m off (want stopped at it)" % wd)
	if w.get("lunging"):
		bad.append("W still lunging after meeting the wall")
	var want := 0.0
	var tt := 0.0
	while tt < Mech.LUNGE_TOTAL_S:
		tt += 1.0 / wf
		want += Mech.lunge_speed(tt) / wf
	var fd := Vector2(f.global_position.x - f0.x, f.global_position.z - f0.z).length()
	if absf(fd - want) > 1.0:
		bad.append("F covered %.1f m in the open (curve says %.1f)" % [fd, want])
	if f_done_at < Mech.LUNGE_TOTAL_S - 0.05 or f_done_at > Mech.LUNGE_TOTAL_S + 0.1:
		bad.append("F's lunge ended at %.2f s (want %.2f)" % [f_done_at, Mech.LUNGE_TOTAL_S])
	if b_lunge_at < 0.0:
		bad.append("the Hard bot never lunged at a target 10 m straight ahead")
	if b_again:
		bad.append("the bot lunged again inside its cooldown")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] lunge done (ram %.0f at %.2f s, wall stop %.1f m, open %.1f m / %.1f, bot at %.2f s)" % [hits[0], r_stopped_at, wd, fd, want, b_lunge_at])
	_quit(0)
