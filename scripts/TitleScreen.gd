extends Control

# T192: a saved local profile counts as signed in (real accounts come with the web
# build): returning pilots get PLAY straight to the hangar; guests get PLAY AS GUEST ->
# callsign (SignIn) -> hangar, with LOG IN / SIGN UP shown disabled until then.
# T207: LOG IN / SIGN UP are live (accounts on a dedicated server); signed in, the note
# names the account and LOG IN becomes LOG OUT.
func _ready() -> void:
	Game.set_mouse_captured(false)
	var signed_in: bool = not Game.account.is_empty()
	for n in ["LoginButton", "SignupButton"]:
		(get_node(n) as Button).disabled = false
	$SignupButton.visible = not signed_in
	$LoginButton.text = "LOG OUT" if signed_in else "LOG IN"
	$AccountsNote.text = ("SIGNED IN AS %s" % String(Game.account["email"]).to_upper()) if signed_in \
		else "ACCOUNTS LIVE ON DEDICATED SERVERS"
	if OS.has_feature("web"):  # T420: the browser build is single player until T422 (no ENet there)
		for n in ["LoginButton", "SignupButton", "AccountsNote"]:
			get_node(n).visible = false
	$PlayButton.text = "PLAY" if Game.has_profile or signed_in else "PLAY AS GUEST"

func _on_play_pressed() -> void:
	var to_hangar: bool = Game.has_profile or not Game.account.is_empty()
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn" if to_hangar else "res://scenes/ui/SignIn.tscn")

func _on_login_pressed() -> void:
	if not Game.account.is_empty():
		Game.sign_out()
		_ready()
		return
	Game.account_mode = "login"
	get_tree().change_scene_to_file("res://scenes/ui/Account.tscn")

func _on_signup_pressed() -> void:
	Game.account_mode = "signup"
	get_tree().change_scene_to_file("res://scenes/ui/Account.tscn")
