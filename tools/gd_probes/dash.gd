extends Node
# T454 probe (Swift DASH; user 2026-11-17: "add as many mechs as you think are good"): a short burst
# along the move input, on the lunge's clock with its own curve. On a deck high above the map:
#  S strafes right and dashes: it goes ~the curve's distance to its RIGHT (not along its facing),
#    and is done after the curve's length;
#  N dashes with no input: along its facing;
#  E dashes sideways into an enemy 2.5 m off: stops at it, the enemy takes no damage (no ram);
#  B is a Hard bot with DASH and a target in range: it dashes on its own, no more than its charges
#    plus what recharged in 6 s;
# then (user 2026-11-17: "two charges, which each charge recharges separately"; "slower than slip
# over sustained distance"):
#  S again, fresh (user: "recharge sequentially, but the first should recharge as soon as it's spent
#    and not wait for the second"): two presses 1 s apart both dash, a third right after doesn't;
#    one is back `cooldown` after the FIRST use (not after the second), the other a cooldown later
#    (not `cooldown` after its own use: that would be parallel);
#  on a second deck, from steady state (both charges just spent), a Swift walking forward and dashing
#    whenever it can covers less ground in 60 s than a mech walking at Slip's speed -- with no skills,
#    and with Swift's MOVE SPEED + ABILITY RECHARGE maxed vs Slip's MOVE SPEED maxed.

const Dash := preload("res://resources/abilities/Dash.tres")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

class Steer extends "res://scripts/InputSource.gd":
	var move := Vector2.ZERO
	var press := false  # one tick
	var hold := false   # every tick
	func get_move_direction() -> Vector2:
		return move
	func is_ability_pressed() -> bool:
		var p := press or hold
		press = false
		return p

func _fail(msg: String) -> void:
	push_error("[probe] dash FAIL: " + msg)
	_quit(1)

func _quit(code: int) -> void:  # B124: stop sounds before quitting
	for n in get_tree().root.find_children("*", "", true, false):
		if n is AudioStreamPlayer3D or n is AudioStreamPlayer:
			n.stop()
	get_tree().paused = true
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_tree().quit(code)

func _steer(m: Node) -> Steer:
	var src := Steer.new()
	add_child(src)
	m.call("set_input_source", src)
	return src

func _place(m: Node3D, at: Vector3) -> void:
	m.global_position = at
	m.set("velocity", Vector3.ZERO)

