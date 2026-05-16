class_name NetworkInputSource
extends "res://scripts/InputSource.gd"

# Server-side input buffer for a remote peer's mech.
# T118 _rpc_input handler calls push_input() after sender validation (V41).
# All getters consume one-shot fields on read (matches PlayerInputSource contract).

var _move_dir: Vector2 = Vector2.ZERO
var _look_delta: Vector2 = Vector2.ZERO
var _fire_primary: bool = false
var _fire_secondary: bool = false
var _slot_toggle: int = -1
var _reload: bool = false
var _ability: bool = false

func push_input(payload: Dictionary) -> void:
	_move_dir = payload.get("move", Vector2.ZERO)
	_look_delta += payload.get("look", Vector2.ZERO)
	_fire_primary = payload.get("fire_prim", false)
	_fire_secondary = payload.get("fire_sec", false)
	var st: int = payload.get("slot_toggle", -1)
	if st >= 0:
		_slot_toggle = st
	_reload = _reload or payload.get("reload", false)
	_ability = _ability or payload.get("ability", false)

func get_move_direction() -> Vector2:
	return _move_dir

func get_look_delta() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d

func is_firing_primary() -> bool:
	return _fire_primary

func is_firing_secondary() -> bool:
	return _fire_secondary

func get_slot_toggle() -> int:
	var t := _slot_toggle
	_slot_toggle = -1
	return t

func is_reload_pressed() -> bool:
	var r := _reload
	_reload = false
	return r

func is_ability_pressed() -> bool:
	var a := _ability
	_ability = false
	return a

func is_human_input() -> bool:
	return true
