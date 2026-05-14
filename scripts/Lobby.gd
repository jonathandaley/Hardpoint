extends Control

const _MAP_OPTIONS: Array = [
	{"name": "Math Temple", "path": "res://resources/maps/MathTemple.tres"},
	{"name": "Badlands",    "path": "res://resources/maps/Badlands.tres"},
	{"name": "Ironworks",   "path": "res://resources/maps/Ironworks.tres"},
]

@onready var _peer_list: VBoxContainer = $PeerList
@onready var _host_controls: VBoxContainer = $HostControls
@onready var _bot_fill_check: CheckBox = $HostControls/BotFillRow/BotFillCheck
@onready var _team_size_spin: SpinBox = $HostControls/TeamSizeRow/TeamSizeSpin
@onready var _map_option: OptionButton = $HostControls/MapRow/MapOption
@onready var _start_button: Button = $StartButton
@onready var _status_label: Label = $StatusLabel

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

	_update_host_controls_visibility()
	_rebuild_peer_list()
	_sync_host_controls_to_lobby()
	_update_start_button()

func _local_peer_meta() -> Dictionary:
	return {
		"pilot_name": Game.profile.get("pilot_name", "Pilot"),
		"elo":        Game.profile.get("elo", 1000),
		"level":      Game.profile.get("level", 1),
		"squad":      Game.loadout.get("squad", []),
		"ready":      false,
	}

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

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	Game.mp_lobby["peers"][id] = {
		"pilot_name": "Peer %d" % id,
		"elo":        1000,
		"level":      1,
		"squad":      [],
		"ready":      false,
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
		var elo_lbl := Label.new()
		elo_lbl.text = "ELO %d" % entry.get("elo", 0)
		elo_lbl.custom_minimum_size.x = 90
		var ready_lbl := Label.new()
		ready_lbl.text = "[RDY]" if entry.get("ready", false) else "[   ]"
		ready_lbl.custom_minimum_size.x = 50
		row.add_child(name_lbl)
		row.add_child(elo_lbl)
		row.add_child(ready_lbl)
		_peer_list.add_child(row)

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

func _on_start_pressed() -> void:
	# T115: match-start RPC + scene transition to Arena
	_status_label.text = "Match start not yet implemented (T115)"

func _on_back_pressed() -> void:
	Game.disconnect_mp()
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
