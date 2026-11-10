extends Node
# T307 probe (user 2026-11-05: "Remove the bullet entirely; the beam (totally instant shot)
# should exactly match the damage ... like the laser, but one shot"): a charged Patience shot
# at an enemy on the crosshair ray deals its full damage in the same tick the beam appears,
# the beam ends exactly at the ray hit, no Projectile is spawned, and nothing lands later.

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
	push_error("[probe] patience_hitscan FAIL: " + msg)

func _beam(w: Node) -> MeshInstance3D:
	return w.get("_beam_mesh")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.loadout["team_size"] = 1
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:  # B135: T365 squads are random -- a Kestrel's shield soaked the shot
		if int(e["peer_id"]) == 0:
			e["squad"] = range(5).map(func(_i): return {"mech": "res://resources/mechs/Pegasus.tres", "weapons": ["res://scenes/weapons/RifleLight.tscn", "res://scenes/weapons/RifleLight.tscn"]})
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
			m.invincible = m == me
			if m != me:
				m.set_physics_process(false)  # not PROCESS_MODE_DISABLED: that drops its body from physics
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
	for i in 10:
		await get_tree().physics_frame
	var w: Node = me.get_weapons()[0]
	var cam: Camera3D = me.get("camera")
	# park the enemy across the crosshair ray, 25 m out
	var hit := {}
	for dy in [1.5, 1.0, 2.0, 0.5, 2.5]:
		var p := cam.global_position - cam.global_transform.basis.z * 25.0
		enemy.global_position = p - Vector3(0, dy, 0)
		await get_tree().physics_frame
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_transform.basis.z * 300.0)
		q.exclude = me.get_exclude_rids()
		hit = cam.get_world_3d().direct_space_state.intersect_ray(q)
		if hit and hit.collider == enemy:
			break
	if not (hit and hit.collider == enemy):
		_fail("could not put the enemy on the crosshair ray")
		get_tree().quit(1); return
	w.set("_charge_time", w.get("max_charge_time"))
	var full: float = w.get("max_damage")
	var h0: float = enemy.get("health")
	var before := _beams(arena)
	var shots_before := arena.get_children().filter(func(n): return n is Projectile).size()
	src.prim = true
	var beam: MeshInstance3D = null
	var dealt_at_beam := -1.0
	for i in 30:
		await get_tree().physics_frame
		for b in _beams(arena):
			if not before.has(b) and beam == null:
				beam = b
				dealt_at_beam = h0 - float(enemy.get("health"))
		if beam != null:
			break
	src.prim = false
	if beam == null:
		_fail("no beam after a charged shot")
		get_tree().quit(1); return
	if absf(dealt_at_beam - full) > 1.0:
		_fail("when the beam appeared the enemy had taken %.1f, want the full %.1f at once" % [dealt_at_beam, full])
		get_tree().quit(1); return
	var end: Vector3 = beam.global_position - beam.global_transform.basis.z * (beam.mesh as BoxMesh).size.z * 0.5
	if end.distance_to(hit.position) > 0.2:
		_fail("beam ends at %s, the shot hit %s" % [end, hit.position])
		get_tree().quit(1); return
	for i in 30:
		await get_tree().physics_frame
	var shots := arena.get_children().filter(func(n): return n is Projectile).size()
	if shots > shots_before:
		_fail("a projectile was spawned (%d)" % (shots - shots_before))
		get_tree().quit(1); return
	if absf(h0 - float(enemy.get("health")) - full) > 1.0:
		_fail("enemy took %.1f in total, want exactly one %.1f hit" % [h0 - float(enemy.get("health")), full])
		get_tree().quit(1); return
	print("[probe] patience_hitscan done (%.1f dmg the tick it fired, beam end %.2f m from the hit)" % [dealt_at_beam, end.distance_to(hit.position)])
	get_tree().quit(0)

func _beams(arena: Node) -> Array:
	return arena.get_children().filter(func(n): return n is MeshInstance3D and n.mesh is BoxMesh and (n.mesh as BoxMesh).size.z > 5.0)
