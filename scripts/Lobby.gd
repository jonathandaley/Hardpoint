extends Control

const _MAP_OPTIONS: Array = [
	{"name": "Math Temple", "path": "res://resources/maps/MathTemple.tres"},
	{"name": "Badlands",    "path": "res://resources/maps/Badlands.tres"},
	{"name": "Sydney",      "path": "res://resources/maps/City.tres"},
	{"name": "Redwood Forest", "path": "res://resources/maps/Forest.tres"},
	{"name": "Giza", "path": "res://resources/maps/Giza.tres"},
	{"name": "Swamp", "path": "res://resources/maps/Swamp.tres"},
	{"name": "Factory", "path": "res://resources/maps/Factory.tres"},
	{"name": "Corvette", "path": "res://resources/maps/Corvette.tres"},
]

const ROSTER: Array = [
	"res://resources/mechs/Slip.tres",
	"res://resources/mechs/Cesh.tres",
	"res://resources/mechs/Seeker.tres",
	"res://resources/mechs/Hornet.tres",
	"res://resources/mechs/Hippogriff.tres",
	"res://resources/mechs/Pegasus.tres",
	"res://resources/mechs/Kestrel.tres",
	"res://resources/mechs/Everest.tres",
	"res://resources/mechs/Vesuvius.tres",
]

const WEAPON_CATALOG: Array = [
	{"name": "RIFLE LT",      "path": "res://scenes/weapons/RifleLight.tscn",           "slot_size": 0},
	{"name": "SNIPER LT",     "path": "res://scenes/weapons/SniperLight.tscn",          "slot_size": 0},
	{"name": "MG LT",         "path": "res://scenes/weapons/MachineGunLight.tscn",      "slot_size": 0},
	{"name": "SHOTGUN LT",    "path": "res://scenes/weapons/ShotgunLight.tscn",         "slot_size": 0},
	{"name": "MISSILE LT",    "path": "res://scenes/weapons/MissileLauncherLight.tscn", "slot_size": 0},
	{"name": "ROCKET LT",     "path": "res://scenes/weapons/RocketLauncherLight.tscn",  "slot_size": 0},
	{"name": "LASER LT",      "path": "res://scenes/weapons/LaserCannonLight.tscn",     "slot_size": 0},
	{"name": "ARC LT",        "path": "res://scenes/weapons/ArcWeaponLight.tscn",       "slot_size": 0},
	{"name": "RIFLE HV",      "path": "res://scenes/weapons/RifleHeavy.tscn",           "slot_size": 1},
	{"name": "SNIPER HV",     "path": "res://scenes/weapons/SniperHeavy.tscn",          "slot_size": 1},
	{"name": "MG HV",         "path": "res://scenes/weapons/MachineGunHeavy.tscn",     "slot_size": 1},
	{"name": "SHOTGUN HV",    "path": "res://scenes/weapons/ShotgunHeavy.tscn",        "slot_size": 1},
	{"name": "MISSILE HV",    "path": "res://scenes/weapons/MissileLauncherHeavy.tscn","slot_size": 1},
	{"name": "LASER HV",      "path": "res://scenes/weapons/LaserCannonHeavy.tscn",    "slot_size": 1},
	{"name": "ARC HV",        "path": "res://scenes/weapons/ArcWeaponHeavy.tscn",      "slot_size": 1},
	{"name": "AERIAL HV",     "path": "res://scenes/weapons/AerialStrikeHeavy.tscn",   "slot_size": 1},
	{"name": "PATIENCE HV",   "path": "res://scenes/weapons/PatienceHeavy.tscn",        "slot_size": 1},
]

