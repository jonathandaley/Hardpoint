extends Node
# T260 probe (HUMAN_FOUND_ISSUES 2026-11-05: "Patience shot: thick beam that fades slowly"):
# a fully charged Patience shot leaves a beam at least 0.3 m thick that is still there,
# fading, after 1 s and gone by 2.5 s; the beam is sent to clients too.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")

class Src extends "res://scripts/InputSource.gd":
	var aim := Vector2.ZERO
	var prim := false
	var sec := false
	func get_abs_aim():
		return aim
	func is_firing_primary() -> bool:
		return prim
	func is_firing_secondary() -> bool:
		return sec

func _fail(msg: String) -> void:
	push_error("[probe] patience_beam FAIL: " + msg)

func _beam(w: Node) -> MeshInstance3D:
	return w.get("_beam_mesh")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	get_tree().current_scene = arena  # VFX beams go under the current scene
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var me: CharacterBody3D = arena.get("player_mech")
	var enemy: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = true
			if m != me:
				m.process_mode = Node.PROCESS_MODE_DISABLED
	var fwd: Vector3 = -(me.get("torso") as Node3D).global_transform.basis.z
	fwd.y = 0.0
	enemy.global_position = me.global_position + fwd.normalized() * 20.0
	var src := Src.new()
	me.add_child(src)
	me.set_input_source(src)
	src.aim = Vector2((me.get("torso") as Node3D).rotation.y, 0.0)
	var scene: PackedScene = load("res://scenes/weapons/PatienceHeavy.tscn")
	var pw: Node = scene.instantiate()
	var slot := SlotDef.new()
	slot.slot_size = int(pw.get("slot_size"))
	pw.free()
	slot.position = Vector3(0, 2.0, 0)
	slot.weapon_scene = scene
	me.configure_weapons([slot])
	var w: Node = me.get_weapons()[0]
	for i in 5:
		await get_tree().physics_frame
	w.set("_charge_time", w.get("max_charge_time"))  # full charge takes 12 s; don't sit it out
	var t0 := Time.get_ticks_msec()
	var before := _beams(arena)
	src.prim = true
	var beam: MeshInstance3D = null
	t0 = Time.get_ticks_msec()
	while beam == null and Time.get_ticks_msec() - t0 < 1000:
		await get_tree().physics_frame
		for b in _beams(arena):
			if not before.has(b):
				beam = b
	src.prim = false
	if beam == null:
		_fail("no beam after a charged shot")
		get_tree().quit(1); return
	var thick: float = (beam.mesh as BoxMesh).size.x
	if thick < 0.3:
		_fail("beam %.2f m thick, want >= 0.3" % thick)
		get_tree().quit(1); return
	var fired := Time.get_ticks_msec()
	while Time.get_ticks_msec() - fired < 1000:
		await get_tree().process_frame
	if not is_instance_valid(beam):
		_fail("beam gone before 1 s")
		get_tree().quit(1); return
	var a: float = (beam.material_override as StandardMaterial3D).albedo_color.a if beam.material_override else 1.0
	if a >= 0.99:
		_fail("beam not fading at 1 s (alpha %.2f)" % a)
		get_tree().quit(1); return
	while Time.get_ticks_msec() - fired < 2500 and is_instance_valid(beam):
		await get_tree().process_frame
	if is_instance_valid(beam):
		_fail("beam still there at 2.5 s")
		get_tree().quit(1); return
	var src_code: String = (load("res://scripts/Patience.gd") as Script).source_code
	if not src_code.contains("VFX.tracer(") or not src_code.contains("true,"):
		_fail("Patience beam is not broadcast to clients")
		get_tree().quit(1); return
	print("[probe] patience_beam done (%.2f m thick, alpha %.2f at 1 s)" % [thick, a])
	get_tree().quit(0)

func _beams(arena: Node) -> Array:
	return arena.get_children().filter(func(n): return n is MeshInstance3D and n.mesh is BoxMesh and (n.mesh as BoxMesh).size.z > 5.0)
