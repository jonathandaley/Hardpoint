extends CanvasLayer

@onready var health_label: Label = $HealthLabel
@onready var score_label: Label = $ScoreLabel

var _match: Node = null
var _player_mech: Node = null

func setup(match_node: Node, player_mech: Node) -> void:
	_match = match_node
	_player_mech = player_mech

func _process(_delta: float) -> void:
	if _player_mech != null:
		var hp := _player_mech.get("health") as float
		var max_hp := _player_mech.get("max_health") as float
		if _player_mech.get("health") != null:
			health_label.text = "HP  %d / %d" % [hp, max_hp]

	if _match != null:
		var scores: Array = _match.get("scores")
		score_label.text = "A: %d     B: %d" % [scores[0], scores[1]]
