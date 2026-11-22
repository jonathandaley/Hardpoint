class_name PlayerInputSource
extends "res://scripts/InputSource.gd"

var _look_delta: Vector2 = Vector2.ZERO
var _wheel := 0.0
const ARROW_STEPS_S := 6.0  # T532: the up / down arrows held = 6 wheel notches a second (no-mouse players)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_delta += event.relative
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_wheel += 1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel -= 1.0

func get_wheel() -> float:
	var w := _wheel
	_wheel = 0.0
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return 0.0
	return w + Input.get_axis("ui_down", "ui_up") * ARROW_STEPS_S / Engine.physics_ticks_per_second

var frozen := false  # T541: orbital targeting -- the mech stops completely

func get_move_direction() -> Vector2:
	if frozen:
		return Vector2.ZERO
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
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	return Input.is_action_pressed("fire_primary")

func is_firing_secondary() -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	return Input.is_action_pressed("fire_secondary")

func get_slot_toggle() -> int:
	for i in range(4):
		if Input.is_action_just_pressed("weapon_slot_%d" % (i + 1)):
			return i
	return -1

func is_reload_pressed() -> bool:
	return Input.is_action_just_pressed("reload")

func is_tracer_toggle_pressed() -> bool:  # T551: T
	return not frozen and Input.is_action_just_pressed("toggle_tracers")

func is_ability_pressed() -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	return Input.is_action_just_pressed("ability_1")


func is_human_input() -> bool:
	return true
