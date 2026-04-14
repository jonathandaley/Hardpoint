class_name PlayerInputSource
extends "res://scripts/InputSource.gd"

var _look_delta: Vector2 = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_delta += event.relative

func get_move_direction() -> Vector2:
	return Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back")
	)

func get_look_delta() -> Vector2:
	var delta := _look_delta
	_look_delta = Vector2.ZERO
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return Vector2.ZERO
	return delta

func is_firing_primary() -> bool:
	return Input.is_action_pressed("fire_primary")

func is_firing_secondary() -> bool:
	return Input.is_action_pressed("fire_secondary")

func is_human_input() -> bool:
	return true
