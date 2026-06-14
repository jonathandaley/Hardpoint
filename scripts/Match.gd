class_name Match
extends Node
# Base match. Subclasses implement _tick() and override _check_win() as needed.

signal match_ended(winning_team: int)

@export var score_limit: int = 1000
@export var time_limit: float = 0.0  # 0 = no time limit

var scores: Array[int] = [0, 0]  # team 0, team 1
var elapsed: float = 0.0
var running: bool = false

var match_seed: int = 0  # T104: deterministic bot RNG seed broadcast at start

func start() -> void:
	scores = [0, 0]
	elapsed = 0.0
	running = true
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		match_seed = randi()
		Game.seed_rng(match_seed)  # M0.1: central gameplay RNG
		_rpc_set_match_seed.rpc(match_seed)
		_apply_bot_seeds()

func stop() -> void:
	running = false

func _process(delta: float) -> void:
	if not running:
		return
	# T40: match simulation runs server-only; clients receive result via _rpc_match_ended.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	elapsed += delta
	_tick(delta)
	_check_win()

func _tick(_delta: float) -> void:
	pass

func _check_win() -> void:
	for i in scores.size():
		if score_limit > 0 and scores[i] >= score_limit:
			_end_match(i)
			return
	if time_limit > 0.0 and elapsed >= time_limit:
		_end_match(0 if scores[0] >= scores[1] else 1)

func force_end(winning_team: int) -> void:
	_end_match(winning_team)

func _end_match(winning_team: int) -> void:
	running = false
	match_ended.emit(winning_team)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_match_ended.rpc(winning_team)

# T40: server tells all clients the match result so they can show the end screen.
@rpc("authority", "reliable")
func _rpc_match_ended(winning_team: int) -> void:
	running = false
	match_ended.emit(winning_team)

func on_player_eliminated(_player: Node) -> void:
	pass

# T104: server broadcasts match_seed so client bot RNG matches server.
@rpc("authority", "reliable")
func _rpc_set_match_seed(seed: int) -> void:
	match_seed = seed
	Game.seed_rng(match_seed)  # M0.1: central gameplay RNG (mirror server)
	_apply_bot_seeds()

func _apply_bot_seeds() -> void:
	for ai in get_tree().get_nodes_in_group("ai_input_sources"):
		if ai.has_method("set_mp_seed") and "bot_id" in ai:
			ai.set_mp_seed(ai.bot_id ^ match_seed)
