extends Node
# T249 probe (HUMAN_FOUND_ISSUES 2026-11-05: "Update controls list: V"): every gameplay
# action bound in the InputMap (project.godot) shows its key on the Settings controls page.
# Debug-only binds (DEBUG) are left off.

const DEBUG := ["mark_debug"]

func _fail(msg: String) -> void:
	push_error("[probe] controls_list: " + msg)

func _ready() -> void:
	var st: Node = load("res://scenes/ui/Settings.tscn").instantiate()
	add_child(st)
	await get_tree().process_frame
	var page: Node = st.find_child("ControlsPage", true, false)
	var tokens := {}
	for l in (page.find_children("*", "Label", true, false) if page != null else []):
		for t in (l as Label).text.split(" ", false):
			tokens[t.to_upper()] = true
	var checked := 0
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_") or DEBUG.has(String(action)):
			continue
		for ev in InputMap.action_get_events(action):
			var label := ""
			if ev is InputEventKey:
				var code: int = (ev as InputEventKey).physical_keycode if (ev as InputEventKey).keycode == 0 else (ev as InputEventKey).keycode
				label = OS.get_keycode_string(code)
			elif ev is InputEventMouseButton:
				label = {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB"}.get((ev as InputEventMouseButton).button_index, "")
			if label == "":
				continue
			checked += 1
			if not tokens.has(label.to_upper()):
				_fail("%s is bound to %s but the controls page doesn't list %s" % [action, label, label])
	if checked < 10:
		_fail("only %d bound keys found (controls page or InputMap missing?)" % checked)
	print("[probe] controls_list done (%d binds)" % checked)
	get_tree().quit(0)
