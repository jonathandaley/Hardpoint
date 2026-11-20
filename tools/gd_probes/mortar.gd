extends Node
# T458 probe (Mortar; user 2026-11-17: "add as many mechs as you think are good. Also maps and
# weapons."): a shell lobbed onto an aim point lands there -- over a wall that blocks any straight
# shot. On a deck:
#  F lobs at T 40 m away behind a 7 m wall 12 m out: the shell clears the wall and T takes the burst
#    (direct or splash, within damage + splash); the burst lands within 2 m of the aim point;
#  launch_velocity lands on its point for 20, 60 and 120 m (the arc maths, no physics);
#  B is a Hard bot with a mortar and a target behind a wall (no clear shot): it fires anyway.
# T532 (range by wheel / arrows, direction by horizontal aim): step_range's default / steps / clamps; F's
# aim point lies lob_range out along its facing, on the deck, the same at any camera pitch; held wheel
# input (ReplayInputSource "wheel") steps F's lob_range; the landing arrow's material ignores fog.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] mortar FAIL: " + msg)
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

func _plain(m: Node) -> void:
	var es: Node = m.get("_energy_shield")
	if es != null:
		es.set("_active", false)
	var ps: Node = m.get("_shield")
	if is_instance_valid(ps) and ps.visible:
		ps.call("_break")
	m.set("invincible", false)
	m.set("max_health", 1.0e5)
	m.set("health", 1.0e5)

func _place(m: Node3D, at: Vector3) -> void:
	m.global_position = at
	m.set("velocity", Vector3.ZERO)

