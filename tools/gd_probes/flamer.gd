extends Node
# T457 probe (Flamer; user 2026-11-17: "add as many mechs as you think are good. Also maps and
# weapons."): a flame cone. On a deck, F holds the trigger of a FLAMER LT for 2 s at enemies:
#  N 8 m straight ahead burns: hit every tick, keeps burning for burn_s after (health still falls,
#    then stops), the hits pass the server's per-hit check;
#  R 17 m ahead (past the 14 m reach), S 8 m off at 40 deg (outside the cone) and W 8 m ahead
#    behind a wall: untouched;
#  the tank (ammo) runs down while it fires and refills after.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const InputSource := preload("res://scripts/InputSource.gd")
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] flamer FAIL: " + msg)
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
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(0, DECK_Y - 1.0, 0)
	var t1: Array = arena.get("_team_mechs")[1]
	var t0: Array = arena.get("_team_mechs")[0]
	var f: Node3D = t1[0]
	for m in t1 + t0:
		_inert(m)
	for i in range(1, t1.size()):
		_place(t1[i], Vector3(150, DECK_Y + 0.5, -150 + 40 * i))  # F's team, out of the way
	_place(t0[0], Vector3(-150, DECK_Y + 0.5, 150))
	var n: Node3D = t0[1]
	var r: Node3D = t0[2]
	var sd: Node3D = t0[3]
	var w: Node3D = t0[4]
	for m in [n, r, sd, w]:
		_plain(m)
	var slot := SlotDef.new()
	slot.slot_size = 0
	slot.position = Vector3(0, 1.6, 0)
	slot.weapon_scene = load("res://scenes/weapons/FlamerLight.tscn")
	f.call("configure_weapons", [slot])
	var gun: Node = f.call("get_weapons")[0]
	_place(f, Vector3(0, DECK_Y + 0.5, 0))
	await get_tree().physics_frame
	var fwd: Vector3 = f.call("_lunge_facing")
	var side := fwd.rotated(Vector3.UP, deg_to_rad(40.0))
	_place(n, f.global_position + fwd * 8.0)
	_place(r, f.global_position + fwd * 17.0 + fwd.cross(Vector3.UP) * 6.0)  # beside N's line: N can't shadow it
	_place(sd, f.global_position + side * 8.0)
	_place(w, f.global_position - fwd.cross(Vector3.UP) * 30.0 + fwd * 8.0)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(4, 6, 0.5)
	wcs.shape = wb
	wall.add_child(wcs)
	arena.add_child(wall)
	var f2: Node3D = t1[1]  # W's own flamer, aimed the same way past a wall
	_place(f2, f.global_position - fwd.cross(Vector3.UP) * 30.0)
	f2.call("configure_weapons", [slot])
	wall.global_position = f2.global_position + fwd * 4.0 + Vector3.UP * 3.0
	wall.look_at(f2.global_position + Vector3.UP * 3.0)
	f2.rotation = f.rotation
	(f2.get("torso") as Node3D).rotation = (f.get("torso") as Node3D).rotation
	var gun2: Node = f2.call("get_weapons")[0]
	await get_tree().physics_frame
	var hp := {}
	for m in [n, r, sd, w]:
		hp[m] = float(m.get("health"))
	var ammo0: int = gun.get("ammo")
	var wf := float(Engine.physics_ticks_per_second)
	for k in int(2.0 * wf):
		gun.call("fire")
		gun2.call("fire")
		await get_tree().physics_frame
	var ammo_low: int = gun.get("ammo")
	var hit_n: float = hp[n] - float(n.get("health"))
	var burning: bool = float(n.get("burn_s")) > 0.0
	var at_stop: float = n.get("health")
	for k in int(0.5 * wf):
		await get_tree().physics_frame
	var after_half: float = at_stop - float(n.get("health"))
	for k in int(3.0 * wf):
		await get_tree().physics_frame
	var at_end: float = n.get("health")
	for k in int(1.0 * wf):
		await get_tree().physics_frame
	var bad: Array = []
	var shots := 2.0 * float(gun.get("fire_rate"))
	if hit_n < 0.8 * shots * float(gun.get("damage")):
		bad.append("N 8 m ahead took %.1f from ~%d ticks of %.1f" % [hit_n, int(shots), gun.get("damage")])
	if not burning or after_half < 0.4 * float(gun.get("burn_dps")) * 0.5:
		bad.append("N not burning after the flame (burning %s, %.2f in 0.5 s)" % [burning, after_half])
	if absf(float(n.get("health")) - at_end) > 0.01:
		bad.append("N still burning %.1f s after (burn_s %.1f)" % [4.5 - 2.0, gun.get("burn_s")])
	for pair in [[r, "R 17 m (past the reach)"], [sd, "S at 40 deg"], [w, "W behind a wall"]]:
		if float(pair[0].get("health")) < hp[pair[0]]:
			bad.append("%s took %.1f" % [pair[1], hp[pair[0]] - float(pair[0].get("health"))])
	if ammo_low >= ammo0:
		bad.append("the tank didn't run down (%d -> %d)" % [ammo0, ammo_low])
	if int(gun.get("ammo")) <= ammo_low:
		bad.append("the tank didn't refill (%d after, %d at the stop)" % [gun.get("ammo"), ammo_low])
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] flamer done (N took %.0f + burning, tank %d -> %d -> %d)" % [hit_n, ammo0, ammo_low, gun.get("ammo")])
	_quit(0)
