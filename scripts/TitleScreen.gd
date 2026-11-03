extends Control

# T192: a saved local profile counts as signed in (real accounts come with the web
# build): returning pilots get PLAY straight to the hangar; guests get PLAY AS GUEST ->
# callsign (SignIn) -> hangar, with LOG IN / SIGN UP shown disabled until then.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for n in ["LoginButton", "SignupButton", "AccountsNote"]:
		get_node(n).visible = not Game.has_profile
	$PlayButton.text = "PLAY" if Game.has_profile else "PLAY AS GUEST"

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn" if Game.has_profile else "res://scenes/ui/SignIn.tscn")