func _wall(arena: Node, at: Vector3, face: Vector3) -> void:
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(12, 7, 1)
	wcs.shape = wb
	wall.add_child(wcs)
	arena.add_child(wall)
	wall.global_position = at + Vector3.UP * 3.5
	wall.look_at(face + Vector3.UP * 3.5)

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
	var bad: Array = []
	for d in [20.0, 60.0, 120.0]:  # the arc maths: integrate the same way the shell flies
		var from := Vector3(0, 2, 0)
		var to := Vector3(d * 0.6, -1.0, d * 0.8)
		var v: Vector3 = Mortar.launch_velocity(from, to)
		var p := from
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var t := 0.0
		var tf: float = Mortar.flight_time(d)
		while t < tf - 0.5 * dt:
			v.y -= Mortar.G * dt
			p += v * dt
			t += dt
		if p.distance_to(to) > 1.5:
			bad.append("launch_velocity for %.0f m lands %.1f m off" % [d, p.distance_to(to)])
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
	var f: Node3D = t1[0]
	var b: Node3D = t1[1]
	var tg: Node3D = t0[1]
	var tb: Node3D = t0[2]
	for m in [f, t1[2], t0[0], tg, tb]:
		_inert(m)
	_plain(tg)
	_plain(tb)
	var slot := SlotDef.new()
	slot.slot_size = 1
	slot.position = Vector3(0.6, 1.8, 0)
	slot.weapon_scene = load("res://scenes/weapons/MortarHeavy.tscn")
	f.call("configure_weapons", [slot])
	b.call("configure_weapons", [slot])
	_place(t0[0], Vector3(0, DECK_Y + 0.5, 150))
	_place(t1[2], Vector3(300, DECK_Y + 0.5, 150))
	_place(f, Vector3(0, DECK_Y + 0.5, 0))
	_place(b, Vector3(600, DECK_Y + 0.5, 0))
	await get_tree().physics_frame
	var fwd: Vector3 = f.call("_lunge_facing")
	_place(tg, f.global_position + fwd * 40.0)
	_wall(arena, f.global_position + fwd * 12.0, f.global_position)
	var bfwd: Vector3 = b.call("_lunge_facing")
	_place(tb, b.global_position + bfwd * 45.0)
	_wall(arena, b.global_position + bfwd * 12.0, b.global_position)
	b.get("_input_source").set("difficulty", 3)
	await get_tree().physics_frame
	var gun: Node = f.call("get_weapons")[0]
	var hp0: float = tg.get("health")
	var aim: Vector3 = tg.global_position
	gun.call("launch_at", aim)
	var boom_at := Vector3.INF
	var wf := float(Engine.physics_ticks_per_second)
	for k in int((Mortar.flight_time(40.0) + 1.0) * wf):
		await get_tree().physics_frame
		if boom_at == Vector3.INF:
			for n in get_tree().current_scene.find_children("Explosion", "", true, false):
				boom_at = (n as Node3D).global_position
	var took: float = hp0 - float(tg.get("health"))
	if took <= 0.0:
		bad.append("T behind the wall took nothing (burst at %s)" % boom_at)
	elif took > float(gun.get("damage")) + float(gun.get("splash_damage")) + 1.0:
		bad.append("T took %.0f (more than a direct hit + splash)" % took)
	if boom_at != Vector3.INF and Vector2(boom_at.x - aim.x, boom_at.z - aim.z).length() > 2.0:
		bad.append("the burst landed %.1f m from the aim point" % Vector2(boom_at.x - aim.x, boom_at.z - aim.z).length())
	# bot: a target it can't see
	var bgun: Node = b.call("get_weapons")[0]
	var ammo0: int = bgun.get("ammo")
	var fired := false
	for k in int(6.0 * wf):
		await get_tree().physics_frame
		if int(bgun.get("ammo")) < ammo0:
			fired = true
			break
	if not fired:
		bad.append("the bot never lobbed at a target behind a wall")
	# T532: range by the wheel, direction by horizontal aim
	var mg := gun as Mortar
	for c in [[-1.0, 0.0, Mortar.LOB_DEFAULT], [-1.0, 3.0, Mortar.LOB_DEFAULT + 3.0 * Mortar.LOB_STEP],
			[-1.0, -100.0, Mortar.LOB_MIN], [-1.0, 100.0, mg.range], [60.0, -1.0, 60.0 - Mortar.LOB_STEP]]:
		if absf(mg.step_range(c[0], c[1]) - c[2]) > 0.01:
			bad.append("step_range(%s, %s) = %.1f, want %.1f" % [c[0], c[1], mg.step_range(c[0], c[1]), c[2]])
	f.set("lob_range", 30.0)
	var pts: Array = []
	for pitch in [-1.0, 0.0, 0.4]:
		f.set("_camera_pitch", pitch)
		pts.append(mg.aim_point())
	var flat_d := Vector2(pts[0].x - mg.global_position.x, pts[0].z - mg.global_position.z).length()
	if absf(flat_d - 30.0) > 0.2 or absf(pts[0].y - DECK_Y) > 0.6:
		bad.append("lob_range 30: the aim point is %.1f m out at y %.1f (want 30 m, on the deck)" % [flat_d, pts[0].y])
	if pts[0].distance_to(pts[1]) > 0.01 or pts[0].distance_to(pts[2]) > 0.01:
		bad.append("the aim point moves with camera pitch (%s / %s / %s)" % pts)
	var rep_src := preload("res://scripts/ReplayInputSource.gd").new()
	add_child(rep_src)
	rep_src.load_spec({"keyframes": [{"tick": 0, "wheel": 1.0}, {"tick": 3, "wheel": 0.0}]})
	f.call("set_input_source", rep_src)
	for k in 6:
		await get_tree().physics_frame
	var lr: float = f.get("lob_range")
	if lr < 30.0 + 2.0 * Mortar.LOB_STEP - 0.01:
		bad.append("held wheel input left lob_range at %.1f (from 30)" % lr)
	var arrow := Mortar._arrow()
	if not ((arrow.get_child(0) as MeshInstance3D).material_override as BaseMaterial3D).disable_fog:
		bad.append("the landing arrow's material doesn't ignore fog")
	arrow.free()
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] mortar done (T took %.0f behind the wall, burst %.1f m off, bot fired)" % [took, Vector2(boom_at.x - aim.x, boom_at.z - aim.z).length() if boom_at != Vector3.INF else -1.0])
	_quit(0)
