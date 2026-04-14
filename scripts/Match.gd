class_name Match
extends Node
# Base match. Subclasses implement _tick() and override _check_win() as needed.

signal match_ended(winning_team: int)

@export var score_limit: int = 1000
@export var time_limit: float = 0.0  # 0 = no time limit

var scores: Array[int] = [0, 0]  # team 0, team 1
var elapsed: float = 0.0
var running: bool = false

func start() -> void:
	scores = [0, 0]
	elapsed = 0.0
	running = true

func stop() -> void:
	running = false

func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	_tick(delta)
	_check_win()

func _tick(_delta: float) -> void:
	pass

func _check_win() -> void:
	for i in scores.size():
		if score_limit > 0 and scores[i] >= score_limit:
			_end_match(1 - i)
			return
	if time_limit > 0.0 and elapsed >= time_limit:
		_end_match(0 if scores[0] >= scores[1] else 1)

func _end_match(winning_team: int) -> void:
	running = false
	match_ended.emit(winning_team)

func on_player_eliminated(_player: Player) -> void:
	pass
