extends Node
# T415 probe (HUMAN_FOUND, queued 2026-11-13: "On Badlands, a damage powerup spawned in the sky and
# floated there. No obvious reason." + "Spent shells float in the air sometimes."):
# - a casing's landing ray ignores mechs (one landing on a mech's head hung there after it left);
# - a casing that comes to rest above the floor (its spot changed under it) drops to the floor;
# - map powerups only spawn where a mech can walk to from its spawn (the navmesh also covers ruin
#   roofs and wall tops: Badlands' "powerup in the sky").

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")

func _fail(msg: String) -> void:
	push_error("[probe] float_fixes FAIL: " + msg)

func _floor_y(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 60, 0), at + Vector3(0, -60, 0))
	var ex: Array = []
	for m in get_tree().get_nodes_in_group("mechs"):
		ex.append_array(m.call("get_exclude_rids"))
	q.exclude = ex
	var hit: Dictionary = get_tree().current_scene.get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if hit else -1000.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Badlands.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 3:
		await get_tree().process_frame
	get_tree().current_scene = arena
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var me: Node3D = arena.get("player_mech")
	var slot := SlotDef.new()
	slot.slot_size = 0
	slot.position = Vector3(0, 2.0, 0)
	slot.weapon_scene = load("res://scenes/weapons/RifleLight.tscn")
	me.call("configure_weapons", [slot])
	var w: Node3D = me.call("get_weapons")[0]
	VFX.casing(w)
	var pool: Node = arena.find_child("Casings", false, false)
	if pool == null:
		_fail("no casing pool")
		get_tree().quit(0)
		return
	# 1. landing ray over a mech's head
	var enemy: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	enemy.invincible = true
	var stop: Node = load("res://scripts/InputSource.gd").new()
	add_child(stop)
	enemy.call("set_input_source", stop)
	for i in 5:
		await get_tree().physics_frame
	var above := enemy.global_position + Vector3(0, 4.0, 0)
	var floor_here := _floor_y(enemy.global_position)
	var land: float = pool.call("_landing_y", above, Vector3.ZERO, w)
	if land > floor_here + 0.3:
		_fail("a casing over a mech lands on it (y %.2f, floor %.2f)" % [land, floor_here])
	# 2. a casing resting in the air drops to the floor
	VFX.casing(w)
	var i: int = (int(pool.get("_next")) - 1 + int(pool.get("cap"))) % int(pool.get("cap"))
	var spot := me.global_position + Vector3(6, 0, 6)
	var fy := _floor_y(spot)
	var pos: PackedVector3Array = pool.get("_pos")
	pos[i] = Vector3(spot.x, fy + 15.0, spot.z)
	pool.set("_pos", pos)
	var gr: PackedFloat32Array = pool.get("_ground")
	gr[i] = fy + 15.0
	pool.set("_ground", gr)
	var vel: PackedVector3Array = pool.get("_vel")
	vel[i] = Vector3.ZERO
	pool.set("_vel", vel)
	var roll: PackedFloat32Array = pool.get("_roll")
	roll[i] = 0.01  # just finishing its roll, 15 m up
	pool.set("_roll", roll)
	var air: Array[int] = pool.get("_air")
	if not air.has(i):
		air.append(i)
	await get_tree().create_timer(3.0).timeout  # a 15 m fall takes ~1.5 s
	var y: float = (pool.get("_pos") as PackedVector3Array)[i].y
	if y > fy + 0.5:
		_fail("a casing left resting 15 m up stays there (y %.1f, floor %.1f)" % [y, fy])
	# 3. map powerups: every one reachable on foot from a spawn
	var navmap: RID = arena.get_world_3d().navigation_map
	var from: Vector3 = arena.call("spawn_points", 0)[0]
	var stray := 0
	arena.set("powerup_every_s", 100000.0)
	for k in 60:
		arena.call("spawn_map_powerup", "damage")
	for id in arena.get("_pickups"):
		var pk: Node3D = arena.get("_pickups")[id]
		if not is_instance_valid(pk) or pk.get("kind") != "damage":
			continue
		var path := NavigationServer3D.map_get_path(navmap, from, pk.global_position, true)
		if path.is_empty() or path[path.size() - 1].distance_to(pk.global_position) > 1.5:
			stray += 1
	if stray > 0:
		_fail("%d of 60 map powerups spawned where no mech can walk (Badlands)" % stray)
	print("[probe] float_fixes done")
	get_tree().quit(0)
