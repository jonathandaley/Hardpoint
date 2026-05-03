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
	var per_beacon := int(points_per_tick * 0.25)   # each captured beacon drains opponent slowly
	if per_beacon < 1:
		per_beacon = 1
	if a > 0:
		scores[1] = max(0, scores[1] - per_beacon * a)
	if b > 0:
		scores[0] = max(0, scores[0] - per_beacon * b)

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
