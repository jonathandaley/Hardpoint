extends Control

@onready var sens_slider: HSlider = $Scroll/Content/SensRow/SensSlider
@onready var sens_label:  Label   = $Scroll/Content/SensRow/SensValue
@onready var vol_slider:  HSlider = $Scroll/Content/VolRow/VolSlider
@onready var vol_label:   Label   = $Scroll/Content/VolRow/VolValue

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

	vol_slider.set_block_signals(true)
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step      = 0.05
	vol_slider.value     = Game.settings.get("master_volume", 0.5)
	vol_slider.set_block_signals(false)
	_update_vol_label()

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

func _update_vol_label() -> void:
	vol_label.text = "%d%%" % int(vol_slider.value * 100.0)

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
	var page := Control.new()
	page.name = "GraphicsPage"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.visible = false
	add_child(page)
	page.add_child($Background.duplicate())
	var scroll := ScrollContainer.new()
	scroll.offset_top = 32.0
	scroll.offset_right = 640.0
	scroll.offset_bottom = 306.0
	page.add_child(scroll)
	graphics_box = VBoxContainer.new()
	graphics_box.name = "GraphicsBox"
	graphics_box.offset_left = 24.0
	graphics_box.offset_top = 12.0
	graphics_box.add_theme_constant_override("separation", 8)
	scroll.add_child(graphics_box)
	var title := Label.new()
	title.text = "GRAPHICS"
	title.add_theme_font_size_override("font_size", 18)
	graphics_box.add_child(title)
	_build_toggle_section(graphics_box, "FANCY HANGAR", "fancy_hangar", "Fancy")  # T254
	_build_toggle_section(graphics_box, "LONG-LASTING CASINGS", "casings_long", "Casings")  # T263: 1000 / 150
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
	open.name = "GraphicsButton"
	open.text = "GRAPHICS"
	open.custom_minimum_size = Vector2(80, 24)
	open.add_theme_font_size_override("font_size", 14)
	open.pressed.connect(func():
		$Scroll.visible = false
		$BackButton.visible = false
		page.visible = true)
	$Scroll/Content/PageButtons.add_child(open)

# An ON / OFF row for a boolean Game.settings key (graphics toggles: T254 ...).
func _build_toggle_section(box: VBoxContainer, title: String, key: String, prefix: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 14)
	box.add_child(lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var buttons: Array = []
	for v in [[true, "ON"], [false, "OFF"]]:
		var btn := Button.new()
		btn.name = "%s_%s" % [prefix, "on" if v[0] else "off"]
		btn.text = v[1]
		btn.custom_minimum_size = Vector2(80, 24)
		btn.add_theme_font_size_override("font_size", 14)
		row.add_child(btn)
		buttons.append([btn, v[0]])
	var paint := func() -> void:
		for b in buttons:
			if bool(Game.settings.get(key, true)) == b[1]:
				(b[0] as Button).add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
			else:
				(b[0] as Button).remove_theme_color_override("font_color")
	for b in buttons:
		(b[0] as Button).pressed.connect(func() -> void:
			Game.settings[key] = b[1]
			Game.save_settings()
			paint.call())
	paint.call()

func _on_vol_changed(value: float) -> void:
	Game.settings["master_volume"] = value
	Game.apply_volume(value)
	Game.save_settings()
	_update_vol_label()

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
