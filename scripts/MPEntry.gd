extends Control

@onready var _port_edit: LineEdit = $TabContainer/Host/PortEdit
@onready var _ip_edit: LineEdit = $TabContainer/Join/IPEdit
@onready var _join_port_edit: LineEdit = $TabContainer/Join/JoinPortEdit
@onready var _join_button: Button = $TabContainer/Join/JoinButton
@onready var _error_label: Label = $ErrorLabel

var _lan: LanDiscovery = null
var _lan_list: VBoxContainer = null
var _lan_check: CheckBox = null

func _ready() -> void:
	Game.set_mouse_captured(false)
	_build_lan()
	Game.mp_peer_connected.connect(_on_mp_connected)
	Game.mp_join_failed.connect(_on_mp_join_failed)
	($TabContainer as TabContainer).current_tab = Game.mp_entry_tab  # T176
	if not Game.account.is_empty():  # T207: join the server you signed in to
		_ip_edit.text = Game.account["host"]
		_join_port_edit.text = str(Game.account["port"])
	else:  # T266: the official server unless the player types another
		_ip_edit.text = Game.OFFICIAL_HOST
		_join_port_edit.text = str(Game.OFFICIAL_PORT)
	if Game.mp_refused_reason != "":  # T168
		_show_error(Game.mp_refused_reason)
		Game.mp_refused_reason = ""

# T467 (HUMAN_FOUND 2026-11-18: "Multiplayer should have an \"open to LAN\" option, to avoid typing in
# manually"): HOST gets OPEN TO LAN (on by default: the game then says so on the local network,
# LanDiscovery); JOIN lists the games it hears -- a click fills in the address and joins.
func _build_lan() -> void:
	_lan_check = CheckBox.new()
	_lan_check.name = "LanCheck"
	_lan_check.text = "OPEN TO LAN"
	_lan_check.button_pressed = true
	$TabContainer/Host.add_child(_lan_check)
	$TabContainer/Host.move_child(_lan_check, $TabContainer/Host/HostButton.get_index())
	var tab := VBoxContainer.new()  # a tab of its own: the Join tab has no room for a list
	tab.name = "LAN"
	$TabContainer.add_child(tab)
	var head := Label.new()
	head.text = "Games on your network (OPEN TO LAN hosts):"
	head.add_theme_font_size_override("font_size", 13)
	tab.add_child(head)
	var scroll := ScrollContainer.new()  # up to LanDiscovery.MAX_GAMES rows
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_lan_list = VBoxContainer.new()
	_lan_list.name = "LanList"
	_lan_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lan_list)
	_lan = LanDiscovery.new()
	_lan.name = "LanListener"
	add_child(_lan)
	_lan.games_changed.connect(_refresh_lan)
	if not _lan.listen():
		head.text = "Can't listen for LAN games (another game open on this computer?)"
	_refresh_lan()

func _refresh_lan() -> void:
	for c in _lan_list.get_children():
		c.queue_free()
	var tabs := $TabContainer as TabContainer
	tabs.set_tab_title(tabs.get_tab_count() - 1, "LAN (%d)" % _lan.games.size() if not _lan.games.is_empty() else "LAN")
	if _lan.games.is_empty():
		var none := Label.new()
		none.text = "none found yet -- the host ticks OPEN TO LAN"
		none.modulate = Color(1, 1, 1, 0.5)
		_lan_list.add_child(none)
		return
	for key in _lan.games:
		var g: Dictionary = _lan.games[key]
		var b := Button.new()
		b.text = "%s  %s  %d/%d" % [g["name"], g["map"], g["players"], g["max"]]
		if int(g["v"]) != Game.NET_VERSION:
			b.text += "  (other version)"
			b.disabled = true
		b.pressed.connect(func() -> void:
			_ip_edit.text = String(g["ip"])
			_join_port_edit.text = str(g["port"])
			_on_join_pressed())
		_lan_list.add_child(b)

func _on_host_pressed() -> void:
	var port := int(_port_edit.text) if _port_edit.text.is_valid_int() else 8910
	Game.lan_open = _lan_check.button_pressed
	Game.host(port)
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")

func _on_join_pressed() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip.is_empty():
		_show_error("Enter a server address")
		return
	var port := int(_join_port_edit.text) if _join_port_edit.text.is_valid_int() else 8910
	_join_button.disabled = true
	_error_label.visible = false
	Game.join(ip, port)

# B86: a joiner also hears about the clients already on the server (relayed
# peer_connected), often in the same poll as the server itself; the first one changed
# scene and the next ran on a node already out of the tree (get_tree() null).
func _on_mp_connected(id: int) -> void:
	if id != 1 or not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")

func _on_mp_join_failed() -> void:
	_join_button.disabled = false
	_show_error(Game.account_notice if Game.account_notice != "" else "Connection failed")  # T403
	Game.account_notice = ""

func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true

func _on_back_pressed() -> void:
	Game.disconnect_mp()
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn")  # T176: came from FIND MATCH
