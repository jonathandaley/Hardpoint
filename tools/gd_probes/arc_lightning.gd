extends Node
# T259 probe (HUMAN_FOUND_ISSUES 2026-11-05: "Arc weapon animation: lightning arc
# (continuous)"): while the arc fires at a locked target its beam is a jagged bolt -- kinked
# sideways, pinned at the muzzle, reaching the target -- that re-shapes frame to frame, and
# keeps its colour through a shield flash (B112).

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
	push_error("[probe] arc_lightning FAIL: " + msg)

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
	var shapes: Array = []
	for i in 60:
		me.set("locked_target", enemy)
		src.prim = true
		await get_tree().physics_frame
		await get_tree().process_frame
		var pts = w.get("_bolt_points")
		if _beam(w).visible and pts is PackedVector3Array and pts.size() > 2:
			shapes.append(pts.duplicate())
	# B112: Mech's shield flash sets then nulls material_override on every torso mesh; the
	# bolt's colour must survive that, so it lives on the mesh surface.
	_beam(w).material_override = null
	var smat = _beam(w).mesh.surface_get_material(0) if _beam(w).mesh.get_surface_count() > 0 else null
	src.prim = false
	if not (smat is StandardMaterial3D) or (smat as StandardMaterial3D).albedo_color.g < 0.9:
		_fail("bolt colour is not on its mesh surface (a shield flash greys it): %s" % smat)
		get_tree().quit(1); return
	if shapes.size() < 5:
		_fail("no bolt points while firing (%d frames)" % shapes.size())
		get_tree().quit(1); return
	var changed := 0
	var kink := 0.0
	for k in shapes.size():
		var p: PackedVector3Array = shapes[k]
		if p[0].length() > 0.05 or p[p.size() - 1].z > -15.0:
			_fail("bolt not muzzle-to-target: starts %s ends %s" % [p[0], p[p.size() - 1]])
			get_tree().quit(1); return
		for v in p:
			kink = maxf(kink, Vector2(v.x, v.y).length())
		if k > 0 and p != shapes[k - 1]:
			changed += 1
	if kink < 0.05:
		_fail("bolt is straight (widest kink %.3f m)" % kink)
		get_tree().quit(1); return
	if changed < shapes.size() / 2:
		_fail("bolt re-shaped on only %d of %d frames" % [changed, shapes.size()])
		get_tree().quit(1); return
	print("[probe] arc_lightning done (%d frames, kink %.2f m)" % [shapes.size(), kink])
	get_tree().quit(0)
