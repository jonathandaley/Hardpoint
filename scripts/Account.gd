extends Control
# T207: LOG IN / SIGN UP against a dedicated server's account endpoint (Game.account_request).
# Mode from Game.account_mode ("login" | "signup"). Success -> signed in -> Hangar.

var _fields := {}
var _status: Label
var _go: Button

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var signup: bool = Game.get("account_mode") == "signup"
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# T306 (HUMAN_FOUND 2026-11-05: "Sign up screen isn't scrollable, so ... you have to exit the
	# game to leave the screen"): the sign-up column (4 fields) ran past the 360 px screen and
	# took BACK with it. Now the form scrolls and BACK is pinned top-left. The SERVER field
	# ("what is that for?") picks which game server holds the account -- not something players
	# should need -- so it hides behind a small SERVER... toggle with the default filled in.
	var back := Button.new()
	back.name = "BackButton"
	back.text = "< BACK"
	back.position = Vector2(8, 8)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn"))
	add_child(back)
	var scroll := ScrollContainer.new()
	scroll.name = "FormScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 40.0
	scroll.offset_bottom = -8.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.name = "Form"
	box.custom_minimum_size = Vector2(280, 0)
	center.add_child(box)
	var head := Label.new()
	head.text = "SIGN UP" if signup else "LOG IN"
	head.add_theme_font_size_override("font_size", 22)
	box.add_child(head)
	var rows := [["email", "EMAIL", ""], ["password", "PASSWORD (8+ characters)" if signup else "PASSWORD", ""]]
	if signup:
		rows.append(["callsign", "CALLSIGN", ""])
	rows.append(["server", "SERVER (address:port)", "127.0.0.1:8910"])
	var server_nodes: Array = []
	for r in rows:
		if r[0] == "server":
			var toggle := Button.new()
			toggle.name = "ServerToggle"
			toggle.text = "SERVER..."
			toggle.flat = true
			toggle.add_theme_font_size_override("font_size", 11)
			toggle.pressed.connect(func() -> void:
				for n in server_nodes:
					n.visible = not n.visible)
			box.add_child(toggle)
		var lbl := Label.new()
		lbl.text = r[1]
		box.add_child(lbl)
		var e := LineEdit.new()
		e.name = String(r[0]).capitalize() + "Edit"
		e.text = r[2]
		e.secret = r[0] == "password"
		box.add_child(e)
		_fields[r[0]] = e
		if r[0] == "server":
			server_nodes.append_array([lbl, e])  # in place: the toggle's lambda holds this array
			lbl.visible = false
			e.visible = false
	_go = Button.new()
	_go.name = "ConfirmButton"
	_go.text = "CREATE ACCOUNT" if signup else "LOG IN"
	_go.pressed.connect(_on_confirm)
	box.add_child(_go)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)

func _on_confirm() -> void:
	var addr: String = _fields["server"].text.strip_edges()
	var host_addr := addr.get_slice(":", 0)
	var port := int(addr.get_slice(":", 1)) if addr.contains(":") and addr.get_slice(":", 1).is_valid_int() else 8910
	var req := {"op": Game.get("account_mode"), "email": _fields["email"].text.strip_edges(),
		"password": _fields["password"].text}
	if _fields.has("callsign"):
		req["callsign"] = _fields["callsign"].text.strip_edges()
	_go.disabled = true
	_status.text = "CONNECTING..."
	var reply: Dictionary = await Game.account_request(host_addr, port, req)
	_fields["password"].text = ""  # never keep it around
	if not is_inside_tree():
		return
	_go.disabled = false
	if not reply.get("ok", false):
		_status.text = String(reply.get("error", "failed")).to_upper()
		return
	Game.sign_in(host_addr, port, req["email"].to_lower(), reply)
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn")
