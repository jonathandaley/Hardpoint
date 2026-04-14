class_name BeaconMatch
extends "res://scripts/Match.gd"
# Drain model: both teams start at score_limit (1000).
# Each tick the team holding fewer beacons loses points.
# First to 0 loses.

@export var score_tick_rate: float = 1.0   # seconds between drain ticks
@export var points_per_tick: int = 10

var beacons: Array = []
var _tick_timer: float = 0.0

func start() -> void:
	super.start()
	scores = [score_limit, score_limit]

func register_beacon(beacon: Node) -> void:
	beacons.append(beacon)
	beacon.captured.connect(_on_beacon_captured)

func _tick(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < score_tick_rate:
		return
	_tick_timer -= score_tick_rate
	_drain_tick()

func _drain_tick() -> void:
	var a := _count_beacons(0)
	var b := _count_beacons(1)
	if a == b:
		return
	if a > b:
		scores[1] = max(0, scores[1] - points_per_tick * (a - b))
	else:
		scores[0] = max(0, scores[0] - points_per_tick * (b - a))
	print("[Match] Scores  A:%d  B:%d  |  Beacons  A:%d  B:%d  neutral:%d" % [
		scores[0], scores[1], a, b, beacons.size() - a - b
	])

func _check_win() -> void:
	for i in scores.size():
		if scores[i] <= 0:
			_end_match(1 - i)
			return

func _count_beacons(team: int) -> int:
	var n := 0
	for b in beacons:
		if b.owner_team == team:
			n += 1
	return n

func _on_beacon_captured(new_team: int) -> void:
	print("[Match] Beacon captured by team %d  |  A:%d  B:%d  neutral:%d" % [
		new_team, _count_beacons(0), _count_beacons(1),
		beacons.size() - _count_beacons(0) - _count_beacons(1)
	])
