extends Node
# T352 probe (HUMAN_FOUND 2026-11-08: "bots go for powerups but can't pick up coins"): a hurt Hard
# bot with nobody to fight walks to a repair kit 12 m off on the navmesh and takes it; a coin
# lying under a bot stays where it is.

func _fail(msg: String) -> void:
	push_error("[probe] bot_pickups FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 2
	Game.loadout["mode"] = "deathmatch"
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	arena.set("powerup_every_s", 1000.0)  # only our kit and coin
	var nr: NavigationRegion3D = arena.get("_nav_region")
	for i in 600:
		if nr != null and nr.navigation_mesh.get_polygon_count() > 0 and i > 5:
			break
		await get_tree().physics_frame
	var me: Node3D = arena.get("player_mech")
	var team: int = int(me.get("team"))
	var ally: Node3D = arena.get("_team_mechs")[team][1]  # a bot on our team: no enemy near it
	for foe in arena.get("_team_mechs")[1 - team]:  # parked where they spawned (the far side)
		foe.set("invincible", true)
		foe.set_physics_process(false)
	ally.get("_input_source").set("difficulty", 3)
	var nav_map: RID = arena.get_world_3d().navigation_map
	var kit_at: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, ally.global_position + Vector3(12, 0, 0))
	arena.call("_rpc_spawn_pickup", 7001, "repair", kit_at, 0)
	ally.set("health", float(ally.get("max_health")) * 0.4)
	var h0: float = ally.get("health")
	var took := false
	for i in 60 * 10:
		await get_tree().physics_frame
		if float(ally.get("health")) > h0 + 1.0:
			took = true
			break
	if not took:
		_fail("a hurt Hard bot didn't fetch a repair kit %.0f m away in 10 s (ended %.1f m off)" % [
			12.0, (ally.global_position - kit_at).length()])
		return
	# a coin under a bot stays
	arena.call("_rpc_spawn_pickup", 7002, "coin", ally.global_position, 4)
	for i in 30:
		await get_tree().physics_frame
	if not (arena.get("_pickups") as Dictionary).has(7002):
		_fail("a bot picked up a coin")
		return
	print("[probe] bot_pickups done")
	get_tree().quit(0)
