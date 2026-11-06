extends Node
# T306 probe (HUMAN_FOUND 2026-11-05: "Sign up screen isn't scrollable, so currently makes it so
# you have to exit the game to leave the screen" + the "server" field question): on the SIGN UP
# screen BACK is fully on the 640x360 screen, CREATE ACCOUNT is on screen or reachable by
# scrolling, and the SERVER field is hidden until its toggle is pressed.

func _ready() -> void:
	Game.set("account_mode", "signup")
	var a: Control = load("res://scenes/ui/Account.tscn").instantiate()
	add_child(a)
	for i in 3:
		await get_tree().process_frame
	var screen := Rect2(Vector2.ZERO, Vector2(640, 360))
	var bad: Array = []
	var back := a.find_child("BackButton", true, false) as Control
	if back == null or not screen.encloses(back.get_global_rect()):
		bad.append("BACK is off the screen (%s)" % (back.get_global_rect() if back != null else "missing"))
	var go := a.find_child("ConfirmButton", true, false) as Control
	var scroll := a.find_child("FormScroll", true, false) as ScrollContainer
	var reachable := go != null and screen.encloses(go.get_global_rect())
	if not reachable and scroll != null:
		scroll.ensure_control_visible(go)
		for i in 2:
			await get_tree().process_frame
		reachable = screen.encloses(go.get_global_rect())
	if not reachable:
		bad.append("CREATE ACCOUNT can't be reached (%s)" % (go.get_global_rect() if go != null else "missing"))
	var server := a.find_child("ServerEdit", true, false) as Control
	var toggle := a.find_child("ServerToggle", true, false) as Button
	if server == null or server.visible:
		bad.append("SERVER field shown by default")
	elif toggle == null:
		bad.append("no SERVER... toggle")
	else:
		toggle.pressed.emit()
		if not server.visible:
			bad.append("SERVER... toggle doesn't reveal the field")
	if not bad.is_empty():
		push_error("[probe] account_screen FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] account_screen done")
	get_tree().quit(0)
