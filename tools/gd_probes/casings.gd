extends Node
# T263 probe (HUMAN_FOUND 2026-11-05 spent shells; user 2026-11-08: real casings, none for
# Patience, two bounces): one shot ejects one casing from a rifle, sniper and machine gun, one
# shell per shotgun blast (not per pellet), none from Patience, the laser or missiles; casings
# come to rest on the floor (two bounces, then they lie still); the pool never grows past its
# cap, adds no node per casing, and updating 300 airborne casings costs < 2 ms a frame.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")

func _fail(msg: String) -> void:
	push_error("[probe] casings FAIL: " + msg)
	get_tree().quit(1)

func _pool() -> Node:
	return get_tree().current_scene.find_child("Casings", false, false) if get_tree().current_scene != null else null

func _used() -> int:
	var p := _pool()
	return int(p.call("used")) if p != null else 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 1]
	Game.loadout["mode"] = "deathmatch"
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 3:
		await get_tree().process_frame
	get_tree().current_scene = arena
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	me.set("invincible", true)
	var want := {"RifleLight": 1, "SniperHeavy": 1, "MachineGunLight": 1, "ShotgunHeavy": 1,
		"PatienceHeavy": 0, "LaserCannonLight": 0, "MissileLauncherLight": 0}
	var got := {}
	for wname in want:
		var slot := SlotDef.new()
		var sc: PackedScene = load("res://scenes/weapons/%s.tscn" % wname)
		var probe_w: Node = sc.instantiate()
		slot.slot_size = int(probe_w.get("slot_size"))
		probe_w.free()
		slot.position = Vector3(0, 2.0, 0)
		slot.weapon_scene = sc
		me.configure_weapons([slot])
		await get_tree().physics_frame
		var w: Node = me.get_weapons()[0]
		var before := _used()
		w.call("_do_fire")
		got[wname] = _used() - before
	for wname in want:
		if got[wname] != want[wname]:
			_fail("%s ejected %d casing(s) per shot, want %d (all: %s)" % [wname, got[wname], want[wname], got])
			return
	# they come to rest on the floor
	var pool := _pool()
	await get_tree().create_timer(4.0).timeout  # game seconds (headless frames run faster)
	if int(pool.call("airborne")) != 0:
		_fail("%d casing(s) still moving 4 s after the last shot" % pool.call("airborne"))
		return
	var floor_y: float = (me as Node3D).global_position.y
	var mm: MultiMesh = (pool as MultiMeshInstance3D).multimesh
	var pos: PackedVector3Array = pool.get("_pos")  # headless (dummy renderer) can't read MultiMesh transforms back
	for i in mm.visible_instance_count:
		var y := pos[i].y
		if absf(y - floor_y) > 0.6:
			_fail("casing %d rests at y %.2f, the floor is %.2f" % [i, y, floor_y])
			return
	# the pool: a cap, no node per casing, cheap to update
	var nodes_before := get_tree().get_node_count()
	var cap: int = int(pool.get("cap"))
	var w2: Node = me.get_weapons()[0]
	for i in cap + 300:
		pool.call("eject", w2, false)
	if _used() != cap or mm.visible_instance_count != cap:
		_fail("pool holds %d after %d casings, cap %d" % [_used(), cap + 300, cap])
		return
	if get_tree().get_node_count() > nodes_before + 2:
		_fail("%d casings added %d nodes" % [cap + 300, get_tree().get_node_count() - nodes_before])
		return
	await get_tree().create_timer(4.0).timeout  # let them land
	for i in 300:  # a heavy firefight's worth in the air at once (5v5 machine guns ~150)
		pool.call("eject", w2, false)
	var t0 := Time.get_ticks_usec()
	pool.call("_process", 1.0 / 60.0)
	var us := Time.get_ticks_usec() - t0
	if us > 2000:
		_fail("updating %d airborne casings took %.2f ms" % [pool.call("airborne"), us / 1000.0])
		return
	print("[probe] casings done (%s; cap %d; %d airborne updated in %.2f ms)" % [got, cap, pool.call("airborne"), us / 1000.0])
	get_tree().quit(0)
