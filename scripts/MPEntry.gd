extends Control

@onready var _port_edit: LineEdit = $TabContainer/Host/PortEdit
@onready var _ip_edit: LineEdit = $TabContainer/Join/IPEdit
@onready var _join_port_edit: LineEdit = $TabContainer/Join/JoinPortEdit
@onready var _join_button: Button = $TabContainer/Join/JoinButton
@onready var _error_label: Label = $ErrorLabel

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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

func _on_host_pressed() -> void:
	var port := int(_port_edit.text) if _port_edit.text.is_valid_int() else 8910
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
