extends Node
# T299 probe (HUMAN_FOUND 2026-11-05 late: "Laser and arc should not go through targets, but
# stop when hitting a mech"): an enemy standing between the gun and the aim point -- off the
# camera's crosshair ray (laser) / short of the locked target (arc) -- ends the beam where it
# is hit, and the laser's damage lands on it.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")

func _fail(msg: String) -> void:
	push_error("[probe] beam_stops FAIL: " + msg)
	get_tree().quit(1)

func _arm(me: Node, path: String) -> Node:
	var slot := SlotDef.new()
	slot.slot_size = 0
	slot.position = Vector3(0, 2.0, 0)
	slot.weapon_scene = load(path)
	me.configure_weapons([slot])
	return me.get_weapons()[0]

# put `m` so its centre mass sits at `p`
func _place(m: Node3D, p: Vector3) -> void:
	m.global_position = p - (m.call("center_mass") - m.global_position)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 2]
	Game.loadout["mode"] = "beacons"
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
	var foes: Array = arena.get("_team_mechs")[1 - int(me.get("team"))]
	if foes.size() < 2:
		_fail("need two enemies, got %d" % foes.size())
		return
	var target: Node3D = foes[0]
	var blocker: Node3D = foes[1]
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			if m != me:
				m.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE  # frozen but still solid
				m.process_mode = Node.PROCESS_MODE_DISABLED
	me.invincible = true
	var fwd: Vector3 = -(me.get("torso") as Node3D).global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	target.global_position = me.global_position + fwd * 60.0 + Vector3(0, 0, 30)  # out of the way

	# laser: the crosshair ray (camera) passes over the blocker, the muzzle line goes through it
	var w := _arm(me, "res://scenes/weapons/LaserCannonLight.tscn")
	await get_tree().physics_frame
	var muzzle: Vector3 = w.global_position
	var aim_p: Vector3 = muzzle + fwd * 40.0
	var mid: Vector3 = muzzle + fwd * 6.0
	_place(blocker, mid)
	for i in 2:
		await get_tree().physics_frame
	var cam: Camera3D = me.get("camera")
	cam.look_at(aim_p)
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, aim_p)
	q.exclude = me.get_exclude_rids()
	var cam_hit := me.get_world_3d().direct_space_state.intersect_ray(q)
	if cam_hit and cam_hit.collider == blocker:
		_fail("setup: the crosshair ray itself hits the blocker")
		return
	var hp0: float = blocker.get("health")
	w.call("_do_fire")
	var beam_len: float = (w.get("_beam") as Node3D).scale.z
	var to_blocker: float = muzzle.distance_to(mid)
	if beam_len > to_blocker + 1.0:
		_fail("the laser beam runs %.1f m, through the mech %.1f m away" % [beam_len, to_blocker])
		return
	if float(blocker.get("health")) >= hp0:
		_fail("the laser stopped at the mech but didn't hurt it")
		return

	# arc: locked on the target, another enemy in between
	w = _arm(me, "res://scenes/weapons/ArcWeaponLight.tscn")
	await get_tree().physics_frame
	muzzle = w.global_position
	var rng: float = minf(float(w.get("range")) - 2.0, 20.0)
	_place(target, muzzle + fwd * rng)
	_place(blocker, muzzle + fwd * rng * 0.5)
	for i in 2:
		await get_tree().physics_frame
	me.set("locked_target", target)
	w.call("_do_fire")
	var arc_len: float = w.get("_beam_len")
	if arc_len > rng * 0.5 + 1.0:
		_fail("the arc runs %.1f m to its target through the mech %.1f m away" % [arc_len, rng * 0.5])
		return
	print("[probe] beam_stops done (laser %.1f m / blocker %.1f m, arc %.1f m / %.1f m)" % [beam_len, to_blocker, arc_len, rng * 0.5])
	get_tree().quit(0)
