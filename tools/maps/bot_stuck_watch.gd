extends Node
# T416 investigation tool (HUMAN_FOUND: Swamp "impassible choke points that all the bots, including
# elites, were stuck on"): a bots-only match on a map; every second each bot's position; prints the
# spots where a live bot moved < 1.5 m over 8 s (stuck), with how often. Not a suite probe (minutes).
#   ~/bin/godot --headless --path . res://tools/maps/bot_stuck_watch.tscn -- <Map> [seconds] [difficulty]
var _traced := false

## One stalled bot, tick by tick for a second: where it is, its velocity, its move input, its aim yaw.
func _trace(m: Node3D) -> void:
	var ai: Node = m.get("_input_source")
	for k in 60:
		await get_tree().physics_frame
		if not is_instance_valid(m):
			return
		if k % 3 == 0:
			print("[trace] %d pos %s vel %s move %s yaw %.2f strafe %s dist %.1f" % [k, m.global_position.snapped(Vector3.ONE * 0.01),
				(m as CharacterBody3D).velocity.snapped(Vector3.ONE * 0.01), ai.get("_move_dir") if ai else "?",
				(m.get("torso") as Node3D).global_rotation.y, ai.get("_strafe_sign") if ai else "?",
				m.global_position.distance_to(ai.get("_target").global_position) if ai and is_instance_valid(ai.get("_target")) else -1.0])

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var secs := int(args[1]) if args.size() > 1 else 120
	Game.settings["bot_difficulty"] = int(args[2]) if args.size() > 2 else 3
	Game.loadout["map_def"] = load("res://resources/maps/%s.tres" % (args[0] if args.size() > 0 else "Swamp"))
	Game.loadout["team_size"] = 5
	Game.loadout["mode"] = "beacons"
	Game.mp_active_match["roster"] = []
	Game.setup_sp_match()
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	var me: Node = arena.get("player_mech")
	me.set("invincible", true)
	me.global_position += Vector3(0, 300, 0)  # the human sits it out, far above
	var hist := {}  # mech -> [positions per second]
	var spots := {}
	for s in secs:
		await get_tree().create_timer(1.0, false).timeout
		for m in get_tree().get_nodes_in_group("mechs"):
			if m == me or m.get("is_dead") or not is_instance_valid(m):
				continue
			var h: Array = hist.get(m, [])
			h.append((m as Node3D).global_position)
			hist[m] = h
			if h.size() >= 8:
				var walked := 0.0  # total path, not net: a strafing bot isn't stuck
				for k in range(h.size() - 7, h.size()):
					walked += (h[k] as Vector3).distance_to(h[k - 1])
				if walked < 1.5:
					var key := "%d,%d" % [roundi(h[-1].x / 4.0) * 4, roundi(h[-1].z / 4.0) * 4]
					spots[key] = int(spots.get(key, 0)) + 1
					if int(spots[key]) == 1 and not _traced:
						_traced = true
						_trace(m)
					if int(spots[key]) == 1:
						var ai: Node = m.get("_input_source")
						var cb := m as CharacterBody3D
						var hits: Array = []
						for c in cb.get_slide_collision_count():
							var col := cb.get_slide_collision(c)
							hits.append("%s n%s" % [(col.get_collider() as Node).name if col.get_collider() else "?", col.get_normal().snapped(Vector3.ONE * 0.01)])
						print("[stuck_watch] %s stuck at %s: move %s, vel %s, floor %s, step %.2f, hits %s, terrain %.2f" % [m.name, cb.global_position.snapped(Vector3.ONE * 0.01),
							ai.get("_move_dir") if ai else "?", cb.velocity.snapped(Vector3.ONE * 0.01), cb.is_on_floor(), float(m.get("_step_up_remaining")), hits, float(m.get("terrain_speed"))])
	var rows: Array = []
	for k in spots:
		rows.append([spots[k], k])
	rows.sort()
	rows.reverse()
	print("[stuck_watch] %s %d s: %d stuck spots; top: %s" % [args[0] if args.size() > 0 else "Swamp", secs, rows.size(), rows.slice(0, 12)])
	get_tree().quit(0)
