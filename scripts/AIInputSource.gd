class_name AIInputSource
extends "res://scripts/InputSource.gd"
# Stub AI — wanders randomly, fires occasionally. Stage 3 replaces this.

var _wander_direction: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _fire_timer: float = 0.0
var _wants_fire: bool = false

func _process(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(2.0, 5.0)
		var angle := randf() * TAU
		_wander_direction = Vector2(cos(angle), sin(angle))

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = randf_range(1.5, 4.0)
		_wants_fire = true
	else:
		_wants_fire = false

func get_move_direction() -> Vector2:
	return _wander_direction

func is_firing_primary() -> bool:
	return _wants_fire
