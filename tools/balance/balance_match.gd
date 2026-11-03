extends Node
# T209: one headless all-bot match for the balance tester (tools/balance_eval.py).
# Every roster slot is an Elite bot with a 5-mech squad of random (mech, weapon family)
# picks from the live catalogs (Lobby.ROSTER, Lobby.bot_weapon_paths), seeded, so many
# matches cover every mech and family in mixed company. Bots respawn into their squads
# as in a real match (T198). User args: seed=<n> size=<team size> max_s=<sim seconds>
# Prints one line per mech life, then the match:
#   [bal] {"mech", "wpn", "team", "dealt", "taken", "kills", "alive_s", "won"}
#   [bal-match] {"winner", "t"}

const Lobby := preload("res://scripts/Lobby.gd")
const AI := preload("res://scripts/AIInputSource.gd")

var _arg := {"seed": "1", "size": "3", "max_s": "420"}
var _born: Dictionary = {}  # mech -> tick first seen
var _gone: Dictionary = {}  # mech -> tick first seen dead

func _ready() -> void:
	for kv in OS.get_cmdline_user_args():
		var p: PackedStringArray = kv.split("=", true, 1)
		if p.size() == 2:
			_arg[p[0]] = p[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_arg["seed"])
	Game.loadout["team_size"] = int(_arg["size"])
	Game.settings["bot_difficulty"] = 4
	Game.setup_sp_match()
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
				"alive_s": snappedf((int(_gone.get(m, t)) - int(_born[m])) / 60.0, 0.1), "won": won[0] == team}))
	print("[bal-match] " + JSON.stringify({"winner": won[0], "t": snappedf(t / 60.0, 0.1)}))
	get_tree().quit(0)

func _census(arena: Node, t: int) -> void:
	for team in 2:
		for m in arena.get("_team_mechs")[team]:
			if not is_instance_valid(m):
				continue
			if not _born.has(m) and not m.is_dead:
				_born[m] = t
			if m.is_dead and _born.has(m) and not _gone.has(m):
				_gone[m] = t
