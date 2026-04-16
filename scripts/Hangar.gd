extends Control

@onready var mech_panel: Control = $Content/MechPanel
@onready var pilot_panel: Control = $Content/PilotPanel
@onready var pilot_label: Label = $TopBar/PilotLabel
@onready var pilot_name_label: Label = $Content/PilotPanel/PilotName
@onready var pilot_record_label: Label = $Content/PilotPanel/PilotRecord

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var pilot_name: String = Game.profile.get("pilot_name", "Pilot")
	pilot_label.text = pilot_name
	pilot_name_label.text = "NAME: " + pilot_name.to_upper()
	var wins: int = Game.profile.get("wins", 0)
	var losses: int = Game.profile.get("losses", 0)
	pilot_record_label.text = "WINS: %d   LOSSES: %d" % [wins, losses]
	_show_tab(0)

func _show_tab(idx: int) -> void:
	mech_panel.visible = idx == 0
	pilot_panel.visible = idx == 1

func _on_mech_tab_pressed() -> void:
	_show_tab(0)

func _on_pilot_tab_pressed() -> void:
	_show_tab(1)

func _on_matchmaking_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/arena/Arena.tscn")
