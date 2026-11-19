extends Node
# T493 probe (HUMAN_FOUND 2026-11-18: "Bots do not switch targets if their chosen target is behind an
# obstacle and there are other valid targets nearby ... keeping their target behind a wall should not
# render them all impotent."): a Normal bot set on a hurt enemy A behind a wall, enemy V in plain sight
# 20 m off: within a few seconds it takes V, and keeps it (no flipping straight back).

const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] bot_retarget FAIL: " + msg)
	get_tree().quit(1)

func _inert(m: Node) -> void:
	var src: Node = InputSource.new()
	add_child(src)
	m.call("set_input_source", src)

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
	for i in 10:
		await get_tree().physics_frame
	var deck := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(800, 2, 800)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(0, DECK_Y - 1.0, 0)
	var t0: Array = arena.get("_team_mechs")[0]
	var t1: Array = arena.get("_team_mechs")[1]
	var b: Node3D = t1[0]
	var a: Node3D = t0[1]
	var v: Node3D = t0[2]
	for m in t0 + [t1[1], t1[2]]:
		_inert(m)
		m.set("invincible", true)
	b.set("invincible", true)
	var ai: Node = b.get("_input_source")
	ai.set("difficulty", 1)
	(t0[0] as Node3D).global_position = Vector3(-350, DECK_Y + 0.5, 0)
	(t1[1] as Node3D).global_position = Vector3(350, DECK_Y + 0.5, 300)
	(t1[2] as Node3D).global_position = Vector3(350, DECK_Y + 0.5, -300)
	b.global_position = Vector3(0, DECK_Y + 0.5, 0)
	a.global_position = Vector3(15, DECK_Y + 0.5, 0)
	v.global_position = Vector3(0, DECK_Y + 0.5, 20)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(1, 8, 8)
	wcs.shape = wbox
	wall.add_child(wcs)
	arena.add_child(wall)
	wall.global_position = Vector3(7, DECK_Y + 4.0, 0)
	a.set("health", float(a.get("max_health")) * 0.2)  # hurt: the score's favourite
	for m in [a, v, b]:
		m.set("velocity", Vector3.ZERO)
	await get_tree().physics_frame
	ai.set("_target", a)
	var wf := float(Engine.physics_ticks_per_second)
	var took_v := -1.0
	var flipped := false
	for k in int(10.0 * wf):
		await get_tree().physics_frame
		b.global_position = Vector3(0, b.global_position.y, 0)  # holds its ground: the test is the choice
		var t: Node = ai.get("_target")
		if took_v < 0.0 and t == v:
			took_v = (k + 1) / wf
		elif took_v >= 0.0 and t == a and (k + 1) / wf < took_v + 3.5:
			flipped = true
	if took_v < 0.0:
		_fail("the bot kept a target behind a wall for 10 s with another in plain sight 20 m off")
		return
	if flipped:
		_fail("the bot flipped straight back to the hidden target")
		return
	print("[probe] bot_retarget done (took the visible enemy at %.1f s)" % took_v)
	get_tree().quit(0)
