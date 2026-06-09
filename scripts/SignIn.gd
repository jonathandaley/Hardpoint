extends Control

@onready var name_edit: LineEdit = $NameEdit

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var existing: String = Game.profile.get("pilot_name", "")
	if existing != "Pilot":
		name_edit.text = existing
	name_edit.grab_focus()
	name_edit.text_submitted.connect(_on_submitted)

func _on_confirm_pressed() -> void:
	_confirm()

func _on_submitted(_text: String) -> void:
	_confirm()

func _confirm() -> void:
	var n: String = name_edit.text.strip_edges()
	if n.is_empty():
		n = "Pilot"
	Game.profile["pilot_name"] = n
	Game.save_profile()
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn")
