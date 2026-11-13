extends "res://autoloads/game/SyncLog.gd"
# T393 part 2 (T290 audit: Game.gd ~1900 lines): Game's local progression -- the skill tree, the
# profile (ELO / XP / levels / coins / skills), the hangar loadout + presets, settings, the gameplay
# RNG -- and their files. Game.gd extends this script, so every name stays Game.<name>. Nothing here
# reaches into Game's own members; `account` (signed in = the server owns the profile) lives here
# because the skill buttons check it, and Game's accounts code fills it.

const _SAVE_PATH     := "user://profile.cfg"
const _SETTINGS_PATH := "user://settings.cfg"

# ELO constants
const _ELO_K := 32
const _BOT_ELO_BY_DIFFICULTY: Array = [800, 1000, 1200, 1400, 1600]

# Skill tree: Fibonacci coin costs for upgrade levels 2-12
const _SKILL_FIB_COSTS: Array[int] = [100, 200, 300, 500, 800, 1300, 2100, 3400, 5500, 8900, 14400]

# key -> {parents: Array[String], any_parent: bool, label: String, per_level: float}
# parents empty = root skill; any_parent=true means ONE parent unlocked suffices
const SKILL_TREE: Dictionary = {
	"damage":           {"parents": [],                             "any_parent": false, "label": "Damage",           "per_level": 0.015},
	"health":           {"parents": [],                             "any_parent": false, "label": "Health",            "per_level": 0.02},
	"projectile_speed": {"parents": ["damage"],                     "any_parent": false, "label": "Projectile Speed",  "per_level": 0.01},
	"spread_reduction": {"parents": ["projectile_speed"],           "any_parent": false, "label": "Spread Reduction",  "per_level": 0.06},
	"repair_rate":      {"parents": ["health"],                     "any_parent": false, "label": "Repair Rate",       "per_level": 0.5},
	"shield_capacity":  {"parents": ["health"],                     "any_parent": false, "label": "Shield Capacity",   "per_level": 0.05},
	"move_speed":       {"parents": ["damage", "health"],           "any_parent": true,  "label": "Move Speed",        "per_level": 0.01},
	"beacon_capture":   {"parents": ["move_speed"],                 "any_parent": false, "label": "Beacon Capture",    "per_level": 0.05},
	"contested_hold":   {"parents": ["beacon_capture"],             "any_parent": false, "label": "Contested Hold",    "per_level": 0.5},
	"ability_recharge": {"parents": ["damage", "health"],           "any_parent": true,  "label": "Ability Recharge",  "per_level": 0.05},
	"powerup_duration": {"parents": ["ability_recharge"],           "any_parent": false, "label": "Powerup Duration",  "per_level": 0.05},
	"coin_pickup":      {"parents": ["ability_recharge"],           "any_parent": false, "label": "Coin Pickup",       "per_level": 0.03},
	"xp_bonus":         {"parents": ["ability_recharge"],           "any_parent": false, "label": "XP Bonus",          "per_level": 0.03},
	"reload_speed":     {"parents": ["damage", "ability_recharge"], "any_parent": true,  "label": "Reload Speed",      "per_level": 0.04},
	"lock_speed":       {"parents": ["damage", "ability_recharge"], "any_parent": true,  "label": "Lock Speed",        "per_level": 0.05},
}

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
	"skills": {},  # skill_key -> level (1-12); absent = locked
}

# Loadout is set in Hangar and consumed by Arena.
# mech_def is a MechDef resource; null until Hangar initialises it.
var loadout: Dictionary = {
	"mech_def": null,
	"bot_def": preload("res://resources/mechs/Hippogriff.tres"),
	"weapon_overrides": [],        # Array[PackedScene|null], parallel to mech_def.weapon_slots
	"mech_weapon_choices": {},     # {mech_resource_path: [weapon_scene_path, ...]} -- a mech's last picks
	"squad_weapons": [],           # T345: per squad slot [weapon paths]; empty = that mech's last picks
	"team_size": 1,                # mechs per team (1 = 1v1, 5 = 5v5)
	"squad": [],                   # Array of 5 mech resource paths (slot 0 = player mech)
	"presets": {},                 # T177: {name: {"squad": [mech paths], "weapons": {mech path: [weapon paths]}}}
	"map_def": null,               # MapDef resource; null = Math Temple (default)
	"mode": "beacons",             # T285: "beacons" or "deathmatch" (SP picker)
}

## T196: over-the-shoulder side of the local view, +1 right / -1 left (V swaps).
## T252: 0 = the raised center view (Settings VIEW, the default; user 2026-11-05).
var shoulder := 0.0