@onready var _peer_list: VBoxContainer = $PeerList
@onready var _host_controls: VBoxContainer = $HostControls
@onready var _bot_fill_check: CheckBox = $HostControls/BotFillRow/BotFillCheck
@onready var _dm_check: CheckBox = $HostControls/BotFillRow/DeathMatchCheck  # T285
@onready var _team_size_spin: SpinBox = $HostControls/TeamSizeRow/TeamSizeSpin
@onready var _map_option: OptionButton = $HostControls/MapRow/MapOption
@onready var _start_button: Button = $StartButton
@onready var _status_label: Label = $StatusLabel
@onready var _ready_btn: Button = $ReadyBtn

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.lobby_updated.connect(_on_lobby_updated)
	Game.mp_peer_connected.connect(_on_peer_connected)
	Game.mp_peer_disconnected.connect(_on_peer_disconnected)

	_setup_map_option()
	_dm_check.toggled.connect(func(on: bool) -> void:  # T285
		Game.mp_lobby["mode"] = "deathmatch" if on else "beacons"
		Game.broadcast_lobby())

	# B44: Lobby also loads on the V40 return after a match -- the match is over, and
	# the connected peers must NOT be wiped (only a fresh host session starts empty).
	Game.mp_active_match["roster"] = []
	if multiplayer.is_server() and not Game.mp_lobby["peers"].is_empty():
		# B62: the match just changed everyone's ELO/level; the lobby copy (match stats'
		# pre_elo, peer list) was from join time. Refresh own entry, re-ask every client.
		var me: Dictionary = Game.mp_lobby["peers"].get(multiplayer.get_unique_id(), {})
		me["elo"] = Game.profile.get("elo", 1000)
		me["level"] = Game.profile.get("level", 1)
		Game._rpc_request_meta.rpc()
		Game.broadcast_lobby()
	elif multiplayer.is_server() and Game.dedicated:
		pass  # T204: Game.start_dedicated set the lobby up; the server is not a player
	elif multiplayer.is_server():
		Game.mp_lobby = {
			"peers":      {},
			"bot_fill":   true,
			"team_size":  Game.loadout.get("team_size", 1),
			"map_path":   "res://resources/maps/MathTemple.tres",
			"mode":       "beacons",
			"match_seed": 0,
		}
		var my_id := multiplayer.get_unique_id()
		Game.mp_lobby["peers"][my_id] = _local_peer_meta()
		Game.broadcast_lobby()
	else:
		# Auto-send current squad so server has it immediately.
		Game._rpc_set_squad.rpc_id(1, _build_squad_data())

	_update_host_controls_visibility()
	_rebuild_peer_list()
	_sync_host_controls_to_lobby()
	_update_start_button()
	_update_ready_btn()

# ---- Peer meta helpers ----

func _mech_short_name(path: String) -> String:
	return path.get_file().get_basename()

static func _build_squad_data() -> Array:
	var squad_paths: Array = Game.loadout.get("squad", [])
	var choices: Dictionary = Game.loadout.get("mech_weapon_choices", {})
	var result: Array = []
	for path in squad_paths:
		result.append({"mech": path, "weapons": choices.get(path, [])})
	while result.size() < 5:
		var fallback: String = ROSTER[0] if ROSTER.size() > 0 else ""
		result.append({"mech": fallback, "weapons": []})
	return result

static func _local_peer_meta() -> Dictionary:
	return {
		"pilot_name": Game.profile.get("pilot_name", "Pilot"),
		"elo":        Game.profile.get("elo", 1000),
		"level":      Game.profile.get("level", 1),
		"skills":     Game.profile.get("skills", {}),  # T332
		"squad":      _build_squad_data(),
		"ready":      false,
	}

# ---- Peer list ----

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# Game._on_mp_peer_connected already added placeholder + broadcast.
	# Just ensure the entry exists (guard for future ordering changes).
	if not Game.mp_lobby["peers"].has(id):
		Game.mp_lobby["peers"][id] = {
			"pilot_name": "Peer %d" % id,
			"elo": 1000, "level": 1, "squad": [], "ready": false,
		}
		Game.broadcast_lobby()

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	Game.mp_lobby["peers"].erase(id)
	Game.broadcast_lobby()

func _on_lobby_updated() -> void:
	_status_label.text = "MATCH STARTING..." if Game.mp_lobby.get("starting", false) else ""  # T204
	_rebuild_peer_list()
	_sync_host_controls_to_lobby()
	_update_start_button()
	_update_ready_btn()

