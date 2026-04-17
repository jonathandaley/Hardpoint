extends Control

const ROSTER: Array = [
	"res://resources/mechs/Lynx.tres",
	"res://resources/mechs/Hippogriff.tres",
	"res://resources/mechs/Warhog.tres",
]

@onready var mech_panel: Control = $Content/MechPanel
@onready var pilot_panel: Control = $Content/PilotPanel
@onready var pilot_label: Label = $TopBar/PilotLabel
@onready var pilot_name_label: Label = $Content/PilotPanel/PilotName
@onready var pilot_record_label: Label = $Content/PilotPanel/PilotRecord
@onready var mech_name_label: Label = $Content/MechPanel/MechName
@onready var mech_stats_label: Label = $Content/MechPanel/MechStats
@onready var roster_list: VBoxContainer = $Content/MechPanel/RosterPanel/RosterList

var _mechs: Array = []
var _selected: int = 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var pilot_name: String = Game.profile.get("pilot_name", "Pilot")
	pilot_label.text = pilot_name
	pilot_name_label.text = "NAME: " + pilot_name.to_upper()
	var wins: int = Game.profile.get("wins", 0)
	var losses: int = Game.profile.get("losses", 0)
	pilot_record_label.text = "WINS: %d   LOSSES: %d" % [wins, losses]
	_load_roster()
	_ensure_default_mech()
	_build_roster_buttons()
	_update_mech_panel()
	_show_tab(0)

func _load_roster() -> void:
	_mechs.clear()
	for path in ROSTER:
		var md = load(path)
		if md != null:
			_mechs.append(md)
		else:
			push_error("[Hangar] Failed to load MechDef: " + path)

func _ensure_default_mech() -> void:
	var current = Game.loadout.get("mech_def")
	if current == null:
		# Default to Hippogriff (index 1)
		_selected = 1 if _mechs.size() > 1 else 0
		if _mechs.size() > 0:
			Game.loadout.mech_def = _mechs[_selected]
	else:
		# Match current selection to roster index
		for i in _mechs.size():
			if _mechs[i] == current:
				_selected = i
				return
		# Current mech not in roster — fall back to first
		_selected = 0
		if _mechs.size() > 0:
			Game.loadout.mech_def = _mechs[0]

func _build_roster_buttons() -> void:
	for child in roster_list.get_children():
		child.queue_free()
	for i in _mechs.size():
		var md = _mechs[i]
		var btn := Button.new()
		btn.text = "%s\n%s" % [md.display_name.to_upper(), md.class_tag.to_upper()]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_roster_selected.bind(i))
		roster_list.add_child(btn)
	_highlight_selected()

func _highlight_selected() -> void:
	var buttons := roster_list.get_children()
	for i in buttons.size():
		var btn: Button = buttons[i]
		if i == _selected:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			btn.remove_theme_color_override("font_color")

func _on_roster_selected(idx: int) -> void:
	_selected = idx
	Game.loadout.mech_def = _mechs[idx]
	_highlight_selected()
	_update_mech_panel()

func _update_mech_panel() -> void:
	var md = Game.loadout.get("mech_def")
	if md == null:
		return
	mech_name_label.text = "MECH: %s (%s)" % [md.display_name.to_upper(), md.class_tag.to_upper()]
	var shield_str := "YES" if md.has_shields else "—"
	mech_stats_label.text = "SPEED: %.2f   HEALTH: %.0f   SHIELDS: %s" % [md.walk_speed, md.max_health, shield_str]

func _show_tab(idx: int) -> void:
	mech_panel.visible = idx == 0
	pilot_panel.visible = idx == 1

func _on_mech_tab_pressed() -> void:
	_show_tab(0)

func _on_pilot_tab_pressed() -> void:
	_show_tab(1)

func _on_matchmaking_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/arena/Arena.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/Settings.tscn")
