extends CanvasLayer

@onready var health_label: Label = $HealthLabel
@onready var score_label: Label = $ScoreLabel
@onready var crosshair: Label = $Crosshair
@onready var result_label: Label = $ResultLabel

var _match: Node = null
var _player_mech: Node = null
var _player_team: int = 0

func setup(match_node: Node, player_mech: Node, player_team: int) -> void:
	_match = match_node
	_player_mech = player_mech
	_player_team = player_team

func show_result(winning_team: int) -> void:
	result_label.text = "YOU WIN" if winning_team == _player_team else "YOU LOSE"
	result_label.visible = true
	crosshair.visible = false

func _process(_delta: float) -> void:
	if _player_mech != null and _player_mech.get("health") != null:
		health_label.text = "HP  %d / %d" % [
			_player_mech.get("health"), _player_mech.get("max_health")
		]

	if _match != null:
		var scores: Array = _match.get("scores")
		score_label.text = "A: %d     B: %d" % [scores[0], scores[1]]
