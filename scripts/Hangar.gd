extends Control

@onready var mech_panel: Control = $Content/MechPanel
@onready var pilot_panel: Control = $Content/PilotPanel
@onready var pilot_label: Label = $TopBar/PilotLabel
@onready var pilot_name_label: Label = $Content/PilotPanel/PilotName
@onready var pilot_record_label: Label = $Content/PilotPanel/PilotRecord
@onready var mech_name_label: Label = $Content/MechPanel/MechName
@onready var mech_stats_label: Label = $Content/MechPanel/MechStats

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var pilot_name: String = Game.profile.get("pilot_name", "Pilot")
	pilot_label.text = pilot_name
	pilot_name_label.text = "NAME: " + pilot_name.to_upper()
	var wins: int = Game.profile.get("wins", 0)
	var losses: int = Game.profile.get("losses", 0)
	pilot_record_label.text = "WINS: %d   LOSSES: %d" % [wins, losses]
	_ensure_default_mech()
	_update_mech_panel()
	_show_tab(0)

func _ensure_default_mech() -> void:
	if Game.loadout.get("mech_def") == null:
		Game.loadout.mech_def = load("res://resources/mechs/Hippogriff.tres")

func _update_mech_panel() -> void:
	var md: MechDef = Game.loadout.get("mech_def")
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
