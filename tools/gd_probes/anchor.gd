extends Node
# T430 probe (Denali ANCHOR, design left to Claude 2026-11-16): planted for the ability's duration --
# a mech told to walk stays put (it walked before), its knees bend into the half crouch, hits on it
# do ANCHOR_DAMAGE_IN of a baseline hit and its own hits ANCHOR_DAMAGE_OUT; when the duration ends
# it walks again; a Hard bot with ANCHOR and a target in range plants on its own. On a deck high
# above the map, the walker and the bot 300 m apart.

const Anchor := preload("res://resources/abilities/Anchor.tres")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

class Walker extends "res://scripts/InputSource.gd":
	func get_move_direction() -> Vector2:
		return Vector2(0, -1)

func _fail(msg: String) -> void:
	push_error("[probe] anchor FAIL: " + msg)
	_quit(1)

func _quit(code: int) -> void:  # B124: stop sounds, let audio settle, then quit
	for n in get_tree().root.find_children("*", "", true, false):
		if n is AudioStreamPlayer3D or n is AudioStreamPlayer:
			n.stop()
	get_tree().paused = true
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_tree().quit(code)

func _source(m: Node, src: Node) -> void:
	add_child(src)  # freed with the probe
	m.call("set_input_source", src)

func _plain(m: Node) -> void:  # no shields, can't die in the window
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

func _hit(target: Node, shooter: Node) -> float:  # one weapon hit, damage actually taken
	var w: Node = (shooter.call("get_weapons") as Array)[0]
	var before: float = target.get("health")
	target.call("take_damage", float(w.get("damage")), w)
	return before - float(target.get("health"))

func _walked(m: Node3D, secs: float) -> float:
	var p0 := m.global_position
	for k in int(secs * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
	return Vector2(m.global_position.x - p0.x, m.global_position.z - p0.z).length()

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
	box.size = Vector3(1200, 2, 400)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(300, DECK_Y - 1.0, 0)
	var t1: Array = arena.get("_team_mechs")[1]
	var t0: Array = arena.get("_team_mechs")[0]
	var a: Node3D = t1[0]   # the walker that anchors
	var b: Node3D = t1[1]   # Hard bot with ANCHOR
	var ta: Node3D = t0[1]  # takes A's hits / shoots A
	var tb: Node3D = t0[2]  # B's target
	_source(a, Walker.new())
	for m in t0 + [t1[2], t1[3]]:
		_source(m, InputSource.new())
	for m in t0 + [a]:
		_plain(m)
	for m in [a, b]:
		m.call("configure_abilities", [Anchor])
	b.set("invincible", true)
	_place(t0[0], Vector3(0, DECK_Y + 0.5, 150))
	_place(t0[3], Vector3(0, DECK_Y + 0.5, -150))
	_place(t1[2], Vector3(150, DECK_Y + 0.5, 150))
	_place(t1[3], Vector3(150, DECK_Y + 0.5, -150))
	_place(a, Vector3(0, DECK_Y + 0.5, 0))
	_place(b, Vector3(300, DECK_Y + 0.5, 0))
	await get_tree().physics_frame
	var fa: Vector3 = -(a.call("get_aim_basis") as Basis).z
	fa.y = 0.0
	_place(ta, a.global_position + fa.normalized() * 12.0)
	var fb: Vector3 = -(b.call("get_aim_basis") as Basis).z
	fb.y = 0.0
	_place(tb, b.global_position + fb.normalized() * 10.0)
	b.get("_input_source").set("difficulty", 3)
	var bot_planted := [false]
	var watch := func() -> void:
		if b.get("anchored"):
			bot_planted[0] = true
	get_tree().physics_frame.connect(watch)

	var bad: Array = []
	var free_walk: float = await _walked(a, 1.0)
	var hit_in0 := _hit(a, ta)
	var hit_out0 := _hit(ta, a)
	a.call("_activate_ability", Anchor)
	if not a.get("anchored"):
		bad.append("ANCHOR didn't set anchored")
	var planted_walk: float = await _walked(a, 1.0)
	var pose: Vector3 = (a.get("legs") as Node).get("_pose")
	var hit_in := _hit(a, ta)
	var hit_out := _hit(ta, a)
	await _walked(a, Anchor.duration - 0.8)  # past the duration
	var after_anchor: bool = a.get("anchored")
	var walk_after: float = await _walked(a, 1.0)
	for k in int(4.0 * Engine.physics_ticks_per_second):  # the bot's chance (it already had ~9 s)
		if bot_planted[0]:
			break
		await get_tree().physics_frame
	get_tree().physics_frame.disconnect(watch)

	if free_walk < 0.3:
		bad.append("A only walked %.2f m in 1 s before anchoring (setup)" % free_walk)
	if planted_walk > 0.05:
		bad.append("A moved %.2f m in 1 s while anchored (want planted)" % planted_walk)
	if pose.x < 0.3:
		bad.append("A's legs not crouched while anchored (pose %s)" % str(pose))
	if hit_in0 <= 0.0 or absf(hit_in / hit_in0 - Mech.ANCHOR_DAMAGE_IN) > 0.02:
		bad.append("hit on A while anchored %.1f vs %.1f before (want x%.2f)" % [hit_in, hit_in0, Mech.ANCHOR_DAMAGE_IN])
	if hit_out0 <= 0.0 or absf(hit_out / hit_out0 - Mech.ANCHOR_DAMAGE_OUT) > 0.02:
		bad.append("A's hit while anchored %.1f vs %.1f before (want x%.2f)" % [hit_out, hit_out0, Mech.ANCHOR_DAMAGE_OUT])
	if after_anchor:
		bad.append("A still anchored after the %.0f s duration" % Anchor.duration)
	if walk_after < 0.3:
		bad.append("A only walked %.2f m in 1 s after the anchor ended" % walk_after)
	if not bot_planted[0]:
		bad.append("the Hard bot never anchored with a target 10 m ahead")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] anchor done (walk %.2f -> %.2f -> %.2f m/s, in x%.2f, out x%.2f, crouch %.2f)" % [
		free_walk, planted_walk, walk_after, hit_in / hit_in0, hit_out / hit_out0, pose.x])
	_quit(0)