func _rebuild_peer_list() -> void:
	for child in _peer_list.get_children():
		child.queue_free()
	var peers: Dictionary = Game.mp_lobby.get("peers", {})
	for id in peers:
		var entry: Dictionary = peers[id]
		var row := HBoxContainer.new()

		var name_lbl := Label.new()
		name_lbl.text = entry.get("pilot_name", "?")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 13)

		var elo_lbl := Label.new()
		elo_lbl.text = "ELO %d" % entry.get("elo", 0)
		elo_lbl.custom_minimum_size.x = 75
		elo_lbl.add_theme_font_size_override("font_size", 13)

		var squad_lbl := Label.new()
		var sq: Array = entry.get("squad", [])
		if sq.is_empty():
			squad_lbl.text = "[no squad]"
		else:
			var names: Array = []
			for e in sq:
				names.append(_mech_short_name(str(e.get("mech", ""))))
			squad_lbl.text = ", ".join(names)
		squad_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		squad_lbl.add_theme_font_size_override("font_size", 11)
		squad_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))

		var ready_lbl := Label.new()
		ready_lbl.text = "[RDY]" if entry.get("ready", false) else "[   ]"
		ready_lbl.custom_minimum_size.x = 45
		ready_lbl.add_theme_font_size_override("font_size", 13)

		row.add_child(name_lbl)
		row.add_child(elo_lbl)
		row.add_child(squad_lbl)
		row.add_child(ready_lbl)
		_peer_list.add_child(row)

# ---- Host controls ----

func _setup_map_option() -> void:
	_map_option.clear()
	for i in _MAP_OPTIONS.size():
		_map_option.add_item(_MAP_OPTIONS[i]["name"], i)

func _update_host_controls_visibility() -> void:
	_host_controls.visible = multiplayer.is_server()
	_start_button.visible = multiplayer.is_server()

func _sync_host_controls_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	_bot_fill_check.set_pressed_no_signal(Game.mp_lobby.get("bot_fill", true))
	_dm_check.set_pressed_no_signal(Game.mp_lobby.get("mode", "beacons") == "deathmatch")
	_team_size_spin.set_value_no_signal(Game.mp_lobby.get("team_size", 1))
	var map_path: String = Game.mp_lobby.get("map_path", "")
	for i in _MAP_OPTIONS.size():
		if _MAP_OPTIONS[i]["path"] == map_path:
			_map_option.select(i)
			break

func _update_start_button() -> void:
	if not multiplayer.is_server():
		return
	var bot_fill: bool = Game.mp_lobby.get("bot_fill", true)
	var peers: Dictionary = Game.mp_lobby.get("peers", {})
	if bot_fill:
		_start_button.disabled = peers.is_empty()
	else:
		var all_ready := peers.size() >= 2
		for id in peers:
			if not peers[id].get("ready", false):
				all_ready = false
				break
		_start_button.disabled = not all_ready

func _on_bot_fill_toggled(pressed: bool) -> void:
	Game.mp_lobby["bot_fill"] = pressed
	Game.broadcast_lobby()
	_update_start_button()

func _on_team_size_changed(value: float) -> void:
	var sz := int(value)
	Game.mp_lobby["team_size"] = sz
	Game.loadout["team_size"] = sz
	Game.broadcast_lobby()

func _on_map_selected(index: int) -> void:
	if index >= 0 and index < _MAP_OPTIONS.size():
		Game.mp_lobby["map_path"] = _MAP_OPTIONS[index]["path"]
		Game.broadcast_lobby()

# ---- Squad picker ----

func _update_ready_btn() -> void:
	var my_id := multiplayer.get_unique_id()
	var my_entry: Dictionary = Game.mp_lobby.get("peers", {}).get(my_id, {})
	_ready_btn.text = "UNREADY" if my_entry.get("ready", false) else "READY UP"

func _on_ready_btn_pressed() -> void:
	var my_id := multiplayer.get_unique_id()
	var my_entry: Dictionary = Game.mp_lobby.get("peers", {}).get(my_id, {})
	var new_ready: bool = not my_entry.get("ready", false)
	if multiplayer.is_server():
		Game._apply_ready(my_id, new_ready)
	else:
		Game._rpc_set_ready.rpc_id(1, new_ready)

func _on_start_pressed() -> void:
	var roster := _build_roster()
	var match_seed := randi()
	Game.mp_lobby["match_seed"] = match_seed
	var map_path: String = Game.mp_lobby.get("map_path", "res://resources/maps/MathTemple.tres")
	Game._rpc_match_start.rpc(map_path, roster, match_seed, Game.mp_lobby.get("mode", "beacons"))

# T184: static -- Game.setup_sp_match builds the SP roster with these too.
const BotNames := preload("res://scripts/BotNames.gd")

