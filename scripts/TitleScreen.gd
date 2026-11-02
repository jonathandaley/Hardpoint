extends Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# T176: one way in -- sign in, set the squad up in the hangar, then FIND MATCH picks
# single player / host / join.
func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/SignIn.tscn")
