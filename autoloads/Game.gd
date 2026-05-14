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

# ---- Multiplayer transport (V5: no new autoload; stays in Game.gd) ----

signal mp_peer_connected(id: int)
signal mp_peer_disconnected(id: int)
signal mp_join_failed
signal mp_server_lost

func _ready() -> void:
	_load_profile()
	_load_settings()
	_load_loadout()
	multiplayer.peer_connected.connect(_on_mp_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	multiplayer.connection_failed.connect(_on_mp_connection_failed)
	multiplayer.server_disconnected.connect(_on_mp_server_disconnected)

func host(port: int = 8910) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("Game.host: create_server failed (port %d): %d" % [port, err])
		mp_join_failed.emit()
		return
	multiplayer.multiplayer_peer = peer

func join(ip: String, port: int = 8910) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("Game.join: create_client failed (%s:%d): %d" % [ip, port, err])
		mp_join_failed.emit()
		return
	multiplayer.multiplayer_peer = peer

func disconnect_mp() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _on_mp_peer_connected(id: int) -> void:
	mp_peer_connected.emit(id)
	# Lobby._on_peer_connected runs synchronously above, populating mp_lobby["peers"][id].
	# Now request real profile meta so the placeholder is replaced promptly.
	if multiplayer.is_server():
		_rpc_request_meta.rpc_id(id)

# Server -> client: asks client to send its profile metadata (V36).
@rpc("authority", "call_remote", "reliable")
func _rpc_request_meta() -> void:
	var meta := {
		"pilot_name": profile.get("pilot_name", "Pilot"),
		"elo":        profile.get("elo", 1000),
		"level":      profile.get("level", 1),
	}
	_rpc_send_meta.rpc_id(1, meta)

# Client -> server: delivers profile metadata (V36, V41).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_meta(meta: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	# V41: sender must be a known lobby peer
	if not mp_lobby["peers"].has(sender):
		push_error("_rpc_send_meta: unknown sender %d" % sender)
		return
	var entry: Dictionary = mp_lobby["peers"][sender]
	entry["pilot_name"] = str(meta.get("pilot_name", "Pilot"))
	entry["elo"]        = int(meta.get("elo", 1000))
	entry["level"]      = int(meta.get("level", 1))
	broadcast_lobby()

func _on_mp_peer_disconnected(id: int) -> void:
	mp_peer_disconnected.emit(id)

func _on_mp_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mp_join_failed.emit()

func _on_mp_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mp_server_lost.emit()

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
	profile["skills"] = cfg.get_value("profile", "skills", {})

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
	cfg.set_value("profile", "skills",      profile.get("skills", {}))
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

	# XP (more XP for beating tougher opponents; xp_bonus skill scales gain)
	var xp_gain: int
	if won:
		xp_gain = clampi(roundi(50.0 * float(opp_elo) / float(maxi(1, my_elo))), 25, 200)
	else:
		xp_gain = clampi(roundi(15.0 * float(opp_elo) / float(maxi(1, my_elo))), 5, 50)
	xp_gain = roundi(float(xp_gain) * (1.0 + get_skill_effect("xp_bonus")))
	profile["xp"] = profile.get("xp", 0) + xp_gain

	# Level-up check
	_check_level_up()

	# Coins (coin_pickup skill scales award)
	var base_coins: int = 75 if won else 20
	profile["coins"] = profile.get("coins", 0) + apply_coin_pickup_bonus(base_coins)

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

func unlock_skill(key: String) -> bool:
	if not can_unlock(key):
		return false
	var skills: Dictionary = profile.get("skills", {})
	skills[key] = 1
	profile["skills"] = skills
	save_profile()
	return true

func upgrade_skill(key: String) -> bool:
	if not can_upgrade(key):
		return false
	var lv: int = skill_level(key)
	profile["coins"] = profile.get("coins", 0) - _SKILL_FIB_COSTS[lv - 1]
	var skills: Dictionary = profile.get("skills", {})
	skills[key] = lv + 1
	profile["skills"] = skills
	save_profile()
	return true

func get_skill_effect(key: String) -> float:
	var def: Dictionary = SKILL_TREE.get(key, {})
	return float(skill_level(key)) * float(def.get("per_level", 0.0))

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

# ---- Multiplayer lobby state (V39) ----

signal lobby_updated

# Server-authoritative lobby state.  Clients receive a replicated copy via
# _rpc_sync_lobby.  All mutation from clients must go through an @rpc to server
# which then calls broadcast_lobby().
var mp_lobby: Dictionary = {
	"peers":      {},    # peer_id (int) -> {pilot_name, elo, level, squad, ready}
	"bot_fill":   true,
	"team_size":  1,
	"map_path":   "res://resources/maps/MathTemple.tres",
	"match_seed": 0,
}

@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby(data: Dictionary) -> void:
	mp_lobby = data
	lobby_updated.emit()

# V40: all coordinated scene transitions go through here (server-origin only).
@rpc("authority", "call_local", "reliable")
func _rpc_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func broadcast_lobby() -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_lobby.rpc(mp_lobby)

# ---- Squad RPC (T113) ----

# Infer slot_size from path naming convention: *Heavy* = 1, else 0 (V17).
func _weapon_size_from_path(path: String) -> int:
	return 1 if "Heavy" in path else 0

# V17: validate one squad entry dict {mech, weapons}.
func _validate_squad_entry(entry: Dictionary) -> bool:
	var mech_path: String = str(entry.get("mech", ""))
	if mech_path.is_empty() or not ResourceLoader.exists(mech_path):
		push_error("_validate_squad_entry: invalid mech path '%s'" % mech_path)
		return false
	var md = ResourceLoader.load(mech_path)
	if md == null:
		push_error("_validate_squad_entry: failed to load mech '%s'" % mech_path)
		return false
	var weapons: Array = entry.get("weapons", [])
	var slots: Array = md.weapon_slots if "weapon_slots" in md else []
	for i in mini(slots.size(), weapons.size()):
		var wpn_path: String = str(weapons[i])
		if wpn_path.is_empty():
			continue
		if not ResourceLoader.exists(wpn_path):
			push_error("_validate_squad_entry: invalid weapon '%s'" % wpn_path)
			return false
		var slot = slots[i]
		var required: int = slot.slot_size if "slot_size" in slot else 0
		if _weapon_size_from_path(wpn_path) != required:
			push_error("V17: weapon '%s' wrong size for slot %d (need %d)" % [wpn_path, i, required])
			return false
	return true

# Validate + store squad for a peer, then broadcast. Called directly on server,
# or via _rpc_set_squad on clients.
func _apply_squad(peer_id: int, squad: Array) -> void:
	if not mp_lobby["peers"].has(peer_id):
		push_error("_apply_squad: unknown peer %d" % peer_id)
		return
	if squad.size() != 5:
		push_error("_apply_squad: expected 5 entries, got %d" % squad.size())
		return
	for entry in squad:
		if not _validate_squad_entry(entry):
			return
	mp_lobby["peers"][peer_id]["squad"] = squad
	broadcast_lobby()

# Client -> server: send squad selection (V39, V41).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_squad(squad: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_apply_squad(sender, squad)

# ---- Ready toggle (T114) ----

func _apply_ready(peer_id: int, ready: bool) -> void:
	if not mp_lobby["peers"].has(peer_id):
		push_error("_apply_ready: unknown peer %d" % peer_id)
		return
	mp_lobby["peers"][peer_id]["ready"] = ready
	broadcast_lobby()

# Client -> server: toggle ready state (V39, V41).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_apply_ready(sender, ready)

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
