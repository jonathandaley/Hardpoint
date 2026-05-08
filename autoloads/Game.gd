extends Node
# Singleton -- cross-match persistent state. The only autoload.
#
# Data ownership:
#   profile  -- server-owned fields (wins/losses/pilot_name). Keep clean for future sync.
#   loadout  -- server-owned fields (chosen mech, weapon config). Same rule.
#   settings -- local-only fields (mouse sensitivity). Never sent to server.

const _SAVE_PATH     := "user://profile.cfg"
const _SETTINGS_PATH := "user://settings.cfg"

var profile: Dictionary = {
	"pilot_name": "Pilot",
	"wins": 0,
	"losses": 0,
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
}

var settings: Dictionary = {
	"mouse_sensitivity": 0.003,
	"bot_difficulty": 1,  # 0=Easy  1=Normal  2=Medium  3=Hard  4=Elite
	"master_volume": 1.0,
}

func _ready() -> void:
	_load_profile()
	_load_settings()
	_load_loadout()

func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return
	profile["pilot_name"] = cfg.get_value("profile", "pilot_name", profile["pilot_name"])
	profile["wins"]        = cfg.get_value("profile", "wins",        0)
	profile["losses"]      = cfg.get_value("profile", "losses",      0)

func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)
	cfg.set_value("profile", "pilot_name", profile.get("pilot_name", "Pilot"))
	cfg.set_value("profile", "wins",       profile.get("wins",       0))
	cfg.set_value("profile", "losses",     profile.get("losses",     0))
	cfg.save(_SAVE_PATH)

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
