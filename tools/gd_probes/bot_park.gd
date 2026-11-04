extends Node
# T230 probe (HUMAN_FOUND_ISSUES 2026-11-04: "two bots got stuck in the forest in sydney,
# and didn't move for a long time. They were both big"): two Everest bots (the slowest,
# 1.25 scale) dropped in Sydney's west park, everyone else frozen, head for the beacons
# and must get clear of the trees: each ends >= MIN_M from its drop point after RUN_S.
# Before T230 one pinned itself on a trunk's face for ~45 s (corner-cut waypoint, slow
# slide along the face): ~10 m in 40 s.

const RUN_S := 40.0
const MIN_M := 18.0  # Everest 0.75 m/s x 40 s = 30 m on a clear run
const Lobby := preload("res://scripts/Lobby.gd")

func _fail(msg: String) -> void:
	push_error("[probe] bot_park: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 3
	Game.loadout["map_def"] = load("res://resources/maps/City.tres")
	Game.setup_sp_match()
	var md: Resource = load("res://resources/mechs/Everest.tres")
	var rng := RandomNumberGenerator.new()
	rng.seed = 230
	for e in Game.mp_active_match["roster"]:
		e["squad"] = [{"mech": md.resource_path, "weapons": Lobby.bot_weapon_paths(md, rng)}]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	var region: NavigationRegion3D = arena.get("_nav_region")
	for i in 3000:
		if region != null and region.navigation_mesh.get_polygon_count() > 0 and not region.is_baking():
			break
		await get_tree().physics_frame
	var bots: Array = []
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = true
			if t == 0 and bots.size() < 2 and m != arena.get("player_mech"):
				bots.append(m)
			else:
				m.process_mode = Node.PROCESS_MODE_DISABLED
				m.global_position += Vector3(0, -200, 0)  # out of sight and out of the way
	var drops := [Vector3(-76, 0.5, 6), Vector3(-72, 0.5, 9)]
	for k in bots.size():
		(bots[k] as Node3D).global_position = drops[k]
	for i in int(RUN_S * 60.0):
		await get_tree().physics_frame
	var got: Array = []
	for k in bots.size():
		var d: float = Vector2((bots[k] as Node3D).global_position.x - drops[k].x, (bots[k] as Node3D).global_position.z - drops[k].z).length()
		got.append("%.1f" % d)
		if d < MIN_M:
			_fail("Everest bot %d only %.1f m from its park drop after %.0f s (at %s)" % [k, d, RUN_S, (bots[k] as Node3D).global_position])
	if bots.size() < 2:
		_fail("found %d team-0 bots" % bots.size())
	print("[probe] bot_park done (moved %s m in %.0f s)" % [", ".join(got), RUN_S])
	get_tree().quit(0)