var settings: Dictionary = {
	"mouse_sensitivity": 0.003,
	"bot_difficulty": 1,  # 0=Easy  1=Normal  2=Medium  3=Hard  4=Elite
	"master_volume": 0.5,
	"view": "center",   # T252: "center" (raised, crosshair over the mech) or "shoulder"
	"fancy_hangar": true,  # T254: the animated repair bay (GRAPHICS > FANCY HANGAR)
	"casings_long": true,  # T263: spent casings pool 1000 (ON) or 150 (GRAPHICS > LONG-LASTING CASINGS)
	"record_matches": false,  # T389: the T157 session recorder on a player's machine (Settings, for bug reports)
}

# M0.1: central seeded RNG for all gameplay randomness (weapon spread, etc.).
# Seeded from the match_seed in Match.start() (MP: the _rpc_match_start payload) so the server
# (and any deterministic replay) produces a reproducible physics tick stream.
# Cosmetic randomness (VFX, camera shake, drop-pod debris) stays on the global
# randf_range and is intentionally NOT routed here.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func seed_rng(s: int) -> void:
	rng.seed = s

## T207: signed in = {host, port, email, session, profile} (Game's accounts section fills it).
var account: Dictionary = {}

## T192: a callsign saved on this machine = signed in (TitleScreen skips the guest path).
## The file also holds the loadout, so the pilot_name key is the test, not the file.
var has_profile := false

func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return
	has_profile = cfg.has_section_key("profile", "pilot_name")
	profile["pilot_name"]  = cfg.get_value("profile", "pilot_name",  profile["pilot_name"])
	profile["wins"]        = cfg.get_value("profile", "wins",        0)
	profile["losses"]      = cfg.get_value("profile", "losses",      0)
	profile["elo"]         = cfg.get_value("profile", "elo",         1000)
	profile["xp"]          = cfg.get_value("profile", "xp",         0)
	profile["level"]       = cfg.get_value("profile", "level",       1)
	profile["coins"]       = cfg.get_value("profile", "coins",       0)
	profile["skills"] = cfg.get_value("profile", "skills", {})

func save_profile() -> void:
	if not account.is_empty():
		return  # T207: an account's profile lives on its server
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)
	cfg.set_value("profile", "pilot_name",  profile.get("pilot_name",  "Pilot"))
	cfg.set_value("profile", "wins",        profile.get("wins",        0))
	cfg.set_value("profile", "losses",      profile.get("losses",      0))
	cfg.set_value("profile", "elo",         profile.get("elo",         1000))
	cfg.set_value("profile", "xp",          profile.get("xp",         0))
	cfg.set_value("profile", "level",       profile.get("level",       1))
	cfg.set_value("profile", "coins",       profile.get("coins",       0))
	cfg.set_value("profile", "skills",      profile.get("skills", {}))
	cfg.save(_SAVE_PATH)
	has_profile = true

# ---- ELO / XP / match helpers ----

func get_bot_elo() -> int:
	var diff: int = clampi(settings.get("bot_difficulty", 1), 0, 4)
	return _BOT_ELO_BY_DIFFICULTY[diff]

func apply_coin_pickup_bonus(base: int) -> int:
	return roundi(float(base) * (1.0 + get_skill_effect("coin_pickup")))

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

# ---- Skill tree helpers ----

func skill_level(key: String) -> int:
	return int(profile.get("skills", {}).get(key, 0))

func skill_points_available() -> int:
	return maxi(0, profile.get("level", 1) - profile.get("skills", {}).size())

func _parents_unlocked(key: String) -> bool:
	var def: Dictionary = SKILL_TREE.get(key, {})
	var parents: Array = def.get("parents", [])
	if parents.is_empty():
		return true
	var skills: Dictionary = profile.get("skills", {})
	if def.get("any_parent", false):
		for p: String in parents:
			if skills.has(p):
				return true
		return false
	for p: String in parents:
		if not skills.has(p):
			return false
	return true

func can_unlock(key: String) -> bool:
	if not SKILL_TREE.has(key):
		return false
	if profile.get("skills", {}).has(key):
		return false
	return skill_points_available() > 0 and _parents_unlocked(key)

func can_upgrade(key: String) -> bool:
	var lv: int = skill_level(key)
	if lv <= 0 or lv >= 12:
		return false
	return profile.get("coins", 0) >= _SKILL_FIB_COSTS[lv - 1]

# T213: signed in, a skill changes on the account's server (account_skill); these are
# the local (guest) path.
func unlock_skill(key: String) -> bool:
	if not account.is_empty() or not _skill_apply("unlock_skill", key):
		return false
	save_profile()
	return true

func upgrade_skill(key: String) -> bool:
	if not account.is_empty() or not _skill_apply("upgrade_skill", key):
		return false
	save_profile()
	return true

