extends Node
# Singleton -- cross-match persistent state.
#
# Data ownership:
#   profile  -- server-owned fields (wins/losses/pilot_name). Keep clean for future sync.
#   loadout  -- server-owned fields (chosen mech, weapon config). Same rule.
#   settings -- local-only fields (mouse sensitivity). Never sent to server.
#
# Also hosts bot-coordination (formerly AIDirector autoload) to stay within the
# three-autoload V5 limit.

const _SAVE_PATH     := "user://profile.cfg"
const _SETTINGS_PATH := "user://settings.cfg"

# ELO constants
const _ELO_K := 32
const _BOT_ELO_BY_DIFFICULTY: Array = [800, 1000, 1200, 1400, 1600]

# Progression tree constants
# Each tier costs _PROG_COIN_COST[current_tier] coins and requires _PROG_LEVEL_REQ[current_tier] level.
const _PROG_LEVEL_REQ: Array = [1, 4, 8, 12]   # level req per tier unlock
const _PROG_COIN_COST: Array = [100, 250, 500, 1000]
const _PROG_NODES: Array = ["speed", "reload", "damage", "health", "ability"]

# Cumulative XP required to reach each level (index 0 = XP to reach level 2, etc.)
# Formula: _LEVEL_THRESHOLDS[n-1] = sum of (i*100) for i in 1..n
const _LEVEL_THRESHOLDS: Array = [
	100, 300, 600, 1000, 1500, 2100, 2800, 3600, 4500, 5500,
	6600, 7800, 9100, 10500, 12000, 13600, 15300, 17100, 19000,
]  # 19 entries for levels 2-20

var profile: Dictionary = {
	"pilot_name": "Pilot",
	"wins": 0,
	"losses": 0,
	"elo": 1000,
	"xp": 0,
	"level": 1,
	"coins": 0,
	"progression": {"speed": 0, "reload": 0, "damage": 0, "health": 0, "ability": 0},
}

# Loadout is set in Hangar and consumed by Arena.
# mech_def is a MechDef resource; null until Hangar initialises it.
var loadout: Dictionary = {
	"mech_def": null,
	"bot_def": preload("res://resources/mechs/Hippogriff.tres"),
	"weapon_overrides": [],        # Array[PackedScene|null], parallel to mech_def.weapon_slots
	"mech_weapon_choices": {},     # {mech_resource_path: [weapon_scene_path, ...]}
	"team_size": 1,                # mechs per team (1 = 1v1, 5 = 5v5)
	"squad": [],                   # Array of 5 mech resource paths (slot 0 = player mech)
	"map_def": null,               # MapDef resource; null = Math Temple (default)
}

var settings: Dictionary = {
	"mouse_sensitivity": 0.003,
	"bot_difficulty": 1,  # 0=Easy  1=Normal  2=Medium  3=Hard  4=Elite
	"master_volume": 0.5,
}

func _ready() -> void:
	_load_profile()
	_load_settings()
	_load_loadout()

func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return
	profile["pilot_name"]  = cfg.get_value("profile", "pilot_name",  profile["pilot_name"])
	profile["wins"]        = cfg.get_value("profile", "wins",        0)
	profile["losses"]      = cfg.get_value("profile", "losses",      0)
	profile["elo"]         = cfg.get_value("profile", "elo",         1000)
	profile["xp"]          = cfg.get_value("profile", "xp",         0)
	profile["level"]       = cfg.get_value("profile", "level",       1)
	profile["coins"]       = cfg.get_value("profile", "coins",       0)
	profile["progression"] = cfg.get_value("profile", "progression",
		{"speed": 0, "reload": 0, "damage": 0, "health": 0, "ability": 0})

func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)
	cfg.set_value("profile", "pilot_name",  profile.get("pilot_name",  "Pilot"))
	cfg.set_value("profile", "wins",        profile.get("wins",        0))
	cfg.set_value("profile", "losses",      profile.get("losses",      0))
	cfg.set_value("profile", "elo",         profile.get("elo",         1000))
	cfg.set_value("profile", "xp",          profile.get("xp",         0))
	cfg.set_value("profile", "level",       profile.get("level",       1))
	cfg.set_value("profile", "coins",       profile.get("coins",       0))
	cfg.set_value("profile", "progression", profile.get("progression", {}))
	cfg.save(_SAVE_PATH)

# ---- ELO / XP / match helpers ----

func get_bot_elo() -> int:
	var diff: int = clampi(settings.get("bot_difficulty", 1), 0, 4)
	return _BOT_ELO_BY_DIFFICULTY[diff]

## Call once per match to update ELO, XP, coins, and level.
func update_after_match(won: bool) -> void:
	var my_elo: int  = profile.get("elo", 1000)
	var opp_elo: int = get_bot_elo()

	# ELO update (standard formula)
	var expected: float = 1.0 / (1.0 + pow(10.0, float(opp_elo - my_elo) / 400.0))
	var result_val: float = 1.0 if won else 0.0
	profile["elo"] = maxi(100, my_elo + roundi(float(_ELO_K) * (result_val - expected)))

	# XP (more XP for beating tougher opponents)
	var xp_gain: int
	if won:
		xp_gain = clampi(roundi(50.0 * float(opp_elo) / float(maxi(1, my_elo))), 25, 200)
	else:
		xp_gain = clampi(roundi(15.0 * float(opp_elo) / float(maxi(1, my_elo))), 5, 50)
	profile["xp"] = profile.get("xp", 0) + xp_gain

	# Level-up check
	_check_level_up()

	# Coins
	profile["coins"] = profile.get("coins", 0) + (75 if won else 20)