static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

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
	var s: Node3D = t1[0]
	var n: Node3D = t1[1]
	var e: Node3D = t1[2]
	var b: Node3D = t1[3]
	var te: Node3D = t0[1]  # E's obstacle
	var tb: Node3D = t0[2]  # B's target
	var ss := _steer(s)
	_steer(n)
	var es := _steer(e)
	for m in t0:
		_steer(m)
		m.set("max_health", 1.0e6)
		m.set("health", 1.0e6)
	for m in [s, n, e, b]:
		m.call("configure_abilities", [Dash])
		m.set("invincible", true)
	_place(t0[0], Vector3(0, DECK_Y + 0.5, 150))
	_place(t0[3], Vector3(0, DECK_Y + 0.5, -150))
	_place(s, Vector3(0, DECK_Y + 0.5, 0))
	_place(n, Vector3(300, DECK_Y + 0.5, 0))
	_place(e, Vector3(600, DECK_Y + 0.5, 0))
	_place(b, Vector3(900, DECK_Y + 0.5, 0))
	await get_tree().physics_frame
	var right_s := _flat((s.get("torso") as Node3D).global_transform.basis.x).normalized()
	var face_n := _flat(n.call("_lunge_facing") as Vector3)
	var right_e := (e.get("torso") as Node3D).global_transform.basis.x
	right_e.y = 0.0
	_place(te, e.global_position + right_e.normalized() * 2.5)
	var fb: Vector3 = -(b.call("get_aim_basis") as Basis).z
	fb.y = 0.0
	_place(tb, b.global_position + fb.normalized() * 15.0)
	b.get("_input_source").set("difficulty", 3)
	await get_tree().physics_frame

	var s0 := s.global_position
	var n0 := n.global_position
	var e0 := e.global_position
	var dmg0: float = te.get("damage_taken_total")
	ss.move = Vector2(1, 0)
	es.move = Vector2(1, 0)
	await get_tree().physics_frame
	for m in [s, n, e]:
		m.call("_activate_ability", Dash)
	ss.move = Vector2.ZERO  # the dash keeps the direction it started with
	es.move = Vector2.ZERO
	var wf := float(Engine.physics_ticks_per_second)
	var s_done := -1.0
	var b_at := -1.0
	var b_dashes := 0
	var b_was := false
	for k in int(6.0 * wf):
		await get_tree().physics_frame
		var t := (k + 1) / wf
		if s_done < 0.0 and not s.get("lunging"):
			s_done = t
		var bl: bool = b.get("lunging")
		if bl and not b_was:
			b_dashes += 1
			if b_at < 0.0:
				b_at = t
		b_was = bl
	var total: float = Mech.DASH_S + Mech.DASH_STOP_S
	var want := 0.0
	var tt := 0.0
	while tt < total:
		tt += 1.0 / wf
		want += Mech.lunge_speed(tt, true) / wf
	var bad: Array = []
	var ds := _flat(s.global_position - s0)
	if ds.length() < want - 1.0 or ds.length() > want + 1.0:
		bad.append("S dashed %.1f m (curve says %.1f)" % [ds.length(), want])
	if ds.length() > 0.5 and ds.normalized().dot(right_s) < 0.9:
		bad.append("S went %s, not to its right %s" % [ds.normalized(), right_s])
	if s_done < 0.0 or absf(s_done - total) > 0.1:
		bad.append("S's dash ended at %.2f s (want %.2f)" % [s_done, total])
	var dn := _flat(n.global_position - n0)
	if dn.length() < want - 1.0 or dn.normalized().dot(face_n) < 0.9:
		bad.append("N (no input) went %.1f m along %s (want ~%.1f along its facing %s)" % [dn.length(), dn.normalized(), want, face_n])
	var de := _flat(e.global_position - e0).length()
	if de > 2.5:
		bad.append("E went %.1f m into a mech 2.5 m off" % de)
	if float(te.get("damage_taken_total")) > dmg0 + 0.01:
		bad.append("E's dash dealt %.1f damage (a dash doesn't ram)" % (float(te.get("damage_taken_total")) - dmg0))
	if b_at < 0.0:
		bad.append("the Hard bot never dashed with a target 15 m off")
	var b_max: int = Dash.charges + int(6.0 / float(Dash.cooldown))  # the charges + whatever recharged
	if b_dashes > b_max:
		bad.append("the bot dashed %d times in 6 s (at most %d)" % [b_dashes, b_max])
	# ---- charges ----
	s.call("configure_abilities", [Dash])
	var used: Array = []  # times a press started a dash
	var refused := false
	var ready_at_first := -1   # first use + cd: want 1
	var ready_at_second := -1  # second use + cd: want 1 (parallel: 2)
	var ready_at_end := -1     # first use + 2 cd: want 2
	var cd := float(Dash.cooldown)
	var was: bool = s.get("lunging")
	for k in int((2.0 * cd + 0.6) * wf):
		var t := k / wf
		if k == 0 or k == int(1.0 * wf) or k == int(1.5 * wf):
			ss.press = true
		await get_tree().physics_frame
		var now: bool = s.get("lunging")
		if now and not was:
			used.append(t)
		was = now
		var ready: int = int(((s.get("_ability_charges") as Dictionary).get("dash", [0]) as Array)[0])
		if used.size() >= 1 and ready_at_first < 0 and t >= used[0] + cd + 0.2:
			ready_at_first = ready
		if used.size() >= 2 and ready_at_second < 0 and t >= used[1] + cd + 0.2:
			ready_at_second = ready
		if used.size() >= 1 and ready_at_end < 0 and t >= used[0] + 2.0 * cd + 0.2:
			ready_at_end = ready
	if used.size() != 2:
		bad.append("3 presses (0, 1, 1.5 s) dashed %d times (want 2: two charges)" % used.size())
	elif ready_at_first != 1 or ready_at_second != 1 or ready_at_end != 2:
		bad.append("charges ready %d at first use + cd (want 1), %d at second use + cd (want 1: one at a time), %d at first + 2 cd (want 2)" % [ready_at_first, ready_at_second, ready_at_end])
	# ---- sustained speed vs Slip: steady state (both charges just spent), 60 s, no skills and maxed ----
	var deck2 := StaticBody3D.new()
	var cs2 := CollisionShape3D.new()
	var box2 := BoxShape3D.new()
	box2.size = Vector3(3000, 2, 3000)
	cs2.shape = box2
	deck2.add_child(cs2)
	arena.add_child(deck2)
	deck2.global_position = Vector3(0, DECK_Y + 99.0, 0)
	var slip_def: Resource = load("res://resources/mechs/Slip.tres")
	var swift_def: Resource = load("res://resources/mechs/Swift.tres")
	var ms := 1.0 + Game.skill_effect_in({"move_speed": 12}, "move_speed")
	var ns := _steer(n)
	var ws := _steer(t0[3])
	# [mech, steer, def, speed x, skills, dashes]
	var runs := [[s, ss, swift_def, 1.0, {}, true], [t0[3], ws, slip_def, 1.0, {}, false],
		[n, ns, swift_def, ms, {"move_speed": 12, "ability_recharge": 12}, true], [e, es, slip_def, ms, {"move_speed": 12}, false]]
	var starts: Array = []
	for i in runs.size():
		var r: Array = runs[i]
		var m: Node3D = r[0]
		m.set("base_walk_speed", r[2].walk_speed * r[3])  # walk_speed is a getter (modifiers, terrain)
		m.set("turn_acceleration", r[2].turn_acceleration)
		m.set("pilot_skills", r[4])
		m.call("configure_abilities", [Dash] if r[5] else [])
		if r[5]:  # steady state: both charges just spent
			var c := float(Dash.cooldown) * (1.0 - float(m.call("skill", "ability_recharge")) * Dash.recharge_skill_k)
			(m.get("_ability_charges") as Dictionary)["dash"] = [0, c, Dash.charges, c]
			(m.get("_ability_cooldowns") as Dictionary)["dash"] = c
		_place(m, Vector3(-600 + 400 * i, DECK_Y + 100.5, 0))
	await get_tree().physics_frame
	for r in runs:
		starts.append((r[0] as Node3D).global_position)
		(r[1] as Steer).move = Vector2(0, -1)
		(r[1] as Steer).hold = r[5]
	for k in int(60.0 * wf):
		await get_tree().physics_frame
	var got: Array = []
	for i in runs.size():
		(runs[i][1] as Steer).hold = false
		(runs[i][1] as Steer).move = Vector2.ZERO
		got.append(_flat((runs[i][0] as Node3D).global_position - starts[i]).length())
	for pair in [[0, 1, "no skills"], [2, 3, "Swift MOVE SPEED + ABILITY RECHARGE 12 vs Slip MOVE SPEED 12"]]:
		if got[pair[0]] >= 0.95 * got[pair[1]]:
			bad.append("%s: Swift dashing all it can went %.0f m in 60 s, Slip walking %.0f m (want Swift < 95%%)" % [pair[2], got[pair[0]], got[pair[1]]])
	var swift_m: float = got[0]
	var slip_m: float = got[1]
	print("[probe] dash: maxed skills, 60 s: Swift %.0f m vs Slip %.0f m" % [got[2], got[3]])
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] dash: charges at %s, 60 s: Swift %.0f m vs Slip %.0f m" % [str(used), swift_m, slip_m])
	print("[probe] dash done (side %.1f m / %.1f in %.2f s, facing %.1f m, blocked at %.1f m, bot at %.2f s)" % [ds.length(), want, s_done, dn.length(), de, b_at])
	_quit(0)
