extends Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_singleplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/SignIn.tscn")

func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MPEntry.tscn")