static func _build_roster() -> Array:
	var roster: Array = []
	var slot_idx := 0
	var bot_id := 0
	var team_size: int = clampi(Game.mp_lobby.get("team_size", 1), 1, 6)

	# Deterministic peer ordering by peer_id.
	var peer_ids: Array = Game.mp_lobby.get("peers", {}).keys()
	peer_ids.sort()

	var team_counts := [0, 0]
	for i in peer_ids.size():
		var pid: int = peer_ids[i]
		var team: int = i % 2
		var entry: Dictionary = Game.mp_lobby["peers"][pid]
		roster.append({
			"slot_idx": slot_idx,
			"peer_id":  pid,
			"team":     team,
			"squad":    entry.get("squad", _default_bot_squad(0)),
			"bot_id":   -1,
		})
		slot_idx += 1
		team_counts[team] += 1

	# T251: singleplayer sets exact bot counts per team ([ally, enemy]; 0 = none) instead
	var counts = Game.mp_lobby.get("bot_counts", null)
	if counts is Array and counts.size() == 2:
		for team in range(2):
			var target: int = team_counts[team] + clampi(int(counts[team]), 0, 5)
			while team_counts[team] < target:
				roster.append({
					"slot_idx": slot_idx,
					"peer_id":  0,
					"team":     team,
					"squad":    _default_bot_squad(bot_id),
					"bot_id":   bot_id,
				})
				slot_idx += 1
				team_counts[team] += 1
				bot_id += 1
	# Bot fill: pad each team to team_size (V29: bot_id used for RNG seed).
	elif Game.mp_lobby.get("bot_fill", true):
		for team in range(2):
			while team_counts[team] < team_size:
				roster.append({
					"slot_idx": slot_idx,
					"peer_id":  0,
					"team":     team,
					"squad":    _default_bot_squad(bot_id),
					"bot_id":   bot_id,
				})
				slot_idx += 1
				team_counts[team] += 1
				bot_id += 1

	# T325: callsigns ride the roster to every peer -- players keep theirs, bots draw from the deck.
	# T332: so do pilot skills -- players' (sanitized), ELITE bots' named builds (T335), others none.
	var taken: Array = []
	var elite: bool = int(Game.settings.get("bot_difficulty", 1)) >= 4
	for e in roster:
		if int(e["peer_id"]) != 0:
			var meta: Dictionary = Game.mp_lobby["peers"].get(e["peer_id"], {})
			e["name"] = str(meta.get("pilot_name", "Pilot"))
			e["skills"] = Game.sanitize_skills(meta.get("skills", {}), int(meta.get("level", 1)))
			taken.append(e["name"])
	for e in roster:
		if int(e["peer_id"]) == 0:
			e["name"] = BotNames.next_name(taken, elite)
			e["skills"] = (BotNames.ELITE.get(e["name"], {}) as Dictionary).duplicate()
			taken.append(e["name"])
	return roster

static func _default_bot_squad(bot_id: int) -> Array:
	var mech_path: String = ROSTER[bot_id % ROSTER.size()]
	var mech_def: Resource = load(mech_path)
	var rng := RandomNumberGenerator.new()
	rng.randomize()  # roster is broadcast, so peers never re-derive it (no determinism needed)
	var result: Array = []
	for _i in 5:
		result.append({"mech": mech_path, "weapons": bot_weapon_paths(mech_def, rng)})
	return result

## T171: random bot loadout -- ONE weapon family (RIFLE, MG, ...) in every slot of
## `mech_def`, sized per slot; mixed loadouts fight worse (ranges, lead, lock all differ).
## Only families that exist in every slot size the mech has (AERIAL/PATIENCE: heavy only).
## ponytail: uniform random family; weight by mech (speed, HP, slot size) when it matters.
static func bot_weapon_paths(mech_def: Resource, rng: RandomNumberGenerator) -> Array:
	var fams := {}  # "RIFLE" -> {slot_size: path}
	for w in WEAPON_CATALOG:
		var f: String = w["name"].get_slice(" ", 0)
		if not fams.has(f):
			fams[f] = {}
		fams[f][w["slot_size"]] = w["path"]
	var fits: Array = fams.keys().filter(func(f: String) -> bool:
		return mech_def.weapon_slots.all(func(sl) -> bool: return fams[f].has(sl.slot_size)))
	if fits.is_empty():
		return mech_def.weapon_slots.map(func(_sl) -> String: return "")
	var fam: Dictionary = fams[fits[rng.randi() % fits.size()]]
	return mech_def.weapon_slots.map(func(sl) -> String: return fam[sl.slot_size])

func _on_back_pressed() -> void:
	Game.disconnect_mp()
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn")  # T176: squads are set up there
