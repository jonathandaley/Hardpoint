extends Control

@onready var sens_slider: HSlider = $Content/SensRow/SensSlider
@onready var sens_label:  Label   = $Content/SensRow/SensValue
@onready var vol_slider:  HSlider = $Content/VolRow/VolSlider
@onready var vol_label:   Label   = $Content/VolRow/VolValue

const DIFF_LABELS := ["EASY", "NORMAL", "HARD"]

var _diff_buttons: Array = []

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	sens_slider.min_value = 0.001
	sens_slider.max_value = 0.010
	sens_slider.step      = 0.0005
	sens_slider.value     = Game.settings.get("mouse_sensitivity", 0.003)
	_update_sens_label()

	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step      = 0.05
	vol_slider.value     = 1.0
	_update_vol_label()

	var diff_row: HBoxContainer = $Content/DiffRow/DiffButtons
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

func _update_sens_label() -> void:
	sens_label.text = "%.4f" % sens_slider.value

func _update_vol_label() -> void:
	vol_label.text = "%d%%" % int(vol_slider.value * 100.0)

func _on_sens_changed(value: float) -> void:
	Game.settings["mouse_sensitivity"] = value
	_update_sens_label()

func _on_vol_changed(_value: float) -> void:
	_update_vol_label()

func _on_diff_pressed(idx: int) -> void:
	Game.settings["bot_difficulty"] = idx
	_highlight_diff(idx)

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
