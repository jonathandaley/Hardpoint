extends Node
# T455 probe (Heron FIELD REPAIR; user 2026-11-17: "add as many mechs as you think are good"): for the
# ability's duration the server repairs Heron and every living ally within Mech.FIELD_R. On a deck:
#  H (Heron, half health) repairs: itself +150 over the 5 s; ally A at 10 m, 50 HP down, back to
#    exactly max (never past); ally F at 25 m untouched; enemy E at 10 m not repaired; the ring
#    shows while it runs, not after;
#  B is a Hard bot Heron: an ally at 70% health walks into reach -> it repairs on its own.

const FieldRepair := preload("res://resources/abilities/FieldRepair.tres")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] field_repair FAIL: " + msg)
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
	var h: Node3D = t1[0]
	var a: Node3D = t1[1]
	var f: Node3D = t1[2]
	var b: Node3D = t1[3]
	var e: Node3D = t0[1]
	for m in [h, a, f, e, t0[0], t0[2], t0[3]]:
		_inert(m)
	for m in [h, b]:
		m.call("configure_abilities", [FieldRepair])
	_place(t0[0], Vector3(0, DECK_Y + 0.5, 150))
	_place(t0[2], Vector3(300, DECK_Y + 0.5, 150))
	_place(t0[3], Vector3(600, DECK_Y + 0.5, 150))
	_place(h, Vector3(0, DECK_Y + 0.5, 0))
	_place(a, Vector3(10, DECK_Y + 0.5, 0))
	_place(f, Vector3(-25, DECK_Y + 0.5, 0))
	_place(e, Vector3(0, DECK_Y + 0.5, 10))
	_place(b, Vector3(1500, DECK_Y + 0.5, 0))
	await get_tree().physics_frame
	h.set("health", 0.5 * float(h.get("max_health")))
	a.set("health", float(a.get("max_health")) - 50.0)
	f.set("health", 0.5 * float(f.get("max_health")))
	e.set("health", 0.5 * float(e.get("max_health")))
	var h0: float = h.get("health")
	var f0: float = f.get("health")
	var e0: float = e.get("health")
	h.call("_activate_ability", FieldRepair)
	var wf := float(Engine.physics_ticks_per_second)
	var ring_during := false
	for k in int((FieldRepair.duration + 0.5) * wf):
		await get_tree().physics_frame
		if k == int(wf):
			var ring: Node3D = h.get("_field_ring")
			ring_during = ring != null and ring.is_visible_in_tree()
	var bad: Array = []
	var dh: float = float(h.get("health")) - h0
	var want: float = Mech.FIELD_HPS * FieldRepair.duration
	if absf(dh - want) > 3.0:
		bad.append("H repaired itself %.1f (want %.0f)" % [dh, want])
	if not is_equal_approx(float(a.get("health")), float(a.get("max_health"))):
		bad.append("A (50 down, 10 m) at %.1f / %.1f (want exactly max)" % [a.get("health"), a.get("max_health")])
	if float(f.get("health")) != f0:
		bad.append("F 25 m off went %.1f -> %.1f (out of reach)" % [f0, f.get("health")])
	if float(e.get("health")) > e0:
		bad.append("enemy E repaired %.1f -> %.1f" % [e0, e.get("health")])
	if not ring_during:
		bad.append("no ring while FIELD REPAIR ran")
	var ring_after: Node3D = h.get("_field_ring")
	if ring_after != null and ring_after.is_visible_in_tree():
		bad.append("ring still showing after the ability ended")
	# T487: the player's own Heron always shows its reach, dim while the ability is off
	var me: Node = arena.get("player_mech")
	me.call("configure_abilities", [FieldRepair])
	await get_tree().process_frame
	await get_tree().process_frame
	var mine: MeshInstance3D = me.get("_field_ring")
	if mine == null or not mine.is_visible_in_tree() or absf((mine.material_override as StandardMaterial3D).albedo_color.a - Mech.FIELD_RING_IDLE_A) > 0.01:
		bad.append("our own Heron doesn't show its reach while FIELD REPAIR is off")
	if h.get("field_repair"):
		bad.append("H still repairing after the duration")
	# bot: a hurt ally walks into reach
	b.get("_input_source").set("difficulty", 3)
	a.set("health", 0.7 * float(a.get("max_health")))
	_place(a, b.global_position + Vector3(8, 0, 0))
	var b_at := -1.0
	for k in int(3.0 * wf):
		await get_tree().physics_frame
		if b.get("field_repair"):
			b_at = k / wf
			break
	if b_at < 0.0:
		bad.append("the bot Heron never repaired with an ally at 70% 8 m off")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] field_repair done (self +%.0f, ally to max, far / enemy untouched, bot at %.2f s)" % [dh, b_at])
	_quit(0)
