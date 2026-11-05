extends Node
# T247 probe (HUMAN_FOUND_ISSUES 2026-11-05: "Arc weapon beam visible even when not firing"):
# the arc beam shows while firing at a locked target and is gone within GONE_S after the
# trigger comes up -- by primary (LMB) and by secondary (RMB, "fire selected weapon"), whose
# release never reached on_fire_release, so the beam stayed on.

const GONE_S := 0.5
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
	push_error("[probe] arc_beam: " + msg)

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
	for case in ["prim", "sec"]:
		var shown := false
		for i in 60:  # 1 s holding the trigger on a held lock
			me.set("locked_target", enemy)
			src.set(case, true)
			await get_tree().physics_frame
			shown = shown or _beam(w).visible
		if not shown:
			_fail("%s: the beam never showed while firing at a locked target" % case)
		src.set(case, false)
		var gone_at := -1.0
		for i in int(GONE_S * 60.0) + 1:
			me.set("locked_target", enemy)
			await get_tree().physics_frame
			if not _beam(w).visible:
				gone_at = i / 60.0
				break
		if gone_at < 0.0:
			_fail("%s: the beam still shows %.1f s after the trigger came up" % [case, GONE_S])
		for i in 30:
			await get_tree().physics_frame
	print("[probe] arc_beam done")
	get_tree().quit(0)
