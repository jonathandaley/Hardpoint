extends Control

const _MAP_OPTIONS: Array = [
	{"name": "Math Temple", "path": "res://resources/maps/MathTemple.tres"},
	{"name": "Badlands",    "path": "res://resources/maps/Badlands.tres"},
	{"name": "Ironworks",   "path": "res://resources/maps/Ironworks.tres"},
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
@onready var _team_size_spin: SpinBox = $HostControls/TeamSizeRow/TeamSizeSpin
@onready var _map_option: OptionButton = $HostControls/MapRow/MapOption
@onready var _start_button: Button = $StartButton
@onready var _status_label: Label = $StatusLabel
@onready var _ready_btn: Button = $ReadyBtn
@onready var _squad_picker: Control = $SquadPicker
@onready var _slot_rows: VBoxContainer = $SquadPicker/PickerPanel/SlotRows

# Squad picker state: parallel arrays indexed by squad slot (0-4).
var _sq_mech_opts: Array = []    # OptionButton per slot
var _sq_wpn_rows: Array = []     # HBoxContainer per slot (weapon OptionButtons inside)
var _sq_wpn_opts: Array = []     # Array[Array[OptionButton]] - weapon opts per slot
var _sq_mds: Array = []          # loaded MechDef per slot (or null)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.lobby_updated.connect(_on_lobby_updated)
	Game.mp_peer_connected.connect(_on_peer_connected)
	Game.mp_peer_disconnected.connect(_on_peer_disconnected)

	_setup_map_option()

	if multiplayer.is_server():
		Game.mp_lobby = {
			"peers":      {},
			"bot_fill":   true,
			"team_size":  Game.loadout.get("team_size", 1),
			"map_path":   "res://resources/maps/MathTemple.tres",
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

func _build_squad_data() -> Array:
	var squad_paths: Array = Game.loadout.get("squad", [])
	var choices: Dictionary = Game.loadout.get("mech_weapon_choices", {})
	var result: Array = []
	for path in squad_paths:
		result.append({"mech": path, "weapons": choices.get(path, [])})
	while result.size() < 5:
		var fallback: String = ROSTER[0] if ROSTER.size() > 0 else ""
		result.append({"mech": fallback, "weapons": []})
	return result

func _local_peer_meta() -> Dictionary:
	return {
		"pilot_name": Game.profile.get("pilot_name", "Pilot"),
		"elo":        Game.profile.get("elo", 1000),
		"level":      Game.profile.get("level", 1),
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

func _on_squad_btn_pressed() -> void:
	_open_squad_picker()

func _open_squad_picker() -> void:
	_build_slot_rows()
	_squad_picker.visible = true

func _build_slot_rows() -> void:
	for child in _slot_rows.get_children():
		child.queue_free()
	_sq_mech_opts.clear()
	_sq_wpn_rows.clear()
	_sq_wpn_opts.clear()
	_sq_mds.clear()

	var my_id := multiplayer.get_unique_id()
	var my_entry: Dictionary = Game.mp_lobby.get("peers", {}).get(my_id, {})
	var saved_squad: Array = my_entry.get("squad", _build_squad_data())

	for i in 5:
		var saved: Dictionary = saved_squad[i] if i < saved_squad.size() else {}
		_build_slot_row(i, saved)

func _build_slot_row(slot_idx: int, saved: Dictionary) -> void:
	var row := HBoxContainer.new()

	var slot_lbl := Label.new()
	slot_lbl.text = "%d:" % (slot_idx + 1)
	slot_lbl.custom_minimum_size.x = 22
	slot_lbl.add_theme_font_size_override("font_size", 13)

	var mech_opt := OptionButton.new()
	mech_opt.custom_minimum_size.x = 130
	mech_opt.add_theme_font_size_override("font_size", 12)
	for path in ROSTER:
		mech_opt.add_item(_mech_short_name(path))
	var saved_mech: String = str(saved.get("mech", ""))
	var mech_idx: int = ROSTER.find(saved_mech)
	if mech_idx < 0:
		mech_idx = slot_idx % ROSTER.size()
	mech_opt.select(mech_idx)

	var wpn_row := HBoxContainer.new()
	wpn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(slot_lbl)
	row.add_child(mech_opt)
	row.add_child(wpn_row)
	_slot_rows.add_child(row)

	_sq_mech_opts.append(mech_opt)
	_sq_wpn_rows.append(wpn_row)
	_sq_wpn_opts.append([])
	_sq_mds.append(null)

	# Load MechDef and build weapon options.
	_refresh_weapon_opts(slot_idx, ROSTER[mech_idx], saved.get("weapons", []))

	# Bind mech change to refresh weapon options.
	mech_opt.item_selected.connect(func(idx: int) -> void:
		_refresh_weapon_opts(slot_idx, ROSTER[idx], [])
	)

func _refresh_weapon_opts(slot_idx: int, mech_path: String, saved_weapons: Array) -> void:
	var wpn_row: HBoxContainer = _sq_wpn_rows[slot_idx]
	for child in wpn_row.get_children():
		child.queue_free()
	_sq_wpn_opts[slot_idx] = []

	if not ResourceLoader.exists(mech_path):
		return
	var md = ResourceLoader.load(mech_path)
	if md == null or not "weapon_slots" in md:
		return
	_sq_mds[slot_idx] = md

	var slots: Array = md.weapon_slots
	for s_i in slots.size():
		var slot = slots[s_i]
		var s_size: int = slot.slot_size if "slot_size" in slot else 0

		var opt := OptionButton.new()
		opt.custom_minimum_size.x = 100
		opt.add_theme_font_size_override("font_size", 11)

		var saved_path: String = str(saved_weapons[s_i]) if s_i < saved_weapons.size() else ""
		var select_idx := 0
		var item_idx := 0
		for cat in WEAPON_CATALOG:
			if cat["slot_size"] == s_size:
				opt.add_item(cat["name"])
				if cat["path"] == saved_path:
					select_idx = item_idx
				item_idx += 1
		opt.select(select_idx)
		wpn_row.add_child(opt)
		_sq_wpn_opts[slot_idx].append(opt)

func _collect_squad() -> Array:
	var result: Array = []
	for i in 5:
		var mech_path: String = ROSTER[_sq_mech_opts[i].get_selected_id()] \
			if _sq_mech_opts[i].get_selected_id() >= 0 else ROSTER[i % ROSTER.size()]
		var md = _sq_mds[i]
		var weapons: Array = []
		if md != null and "weapon_slots" in md:
			var slots: Array = md.weapon_slots
			var wpn_opts: Array = _sq_wpn_opts[i]
			for s_i in slots.size():
				if s_i >= wpn_opts.size():
					weapons.append("")
					continue
				var slot = slots[s_i]
				var s_size: int = slot.slot_size if "slot_size" in slot else 0
				var opt: OptionButton = wpn_opts[s_i]
				var chosen_idx := 0
				var item_i := 0
				for cat in WEAPON_CATALOG:
					if cat["slot_size"] == s_size:
						if item_i == opt.selected:
							chosen_idx = WEAPON_CATALOG.find(cat)
							break
						item_i += 1
				weapons.append(WEAPON_CATALOG[chosen_idx]["path"] if chosen_idx >= 0 else "")
		result.append({"mech": mech_path, "weapons": weapons})
	return result

func _submit_squad(squad: Array) -> void:
	if multiplayer.is_server():
		Game._apply_squad(multiplayer.get_unique_id(), squad)
	else:
		Game._rpc_set_squad.rpc_id(1, squad)

func _on_squad_confirm() -> void:
	var squad := _collect_squad()
	_submit_squad(squad)
	_squad_picker.visible = false

func _on_squad_cancel() -> void:
	_squad_picker.visible = false

# ---- Match start / back ----

func _on_start_pressed() -> void:
	var roster := _build_roster()
	var match_seed := randi()
	Game.mp_lobby["match_seed"] = match_seed
	var map_path: String = Game.mp_lobby.get("map_path", "res://resources/maps/MathTemple.tres")
	Game._rpc_match_start.rpc(map_path, roster, match_seed)

func _build_roster() -> Array:
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

	# Bot fill: pad each team to team_size (V29: bot_id used for RNG seed).
	if Game.mp_lobby.get("bot_fill", true):
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

	return roster

func _default_bot_squad(bot_id: int) -> Array:
	var mech_path: String = ROSTER[bot_id % ROSTER.size()]
	var result: Array = []
	for _i in 5:
		result.append({"mech": mech_path, "weapons": []})
	return result

func _on_back_pressed() -> void:
	Game.disconnect_mp()
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
