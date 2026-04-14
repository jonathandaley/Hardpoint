class_name AIInputSource
extends InputSource
# Stub AI — wanders randomly. Stage 3 will replace this with real behaviour.

var _wander_direction: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0

func _process(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(2.0, 5.0)
		var angle := randf() * TAU
		_wander_direction = Vector2(cos(angle), sin(angle))

func get_move_direction() -> Vector2:
	return _wander_direction
