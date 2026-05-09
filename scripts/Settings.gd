extends Control

@onready var sens_slider: HSlider = $Scroll/Content/SensRow/SensSlider
@onready var sens_label:  Label   = $Scroll/Content/SensRow/SensValue
@onready var vol_slider:  HSlider = $Scroll/Content/VolRow/VolSlider
@onready var vol_label:   Label   = $Scroll/Content/VolRow/VolValue

const DIFF_LABELS := ["EASY", "NORMAL", "MEDIUM", "HARD", "ELITE"]
const MAPS: Array = [
	"res://resources/maps/MathTemple.tres",
	"res://resources/maps/Ironworks.tres",
	"res://resources/maps/Badlands.tres",
]

var _diff_buttons: Array = []
var _map_buttons: Array = []
var _selected_map_idx: int = 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	vol_slider.value     = Game.settings.get("master_volume", 1.0)
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
	_build_map_section()
	_build_controls_section()

func _build_map_section() -> void:
	var content: VBoxContainer = $Scroll/Content
	var section_lbl := Label.new()
	section_lbl.text = "MAP (TESTING)"
	section_lbl.add_theme_font_size_override("font_size", 14)
	content.add_child(section_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)

	var current_map = Game.loadout.get("map_def")
	for i in MAPS.size():
		var md = load(MAPS[i])
		if md == null:
			continue
		if current_map != null and md.map_name == current_map.map_name:
			_selected_map_idx = i
		var btn := Button.new()
		btn.text = md.map_name.to_upper()
		btn.custom_minimum_size = Vector2(120, 28)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_map_pressed.bind(i))
		row.add_child(btn)
		_map_buttons.append(btn)

	if Game.loadout.get("map_def") == null and MAPS.size() > 0:
		Game.loadout["map_def"] = load(MAPS[0])
	_highlight_map(_selected_map_idx)

func _on_map_pressed(idx: int) -> void:
	_selected_map_idx = idx
	var md = load(MAPS[idx])
	Game.loadout["map_def"] = md
	Game.save_loadout()
	_highlight_map(idx)

func _highlight_map(idx: int) -> void:
	for i in _map_buttons.size():
		var btn: Button = _map_buttons[i]
		if i == idx:
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
	var section_lbl := Label.new()
	section_lbl.text = "CONTROLS"
	section_lbl.add_theme_font_size_override("font_size", 14)
	content.add_child(section_lbl)

	const BINDINGS: Array = [
		["W A S D", "Move"],
		["Mouse", "Look"],
		["LMB", "Fire all weapons"],
		["RMB", "Fire selected weapon"],
		["1 2 3 4", "Toggle weapon slot"],
		["R", "Reload"],
		["Q", "Ability"],
		["Tab", "Cycle spectate target"],
		["Esc", "Release mouse / pause"],
	]
	for pair in BINDINGS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		content.add_child(row)
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
