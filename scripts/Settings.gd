extends Control

@onready var sens_slider: HSlider = $Scroll/Content/SensRow/SensSlider
@onready var sens_label:  Label   = $Scroll/Content/SensRow/SensValue

const DIFF_LABELS := ["EASY", "NORMAL", "MEDIUM", "HARD", "ELITE"]

var _diff_buttons: Array = []

func _ready() -> void:
	Game.set_mouse_captured(false)

	sens_slider.set_block_signals(true)
	sens_slider.min_value = 0.001
	sens_slider.max_value = 0.010
	sens_slider.step      = 0.0005
	sens_slider.value     = Game.settings.get("mouse_sensitivity", 0.003)
	sens_slider.set_block_signals(false)
	_update_sens_label()

	var diff_row: HBoxContainer = $Scroll/Content/DiffRow/DiffButtons
	var cur_diff: int = Game.settings.get("bot_difficulty", 1)
	for i in DIFF_LABELS.size():
		var btn := Button.new()
		btn.text = DIFF_LABELS[i]
		btn.custom_minimum_size = Vector2(80, 24)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_diff_pressed.bind(i))
		diff_row.add_child(btn)
		_diff_buttons.append(btn)
	_highlight_diff(cur_diff)
	_build_view_section()
	_build_controls_section()
	_build_toggle_section($Scroll/Content, "RECORD MATCHES (FOR BUG REPORTS)", "record_matches", "Record")  # T389
	_build_graphics_page()  # T253: SHADOWS (and the later graphics toggles) live there
	_build_audio_page()  # T433

# T252: VIEW -- CENTER (raised camera, crosshair over the mech; default) or SHOULDER
# (T196's over-the-shoulder, V swaps sides).
const VIEW_MODES := [["center", "CENTER"], ["shoulder", "SHOULDER"]]
var _view_buttons: Array = []

func _build_view_section() -> void:
	var content: VBoxContainer = $Scroll/Content
	var section_lbl := Label.new()
	section_lbl.text = "VIEW"
	section_lbl.add_theme_font_size_override("font_size", 14)
	content.add_child(section_lbl)
	var row := HBoxContainer.new()
	row.name = "ViewRow"
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	for mode in VIEW_MODES:
		var btn := Button.new()
		btn.name = "View_" + mode[0]
		btn.text = mode[1]
		btn.custom_minimum_size = Vector2(80, 24)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_view_pressed.bind(mode[0]))
		row.add_child(btn)
		_view_buttons.append(btn)
	_highlight_view()

func _on_view_pressed(mode: String) -> void:
	Game.settings["view"] = mode
	Game.shoulder = 0.0 if mode == "center" else 1.0
	Game.save_settings()
	_highlight_view()

func _highlight_view() -> void:
	for i in _view_buttons.size():
		var btn: Button = _view_buttons[i]
		if VIEW_MODES[i][0] == Game.settings.get("view", "center"):
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			btn.remove_theme_color_override("font_color")

func _update_sens_label() -> void:
	sens_label.text = "%.4f" % sens_slider.value


func _on_sens_changed(value: float) -> void:
	Game.settings["mouse_sensitivity"] = value
	_update_sens_label()
	Game.save_settings()

func _build_controls_section() -> void:
	var content: VBoxContainer = $Scroll/Content

	const BINDINGS: Array = [
		["W A S D", "Move"],
		["Mouse", "Look"],
		["LMB", "Fire all weapons"],
		["RMB", "Fire selected weapon"],
		["1 2 3 4", "Toggle weapon slot"],
		["R", "Reload"],
		["Space", "Ability"],
		["V", "Swap shoulder (shoulder view)"],
		["Tab", "Cycle spectate target"],
		["Esc", "Release mouse / pause"],
	]

	# Controls page - hidden until button pressed, covers full screen.
	var controls_page := Control.new()
	controls_page.name = "ControlsPage"
	controls_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls_page.visible = false
	add_child(controls_page)

	var bg := $Background.duplicate()
	controls_page.add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.offset_left   = 0.0
	scroll.offset_top    = 32.0
	scroll.offset_right  = 640.0
	scroll.offset_bottom = 306.0
	controls_page.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.offset_left  = 24.0
	vbox.offset_top   = 12.0
	vbox.offset_right = 616.0
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	for pair in BINDINGS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		vbox.add_child(row)
		var key_lbl := Label.new()
		key_lbl.text = pair[0]
		key_lbl.add_theme_font_size_override("font_size", 13)
		key_lbl.custom_minimum_size = Vector2(100, 0)
		key_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		row.add_child(key_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = pair[1]
		desc_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(desc_lbl)

	var back_btn := Button.new()
	back_btn.offset_left   = 200.0
	back_btn.offset_top    = 316.0
	back_btn.offset_right  = 440.0
	back_btn.offset_bottom = 348.0
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.text = "BACK"
	back_btn.pressed.connect(func():
		controls_page.visible = false
		$Scroll.visible = true
		$BackButton.visible = true
	)
	controls_page.add_child(back_btn)

	var btn_row := HBoxContainer.new()
	btn_row.name = "PageButtons"  # T253: GRAPHICS joins CONTROLS here
	btn_row.add_theme_constant_override("separation", 8)
	content.add_child(btn_row)
	var btn := Button.new()
	btn.text = "CONTROLS"
	btn.custom_minimum_size = Vector2(80, 24)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func():
		$Scroll.visible = false
		$BackButton.visible = false
		controls_page.visible = true
	)
	btn_row.add_child(btn)

