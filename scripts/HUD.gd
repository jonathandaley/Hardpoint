extends CanvasLayer

@onready var health_label: Label = $HealthLabel
@onready var score_label: Label = $ScoreLabel
@onready var crosshair: Control = $Crosshair
@onready var damage_flash: ColorRect = $DamageFlash
@onready var result_label: Label = $ResultLabel
@onready var restart_label: Label = $RestartLabel

var _damage_alpha: float = 0.0

var _match: Node = null
var _player_mech: Node = null
var _player_team: int = 0

func setup(match_node: Node, player_mech: Node, player_team: int) -> void:
	_match = match_node
	_player_mech = player_mech
	_player_team = player_team

func show_damage() -> void:
	_damage_alpha = 0.45

func register_hit() -> void:
	crosshair.register_hit()

func show_result(winning_team: int) -> void:
	result_label.text = "YOU WIN" if winning_team == _player_team else "YOU LOSE"
	result_label.visible = true
	restart_label.visible = true
	crosshair.visible = false

func _process(delta: float) -> void:
	if _damage_alpha > 0.0:
		_damage_alpha = move_toward(_damage_alpha, 0.0, delta * 2.0)
		damage_flash.modulate.a = _damage_alpha
	if _player_mech != null and _player_mech.get("health") != null:
		health_label.text = "HP  %d / %d" % [
			_player_mech.get("health"), _player_mech.get("max_health")
		]

	if _match != null:
		var scores: Array = _match.get("scores")
		score_label.text = "A: %d     B: %d" % [scores[0], scores[1]]