# The rules-checked change to `profile` (no save): local skills and, borrowed, accounts.
func _skill_apply(op: String, key: String) -> bool:
	if op == "unlock_skill":
		if not can_unlock(key):
			return false
		var skills: Dictionary = profile.get("skills", {})
		skills[key] = 1
		profile["skills"] = skills
		return true
	if op == "upgrade_skill":
		if not can_upgrade(key):
			return false
		var lv: int = skill_level(key)
		profile["coins"] = profile.get("coins", 0) - _SKILL_FIB_COSTS[lv - 1]
		var skills: Dictionary = profile.get("skills", {})
		skills[key] = lv + 1
		profile["skills"] = skills
		return true
	return false

## Server (AccountServer, main thread): the same rules on an account's profile; {} = refused.
func skill_op_on(prof: Dictionary, op: String, key: String) -> Dictionary:
	var keep := profile
	profile = prof.duplicate(true)
	var ok := _skill_apply(op, key)
	var out := profile
	profile = keep
	return out if ok else {}

func get_skill_effect(key: String) -> float:
	var def: Dictionary = SKILL_TREE.get(key, {})
	return float(skill_level(key)) * float(def.get("per_level", 0.0))

## T332: a pilot's skill effect from its own skills (the roster entry), not this machine's profile.
## T361 (HUMAN_FOUND 2026-11-08 late: "Skill tree should show what it does ... so that the numbers
## are visible"): a skill's total effect at `level`, as the player reads it -- "+6%", "+1.5 HP/s".
static func skill_effect_text(key: String, level: int) -> String:
	var v: float = float(level) * float(SKILL_TREE.get(key, {}).get("per_level", 0.0))
	var unit := "%"
	match key:
		"repair_rate":
			unit = " HP/s"
		"contested_hold":
			unit = " s"
		_:
			v *= 100.0
	var n := ("%d" % roundi(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v)
	return "+%s%s" % [n, unit]

static func skill_effect_in(skills: Dictionary, key: String) -> float:
	var def: Dictionary = SKILL_TREE.get(key, {})
	return float(clampi(int(skills.get(key, 0)), 0, 12)) * float(def.get("per_level", 0.0))

## T332 / V41: skills as a client reports them -- known keys, levels 1..12, no more unlocks
## than its level allows (skill_points_available). Accounts' come from the server profile.
static func sanitize_skills(raw, level: int) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for k in raw:
		if SKILL_TREE.has(str(k)) and out.size() < maxi(0, level):
			out[str(k)] = clampi(int(raw[k]), 1, 12)
	return out

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return
	settings["mouse_sensitivity"] = cfg.get_value("settings", "mouse_sensitivity", settings["mouse_sensitivity"])
	settings["bot_difficulty"]    = cfg.get_value("settings", "bot_difficulty",    settings["bot_difficulty"])
	settings["master_volume"]     = cfg.get_value("settings", "master_volume",     settings["master_volume"])
	settings["view"]              = cfg.get_value("settings", "view",              settings["view"])
	settings["fancy_hangar"]      = cfg.get_value("settings", "fancy_hangar",      settings["fancy_hangar"])
	settings["casings_long"]      = cfg.get_value("settings", "casings_long",      settings["casings_long"])
	settings["record_matches"]    = cfg.get_value("settings", "record_matches",    settings["record_matches"])
	shoulder = 0.0 if settings["view"] == "center" else 1.0  # T252
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
	loadout["mech_weapon_choices"] = _migrate_weapons(cfg.get_value("loadout", "mech_weapon_choices", {}))
	loadout["squad_weapons"] = _migrate_weapons(cfg.get_value("loadout", "squad_weapons", []))  # T345
	var bot_path: String = cfg.get_value("loadout", "bot_path", "")
	if bot_path != "":
		var bd = load(bot_path)
		if bd != null:
			loadout["bot_def"] = bd
	loadout["team_size"] = cfg.get_value("loadout", "team_size", 1)
	loadout["sp_bots"] = cfg.get_value("loadout", "sp_bots", [])  # T251: [ally, enemy]; [] = fill to team_size
	var squad_paths: Array = cfg.get_value("loadout", "squad", [])
	loadout["squad"] = squad_paths
	loadout["presets"] = _migrate_weapons(cfg.get_value("loadout", "presets", {}))
	var map_path: String = cfg.get_value("loadout", "map_path", "")
	if map_path != "" and ResourceLoader.exists(map_path):  # T248: a saved map that was deleted (Ironworks) -> default
		var mpd = load(map_path)
		if mpd != null:
			loadout["map_def"] = mpd
	loadout["mode"] = cfg.get_value("loadout", "mode", "beacons")  # T285

# T194: the heavy rocket launcher was cut (rockets are light-only; AERIAL HV is the heavy
# pick). Saved choices and presets from before load with the replacement.
const _CUT_WEAPONS := {"res://scenes/weapons/RocketLauncherHeavy.tscn": "res://scenes/weapons/AerialStrikeHeavy.tscn"}

static func _migrate_weapons(v: Variant) -> Variant:
	if v is String:
		return _CUT_WEAPONS.get(v, v)
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _migrate_weapons(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _migrate_weapons(v[k])
		return out
	return v

func save_loadout() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)  # preserve existing sections
	var mech_def = loadout.get("mech_def")
	cfg.set_value("loadout", "mech_path", mech_def.resource_path if mech_def != null else "")
	cfg.set_value("loadout", "mech_weapon_choices", loadout.get("mech_weapon_choices", {}))
	cfg.set_value("loadout", "squad_weapons", loadout.get("squad_weapons", []))  # T345
	var bot_def = loadout.get("bot_def")
	cfg.set_value("loadout", "bot_path", bot_def.resource_path if bot_def != null else "")
	cfg.set_value("loadout", "team_size", loadout.get("team_size", 1))
	cfg.set_value("loadout", "sp_bots", loadout.get("sp_bots") if loadout.get("sp_bots") is Array else [])  # T251 ([] = fill)
	cfg.set_value("loadout", "squad", loadout.get("squad", []))
	cfg.set_value("loadout", "presets", loadout.get("presets", {}))
	var map_def = loadout.get("map_def")
	cfg.set_value("loadout", "map_path", map_def.resource_path if map_def != null else "")
	cfg.set_value("loadout", "mode", loadout.get("mode", "beacons"))  # T285
	cfg.save(_SAVE_PATH)

## T345 (HUMAN_FOUND 2026-11-08: "two of the same mech in a squad can't carry different weapons --
## changing one changes all"): each squad slot keeps its own picks; a slot never set falls back to
## that mech's last picks (mech_weapon_choices), so a mech new to the squad starts as you left it.
func slot_weapons(i: int) -> Array:
	var sw: Array = loadout.get("squad_weapons", [])
	if i < sw.size() and sw[i] is Array and not (sw[i] as Array).is_empty():
		return sw[i]
	var squad: Array = loadout.get("squad", [])
	return loadout.get("mech_weapon_choices", {}).get(squad[i], []) if i >= 0 and i < squad.size() else []

func set_slot_weapons(i: int, paths: Array) -> void:
	var sw: Array = loadout.get("squad_weapons", [])
	while sw.size() <= i:
		sw.append([])
	sw[i] = paths.duplicate()
	loadout["squad_weapons"] = sw

## T177: hangar squad presets -- the whole squad (5 mech paths) plus the weapon choices
## of the mechs in it, under a typed name. Same name = overwrite. T345: and each slot's own picks.
func save_preset(pname: String) -> void:
	var choices: Dictionary = loadout.get("mech_weapon_choices", {})
	var weapons := {}
	for path in loadout.get("squad", []):
		if choices.has(path):
			weapons[path] = (choices[path] as Array).duplicate()
	var presets: Dictionary = loadout.get("presets", {})
	var per_slot: Array = []
	for i in (loadout.get("squad", []) as Array).size():
		per_slot.append(slot_weapons(i).duplicate())
	presets[pname] = {"squad": (loadout.get("squad", []) as Array).duplicate(), "weapons": weapons,
		"slot_weapons": per_slot}
	loadout["presets"] = presets
	save_loadout()

## Makes preset `pname` the current squad (its weapon choices win for its mechs). False if unknown.
func load_preset(pname: String) -> bool:
	var p: Dictionary = loadout.get("presets", {}).get(pname, {})
	if p.is_empty():
		return false
	loadout["squad"] = (p["squad"] as Array).duplicate()
	var choices: Dictionary = loadout.get("mech_weapon_choices", {})
	for path in p["weapons"]:
		choices[path] = (p["weapons"][path] as Array).duplicate()
	loadout["mech_weapon_choices"] = choices
	loadout["squad_weapons"] = (p.get("slot_weapons", []) as Array).duplicate(true)  # T345 (older presets: per mech)
	if not loadout["squad"].is_empty():
		var md = load(loadout["squad"][0])
		if md != null:
			loadout["mech_def"] = md
	save_loadout()
	return true

func delete_preset(pname: String) -> void:
	loadout.get("presets", {}).erase(pname)
	save_loadout()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value("settings", "mouse_sensitivity", settings.get("mouse_sensitivity", 0.003))
	cfg.set_value("settings", "bot_difficulty",    settings.get("bot_difficulty",    1))
	cfg.set_value("settings", "master_volume",     settings.get("master_volume",     0.5))
	cfg.set_value("settings", "view",              settings.get("view",              "center"))
	cfg.set_value("settings", "fancy_hangar",      settings.get("fancy_hangar",      true))
	cfg.set_value("settings", "casings_long",      settings.get("casings_long",      true))
	cfg.set_value("settings", "record_matches",    settings.get("record_matches",    false))
	cfg.save(_SETTINGS_PATH)

func apply_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(linear))
