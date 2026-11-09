extends Node
# T209: one headless all-bot match for the balance tester (tools/balance_eval.py).
# Every roster slot is an Elite bot with a 5-mech squad of random (mech, weapon family)
# picks from the live catalogs (Lobby.ROSTER, Lobby.bot_weapon_paths), seeded, so many
# matches cover every mech and family in mixed company. Bots respawn into their squads
# as in a real match (T198). User args: seed=<n> size=<team size> max_s=<sim seconds>
# T285: mode=deathmatch (timer off: the natural length) map=<MapDef path> diff=<0..4, Elite>
# Prints one line per mech life, then the match:
#   [bal] {"mech", "wpn", "team", "dealt", "taken", "kills", "alive_s", "won"}
#   [bal-match] {"winner", "t", "map", "size"}
# T243: also every attacker (mech) -> victim (mech) pair: damage traded and kills, and each
# life's stall share (census samples alive but not moving):
#   [bal-pair] {"att", "vic", "dmg", "kills"}

const Lobby := preload("res://scripts/Lobby.gd")
const AI := preload("res://scripts/AIInputSource.gd")

var _arg := {"seed": "1", "size": "3", "max_s": "420", "mode": "beacons", "map": "", "diff": "4"}
var _born: Dictionary = {}  # mech -> tick first seen
var _gone: Dictionary = {}  # mech -> tick first seen dead
var _map_name := "?"
var _pairs: Dictionary = {}  # "att|vic" -> [damage, kills]
var _still: Dictionary = {}  # mech -> [census samples alive, of them not moving, last pos]
var _lock: Dictionary = {}  # T339: lock-weapon mech -> [samples a lock was possible, of them locked]

static func _mech_name(m: Node) -> String:
	if m == null or not is_instance_valid(m):
		return "?"
	var spawn: Resource = load(m.get_meta("spawn", [""])[0]) if m.has_meta("spawn") else null
	return String(spawn.display_name) if spawn != null else String(m.name)

func _on_damage(amount: float, source: Node, victim: Node) -> void:
	var att: Node = source
	while att != null and is_instance_valid(att) and not att.is_in_group("mechs") and att.get("owner_mech") == null:
		att = att.get_parent()
	if att != null and is_instance_valid(att) and att.get("owner_mech") != null:
		att = att.get("owner_mech")
	var key := "%s|%s" % [_mech_name(att), _mech_name(victim)]
	var p: Array = _pairs.get(key, [0.0, 0])
	p[0] += amount
	_pairs[key] = p

func _ready() -> void:
	for kv in OS.get_cmdline_user_args():
		var p: PackedStringArray = kv.split("=", true, 1)
		if p.size() == 2:
			_arg[p[0]] = p[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_arg["seed"])
	Game.loadout["team_size"] = int(_arg["size"])
	Game.settings["bot_difficulty"] = int(_arg["diff"])
	Game.loadout["mode"] = _arg["mode"]
	if _arg["map"] != "":
		Game.loadout["map_def"] = load(_arg["map"])
	Game.setup_sp_match()
	var md0 = Game.loadout.get("map_def")
	_map_name = String(md0.map_name) if md0 != null else "?"
	for e in Game.mp_active_match["roster"]:
		e["peer_id"] = 0  # the human slot plays as a bot too
		var squad: Array = []
		for _i in 5:
			var md: Resource = load(Lobby.ROSTER[rng.randi() % Lobby.ROSTER.size()])
			squad.append({"mech": md.resource_path, "weapons": Lobby.bot_weapon_paths(md, rng)})
		e["squad"] = squad
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var won := [-1]
	arena.match_node.match_ended.connect(func(w: int) -> void: won[0] = w)
	arena.match_node.time_limit = 0.0  # T285: measure how long a death match runs on its own
	var max_ticks := int(float(_arg["max_s"]) * 60.0)
	var t := 0
	while t < max_ticks and won[0] < 0:
		await get_tree().physics_frame
		t += 1
		if t % 30 == 0:
			_census(arena, t)
	_census(arena, t)
	var kills := {}
	for team in 2:
		for m in arena.get("_team_mechs")[team]:
			if is_instance_valid(m) and m.is_dead and is_instance_valid(m.last_attacker):
				kills[m.last_attacker] = int(kills.get(m.last_attacker, 0)) + 1
				var key := "%s|%s" % [_mech_name(m.last_attacker), _mech_name(m)]
				var p: Array = _pairs.get(key, [0.0, 0])
				p[1] += 1
				_pairs[key] = p
	for team in 2:
		for m in arena.get("_team_mechs")[team]:
			if not is_instance_valid(m) or not _born.has(m):
				continue
			var wpn := "?"
			for w in m.get_weapons():
				wpn = w.scene_file_path.get_file().get_basename().trim_suffix("Light").trim_suffix("Heavy")
			var spawn: Resource = load(m.get_meta("spawn", [""])[0]) if m.has_meta("spawn") else null
			print("[bal] " + JSON.stringify({"mech": spawn.display_name if spawn != null else String(m.name),
				"wpn": wpn, "team": team, "dealt": snappedf(m.damage_dealt_total, 0.1),
				"taken": snappedf(m.damage_taken_total, 0.1), "kills": int(kills.get(m, 0)),
				"alive_s": snappedf((int(_gone.get(m, t)) - int(_born[m])) / 60.0, 0.1), "won": won[0] == team,
				"stall": snappedf(float(_still[m][1]) / maxf(1.0, float(_still[m][0])), 0.01) if _still.has(m) else 0.0,
				"map": _map_name, "lock_opp_s": (_lock[m][0] * 0.5) if _lock.has(m) else 0.0,
				"lock_s": (_lock[m][1] * 0.5) if _lock.has(m) else 0.0}))
	for key in _pairs:
		var ab: PackedStringArray = String(key).split("|")
		print("[bal-pair] " + JSON.stringify({"att": ab[0], "vic": ab[1], "dmg": snappedf(_pairs[key][0], 0.1),
			"kills": _pairs[key][1], "map": _map_name}))
	print("[bal-match] " + JSON.stringify({"winner": won[0], "t": snappedf(t / 60.0, 0.1), "map": _map_name,
		"size": int(_arg["size"])}))
	get_tree().quit(0)

func _census(arena: Node, t: int) -> void:
	for team in 2:
		for m in arena.get("_team_mechs")[team]:
			if not is_instance_valid(m):
				continue
			if not _born.has(m) and not m.is_dead:
				_born[m] = t
				m.damage_event.connect(_on_damage.bind(m))
			if not m.is_dead and _born.has(m):  # stall share: alive, < 0.15 m since the last census
				var st: Array = _still.get(m, [0, 0, m.global_position])
				st[0] += 1
				if (m.global_position - (st[2] as Vector3)).length() < 0.15:
					st[1] += 1
				st[2] = m.global_position
				_still[m] = st
				# T339: a lock is possible when the bot's target is in sight and inside lock range
				if m.has_lock_weapon():
					var src: Node = m.get("_input_source")
					var tg = src.get("_target") if src != null else null
					if tg != null and is_instance_valid(tg) and src.get("_has_clear_shot") \
							and m.global_position.distance_to(tg.global_position) <= m.lock_weapon_range():
						var lk: Array = _lock.get(m, [0, 0])
						lk[0] += 1
						var lt = m.get("locked_target")
						if lt != null and is_instance_valid(lt):
							lk[1] += 1
						_lock[m] = lk
			if m.is_dead and _born.has(m) and not _gone.has(m):
				_gone[m] = t
