extends Node
# T273 probe (HUMAN_FOUND 2026-11-05: "Arc weapon should be unable to fire until it's
# within range"): holding the trigger on a locked enemy beyond the arc's range spends
# nothing -- no cooldown, no ammo, no beam; bring it within range and it fires.

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
	push_error("[probe] arc_range FAIL: " + msg)

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
	var slot := SlotDef.new()
	slot.slot_size = 0
	slot.position = Vector3(0, 2.0, 0)
	slot.weapon_scene = load("res://scenes/weapons/ArcWeaponLight.tscn")
	me.configure_weapons([slot])
	await get_tree().physics_frame
	var w: Node = me.get_weapons()[0]
	var rng: float = w.get("range")
	enemy.global_position = me.global_position + fwd.normalized() * (rng + 15.0)
	var fired_out := false
	var ammo0 = w.get("ammo")
	for i in 60:
		me.set("locked_target", enemy)
		src.prim = true
		await get_tree().physics_frame
		fired_out = fired_out or float(w.get("_cooldown")) > 0.0 or _beam(w).visible or w.get("ammo") != ammo0
	src.prim = false
	if fired_out:
		_fail("fired at a target %.0f m off (range %.0f): cooldown / ammo / beam spent" % [rng + 15.0, rng])
		get_tree().quit(1); return
	enemy.global_position = me.global_position + fwd.normalized() * (rng * 0.5)
	var fired_in := false
	for i in 60:
		me.set("locked_target", enemy)
		src.prim = true
		await get_tree().physics_frame
		fired_in = fired_in or _beam(w).visible
	src.prim = false
	if not fired_in:
		_fail("never fired at a locked target inside its range")
		get_tree().quit(1); return
	print("[probe] arc_range done (range %.0f m)" % rng)
	get_tree().quit(0)