func _check_level_up() -> void:
	var cur_level: int = profile.get("level", 1)
	var cur_xp: int    = profile.get("xp", 0)
	# cur_level - 1 is the index into _LEVEL_THRESHOLDS (0-based)
	while cur_level - 1 < _LEVEL_THRESHOLDS.size() and cur_xp >= _LEVEL_THRESHOLDS[cur_level - 1]:
		cur_level += 1
	profile["level"] = cur_level

## XP remaining until the next level (0 if max level).
func xp_to_next_level() -> int:
	var lv: int = profile.get("level", 1)
	if lv - 1 >= _LEVEL_THRESHOLDS.size():
		return 0
	return _LEVEL_THRESHOLDS[lv - 1] - profile.get("xp", 0)

# ---- Progression tree helpers ----

func get_progression_tier(node_name: String) -> int:
	var prog: Dictionary = profile.get("progression", {})
	return int(prog.get(node_name, 0))

## Returns the stat multiplier for a progression node (1.0 = no bonus, 1.20 = tier 4).
func get_progression_multiplier(node_name: String) -> float:
	return 1.0 + float(get_progression_tier(node_name)) * 0.05

## True if the player can afford and meets the level requirement for the next tier.
func can_buy_progression(node_name: String) -> bool:
	var tier: int = get_progression_tier(node_name)
	if tier >= _PROG_COIN_COST.size():
		return false
	if profile.get("level", 1) < _PROG_LEVEL_REQ[tier]:
		return false
	return profile.get("coins", 0) >= _PROG_COIN_COST[tier]

## Returns the coin cost for the next tier of the given node (0 if at max).
func get_prog_next_cost(node_name: String) -> int:
	var tier: int = get_progression_tier(node_name)
	if tier >= _PROG_COIN_COST.size():
		return 0
	return _PROG_COIN_COST[tier]

## Returns the level required for the next tier (0 if at max).
func get_prog_next_level_req(node_name: String) -> int:
	var tier: int = get_progression_tier(node_name)
	if tier >= _PROG_LEVEL_REQ.size():
		return 0
	return _PROG_LEVEL_REQ[tier]

## Purchases the next tier if affordable. Returns true on success.
func buy_progression(node_name: String) -> bool:
	if not can_buy_progression(node_name):
		return false
	var prog: Dictionary = profile.get("progression", {})
	var tier: int = int(prog.get(node_name, 0))
	profile["coins"] = profile.get("coins", 0) - _PROG_COIN_COST[tier]
	prog[node_name] = tier + 1
	profile["progression"] = prog
	save_profile()
	return true

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return
	settings["mouse_sensitivity"] = cfg.get_value("settings", "mouse_sensitivity", settings["mouse_sensitivity"])
	settings["bot_difficulty"]    = cfg.get_value("settings", "bot_difficulty",    settings["bot_difficulty"])
	settings["master_volume"]     = cfg.get_value("settings", "master_volume",     settings["master_volume"])
	apply_volume(settings["master_volume"])

func _load_loadout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return
	var mech_path: String = cfg.get_value("loadout", "mech_path", "")
	if mech_path != "":
		var md = load(mech_path)
		if md != null:
			loadout["mech_def"] = md
	loadout["mech_weapon_choices"] = cfg.get_value("loadout", "mech_weapon_choices", {})
	var bot_path: String = cfg.get_value("loadout", "bot_path", "")
	if bot_path != "":
		var bd = load(bot_path)
		if bd != null:
			loadout["bot_def"] = bd
	loadout["team_size"] = cfg.get_value("loadout", "team_size", 1)
	var squad_paths: Array = cfg.get_value("loadout", "squad", [])
	loadout["squad"] = squad_paths
	var map_path: String = cfg.get_value("loadout", "map_path", "")
	if map_path != "":
		var mpd = load(map_path)
		if mpd != null:
			loadout["map_def"] = mpd

func save_loadout() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)  # preserve existing sections
	var mech_def = loadout.get("mech_def")
	cfg.set_value("loadout", "mech_path", mech_def.resource_path if mech_def != null else "")
	cfg.set_value("loadout", "mech_weapon_choices", loadout.get("mech_weapon_choices", {}))
	var bot_def = loadout.get("bot_def")
	cfg.set_value("loadout", "bot_path", bot_def.resource_path if bot_def != null else "")
	cfg.set_value("loadout", "team_size", loadout.get("team_size", 1))
	cfg.set_value("loadout", "squad", loadout.get("squad", []))
	var map_def = loadout.get("map_def")
	cfg.set_value("loadout", "map_path", map_def.resource_path if map_def != null else "")
	cfg.save(_SAVE_PATH)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)
	cfg.set_value("settings", "mouse_sensitivity", settings.get("mouse_sensitivity", 0.003))
	cfg.set_value("settings", "bot_difficulty",    settings.get("bot_difficulty",    1))
	cfg.set_value("settings", "master_volume",     settings.get("master_volume",     1.0))
	cfg.save(_SETTINGS_PATH)

func apply_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(linear))

# ---- Bot coordination (V5: absorbed from former AIDirector autoload) ----

var _bot_intents: Dictionary = {}  # bot Node -> {beacon: Node, team: int}

func ai_director_set_intent(bot: Node, beacon: Node, team: int) -> void:
	_bot_intents[bot] = {"beacon": beacon, "team": team}

func ai_director_clear_intent(bot: Node) -> void:
	_bot_intents.erase(bot)

func ai_director_intent_count(beacon: Node, team: int) -> int:
	var count := 0
	var stale: Array = []
	for bot in _bot_intents:
		if not is_instance_valid(bot):
			stale.append(bot)
			continue
		var entry: Dictionary = _bot_intents[bot]
		if entry.get("beacon") == beacon and entry.get("team") == team:
			count += 1
	for bot in stale:
		_bot_intents.erase(bot)
	return count