# T253 (HUMAN_FOUND_ISSUES 2026-11-05: "graphics toggles in general", "graphics might need
# a dedicated page in settings"): a GRAPHICS page like CONTROLS. SHADOWS moved here; the
# graphics toggles of later tasks (fancy hangar, emissive patterns, effect detail) add
# their own sections to graphics_box.
var graphics_box: VBoxContainer = null

func _build_graphics_page() -> void:
	graphics_box = _build_page("Graphics", "GRAPHICS")
	_build_toggle_section(graphics_box, "FANCY HANGAR", "fancy_hangar", "Fancy")  # T254
	_build_toggle_section(graphics_box, "AMBIENT EFFECTS", "map_effects", "MapFx")  # T446: Swamp's fireflies (not "MAP ...": probe sp_map_pick)
	_build_toggle_section(graphics_box, "CAMERA SHAKE", "camera_shake", "Shake")  # T478: recoil + stomp
	_build_toggle_section(graphics_box, "LONG-LASTING CASINGS", "casings_long", "Casings")  # T263: 1000 / 150
	# T428: lower = faster on a weak graphics card, blurrier 3D; the HUD stays sharp
	_build_choice_section(graphics_box, "RESOLUTION (IN MATCH)", "render_scale", "Res",
		[[1.0, "100%"], [0.75, "75%"], [0.5, "50%"]], 1.0)

# T433: AUDIO -- a volume slider per bus (Game.VOLUME_BUSES); master moved here from the main page.
func _build_audio_page() -> void:
	var box := _build_page("Audio", "AUDIO")
	for bv in Game.VOLUME_BUSES:
		var row := HBoxContainer.new()
		row.name = "Vol" + bv[0]
		row.add_theme_constant_override("separation", 12)
		var lbl := Label.new()
		lbl.text = bv[2]
		lbl.custom_minimum_size = Vector2(110, 0)
		lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(lbl)
		var sl := HSlider.new()
		sl.name = "Slider"
		sl.custom_minimum_size = Vector2(260, 20)
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Game.settings.get(bv[1], 1.0))
		row.add_child(sl)
		var val := Label.new()
		val.text = "%d%%" % roundi(sl.value * 100.0)
		val.add_theme_font_size_override("font_size", 14)
		row.add_child(val)
		sl.value_changed.connect(func(v: float) -> void:
			Game.settings[bv[1]] = v
			Game.apply_volumes()
			Game.save_settings()
			val.text = "%d%%" % roundi(v * 100.0))
		box.add_child(row)

## A sub-page of Settings (`<name>Page`, opened by `<name>Button` next to CONTROLS); returns its box.
func _build_page(pname: String, title_text: String) -> VBoxContainer:
	var page := Control.new()
	page.name = pname + "Page"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.visible = false
	add_child(page)
	page.add_child($Background.duplicate())
	var scroll := ScrollContainer.new()
	scroll.offset_top = 32.0
	scroll.offset_right = 640.0
	scroll.offset_bottom = 306.0
	page.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = pname + "Box"
	box.offset_left = 24.0
	box.offset_top = 12.0
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var back := Button.new()
	back.offset_left = 200.0
	back.offset_top = 316.0
	back.offset_right = 440.0
	back.offset_bottom = 348.0
	back.add_theme_font_size_override("font_size", 20)
	back.text = "BACK"
	back.pressed.connect(func():
		page.visible = false
		$Scroll.visible = true
		$BackButton.visible = true)
	page.add_child(back)
	var open := Button.new()
	open.name = pname + "Button"
	open.text = title_text
	open.custom_minimum_size = Vector2(80, 24)
	open.add_theme_font_size_override("font_size", 14)
	open.pressed.connect(func():
		$Scroll.visible = false
		$BackButton.visible = false
		page.visible = true)
	$Scroll/Content/PageButtons.add_child(open)
	return box

# An ON / OFF row for a boolean Game.settings key (graphics toggles: T254 ...).
func _build_toggle_section(box: VBoxContainer, title: String, key: String, prefix: String) -> void:
	_build_choice_section(box, title, key, prefix, [[true, "ON"], [false, "OFF"]], true)

## One row of choice buttons for Game.settings[key]; the chosen one is yellow.
## Button names: <prefix>_on / _off for ON / OFF, else <prefix>_<label without %>.
func _build_choice_section(box: VBoxContainer, title: String, key: String, prefix: String,
		options: Array, default: Variant) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 14)
	box.add_child(lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var buttons: Array = []
	for v in options:
		var btn := Button.new()
		btn.name = "%s_%s" % [prefix, String(v[1]).to_lower().trim_suffix("%")]
		btn.text = v[1]
		btn.custom_minimum_size = Vector2(80, 24)
		btn.add_theme_font_size_override("font_size", 14)
		row.add_child(btn)
		buttons.append([btn, v[0]])
	var paint := func() -> void:
		for b in buttons:
			if Game.settings.get(key, default) == b[1]:
				(b[0] as Button).add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
			else:
				(b[0] as Button).remove_theme_color_override("font_color")
	for b in buttons:
		(b[0] as Button).pressed.connect(func() -> void:
			Game.settings[key] = b[1]
			Game.save_settings()
			paint.call())
	paint.call()

func _on_diff_pressed(idx: int) -> void:
	Game.settings["bot_difficulty"] = idx
	_highlight_diff(idx)
	Game.save_settings()

func _highlight_diff(idx: int) -> void:
	for i in _diff_buttons.size():
		var btn: Button = _diff_buttons[i]
		if i == idx:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			btn.remove_theme_color_override("font_color")

func _on_back_pressed() -> void:
	Game.save_settings()
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn")
