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

func _on_host_pressed() -> void:
	var port := int(_port_edit.text) if _port_edit.text.is_valid_int() else 8910
	Game.host(port)
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")

func _on_join_pressed() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip.is_empty():
		_show_error("Enter a server IP")
		return
	var port := int(_join_port_edit.text) if _join_port_edit.text.is_valid_int() else 8910
	_join_button.disabled = true
	_error_label.visible = false
	Game.join(ip, port)

func _on_mp_connected(_id: int) -> void:
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")

func _on_mp_join_failed() -> void:
	_join_button.disabled = false
	_show_error("Connection failed")

func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true

func _on_back_pressed() -> void:
	Game.disconnect_mp()
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
