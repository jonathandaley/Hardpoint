extends Node
# T172: one headless bot-vs-bot SP match. Every mech on both teams is a bot.
# User args (after `--`): a=<diff> b=<diff> legacy=<a|b|none> size=<n> mech=<Name>
#   size_a=/size_b= (uneven teams) swap=1 (side A plays team 1) max_s=<sim seconds> wa=/wb=<FAMILY> (RIFLE, ROCKET..)
# Side A always runs the live AI at difficulty a. Side B runs the live AI at b, or
# tools/bot_eval/LegacyAI.gd (the T169 AI) when legacy=b; legacy=a makes side A legacy.
# Prints: [eval] winner=<A|B|draw> t=<s> alive=<A>,<B> dealt=<A>,<B> score=<A>,<B>
# Run many via tools/bot_eval.py (fixed-fps, parallel, tallies).

const Lobby := preload("res://scripts/Lobby.gd")
const AI := preload("res://scripts/AIInputSource.gd")
const LEGACY := preload("res://tools/bot_eval/LegacyAI.gd")

var _arg := {"a": "4", "b": "4", "legacy": "b", "size": "3", "mech": "Hippogriff", "swap": "0", "max_s": "600"}

func _ready() -> void:
	for kv in OS.get_cmdline_user_args():
		var p: PackedStringArray = kv.split("=", true, 1)
		if p.size() == 2:
			_arg[p[0]] = p[1]
	var md: Resource = load("res://resources/mechs/%s.tres" % _arg["mech"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var size_a := int(_arg.get("size_a", _arg["size"]))
	var size_b := int(_arg.get("size_b", _arg["size"]))
	Game.loadout["team_size"] = maxi(size_a, size_b)
	# T184: SP roster with every slot a bot (the human slot too) running <mech>, one family each
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:
		e["peer_id"] = 0
		e["squad"] = [{"mech": md.resource_path, "weapons": Lobby.bot_weapon_paths(md, rng)}]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var side_a_team := 1 if _arg["swap"] == "1" else 0
	var legacy_side: String = _arg["legacy"]
	# LegacyAI reads the global setting; the live AI takes a per-bot override.
	Game.settings["bot_difficulty"] = int(_arg["a"] if legacy_side == "a" else _arg["b"])
	for p in arena.get("_players"):
		var mech: Node = p.get("pawn")
		if mech == null:
			continue
		var side_a: bool = p.get("team") == side_a_team
		var legacy: bool = (legacy_side == "a") == side_a and legacy_side != "none"
		if mech.get_node_or_null("NavAgent") == null:  # the player mech never got one
			var nav := NavigationAgent3D.new()
			nav.name = "NavAgent"
			nav.path_desired_distance = 1.5
			nav.target_desired_distance = 2.5
			mech.add_child(nav)
		var fam: String = _arg.get("wa" if side_a else "wb", "")
		if fam != "":  # force one weapon family on this side (e.g. wa=ROCKET)
			var torso: Node = mech.get("torso")
			for c in torso.get_children():
				if c.name.begins_with("Hardpoint"):
					torso.remove_child(c)
					c.queue_free()
			var paths: Array = md.weapon_slots.map(func(sl) -> String:
				for w in Lobby.WEAPON_CATALOG:
					if w["name"].get_slice(" ", 0) == fam and w["slot_size"] == sl.slot_size:
						return w["path"]
				return "")
			mech.configure_weapons(arena._slots_with_weapon_paths(md.weapon_slots, paths))
		var old: Node = p.get("input_source")
		var ai := Node.new()
		ai.set_script(LEGACY if legacy else AI)
		# keep Arena's id (1 + team*100 + slot -> role); the human slot is slot 0
		ai.bot_id = old.bot_id if old != null and "bot_id" in old else 1 + int(p.get("team")) * 100
		if not legacy:
			ai.difficulty = int(_arg["a"] if side_a else _arg["b"])
		p.add_child(ai)
		p.set("input_source", ai)
		p.call("possess", mech)
		if old != null:
			old.queue_free()

	# uneven teams: the smaller side loses its last slots at t=0
	for team in 2:
		var keep: int = size_a if team == side_a_team else size_b
		var tm: Array = arena.get("_team_mechs")[team]
		for i in range(keep, tm.size()):
			tm[i].take_damage(float(tm[i].health) + 1000.0)
	var won := [-1]
	arena.match_node.match_ended.connect(func(w: int) -> void: won[0] = w)
	var max_ticks := int(float(_arg["max_s"]) * 60.0)
	var t := 0
	while t < max_ticks and won[0] < 0:
		await get_tree().physics_frame
		t += 1
		if t == 240 and arena.get("_nav_region") != null:
			var nm: NavigationMesh = arena.get("_nav_region").navigation_mesh
			print("[eval] navmesh polys=%d" % nm.get_polygon_count())
			if _arg.get("navpaths", "0") == "1":
				var map: RID = arena.get_world_3d().navigation_map
				for team in 2:
					var from: Vector3 = arena.get("_team_mechs")[team][0].global_position
					for b in get_tree().get_nodes_in_group("beacons"):
						var path := NavigationServer3D.map_get_path(map, from, b.global_position, true)
						var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3.INF
						print("[nav] team%d -> %s pts=%d end=(%.1f,%.1f,%.1f) beacon=(%.1f,%.1f,%.1f) miss=%.1f" % [team, b.name, path.size(), end.x, end.y, end.z,
							b.global_position.x, b.global_position.y, b.global_position.z, end.distance_to(b.global_position)])
		if _arg.get("trace", "0") == "1" and t % 300 == 0:
			_trace(arena, t)
		if _arg.has("watch") and t % 15 == 0 and t >= int(_arg.get("w0", "0")) * 60 and t <= int(_arg.get("w1", "9999")) * 60:
			var wm: Node = arena.find_child(_arg["watch"], true, false)
			if wm != null and wm.get_node_or_null("NavAgent") != null:
				var na: NavigationAgent3D = wm.get_node("NavAgent")
				print("[watch] t=%.2f pos=(%.1f,%.1f,%.1f) floor=%s v=(%.1f,%.1f,%.1f) navtgt=(%.0f,%.0f) next=(%.1f,%.1f,%.1f) fin=%s move=%s esc=%.2f" % [
					t / 60.0, wm.global_position.x, wm.global_position.y, wm.global_position.z, wm.is_on_floor(),
					wm.velocity.x, wm.velocity.y, wm.velocity.z, na.target_position.x, na.target_position.z,
					na.get_next_path_position().x, na.get_next_path_position().y, na.get_next_path_position().z, na.is_navigation_finished(),
					wm.get("_input_source").get("_move_dir"), wm.get("_input_source").get("_escape_timer")])
				var ai: Node = wm.get("_input_source")
				var tg = ai.get("_target")
				if tg != null and is_instance_valid(tg):
					var q := PhysicsRayQueryParameters3D.create(wm.global_position + Vector3(0, 2.0, 0), tg.global_position + Vector3(0, 1.5, 0))
					q.exclude = wm.get_exclude_rids()
					var hit: Dictionary = wm.get_world_3d().direct_space_state.intersect_ray(q)
					if not hit.is_empty():
						var col: Node = hit.collider
						print("[los] hit=%s (%s) parent=%s at=(%.1f,%.1f,%.1f) me_y=%.1f tg_y=%.1f" % [col.name, col.get_class(), col.get_parent().name, hit.position.x, hit.position.y, hit.position.z, wm.global_position.y, tg.global_position.y])
				if ai.has_method("_shot_worth_taking") and tg != null and is_instance_valid(tg):
					var w: Node = ai._primary(wm)
					var ap: Vector3 = ai._aim_point(wm, w, 1.0)
					var cam: Camera3D = wm.camera
					var to_p := ap - cam.global_position
					print("[fire] wpn=%s range=%.0f dist=%.0f los=%s react=%.2f burst=%s worth=%s miss=%.2f firing=%s ammo=%d reloading=%s" % [
						w.scene_file_path.get_file(), ai._fire_range(wm), wm.global_position.distance_to(tg.global_position), ai._has_clear_shot,
						ai._react_timer, ai._in_burst, ai._shot_worth_taking(wm, w, ap),
						sin((-cam.global_transform.basis.z).angle_to(to_p)) * to_p.length(), ai._firing, w.ammo, w.is_reloading()])
	var alive := [0, 0]
	var dealt := [0.0, 0.0]
	for team in 2:
		for m in arena.get("_team_mechs")[team]:
			if is_instance_valid(m):
				dealt[team] += m.damage_dealt_total
				if not m.is_dead:
					alive[team] += 1
	var scores: Array = arena.match_node.scores
	var ta := side_a_team
	var tb := 1 - side_a_team
	var winner: String = "A" if won[0] == ta else "B" if won[0] == tb else "draw"
	var fams: Array = []
	for team in [ta, tb]:
		var names := {}
		for m in arena.get("_team_mechs")[team]:
			if is_instance_valid(m):
				for w in m.get_weapons():
					names[w.scene_file_path.get_file().get_basename()] = true
		fams.append("+".join(names.keys()))
	print("[eval] winner=%s t=%.0f alive=%d,%d dealt=%.0f,%.0f score=%d,%d wpn=%s|%s" % [
		winner, t / 60.0, alive[ta], alive[tb], dealt[ta], dealt[tb], scores[ta], scores[tb], fams[0], fams[1]])
	get_tree().quit(0)

func _trace(arena: Node, t: int) -> void:
	for p in arena.get("_players"):
		var m: Node3D = p.get("pawn")
		var ai: Node = p.get("input_source")
		if m == null or ai == null:
			continue
		var tg = ai.get("_target")
		var tgs: String = "-" if tg == null or not is_instance_valid(tg) else "%s@%.0f" % [tg.name, m.global_position.distance_to(tg.global_position)]
		var bc = ai.get("_claimed_beacon")
		var bs: String = "-" if bc == null or not is_instance_valid(bc) else "%s@%.0f" % [bc.name, m.global_position.distance_to(bc.global_position)]
		print("[trace] t=%d %s %s hp=%.0f pos=(%.0f,%.0f) tgt=%s fire=%s los=%s move=%s bcn=%s v=%.1f" % [
			t / 60, m.name, ai.get("role"), m.health, m.global_position.x, m.global_position.z, tgs,
			ai.get("_firing"), ai.get("_has_clear_shot"), ai.get("_move_dir"), bs, Vector2(m.velocity.x, m.velocity.z).length()])
