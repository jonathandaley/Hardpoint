class_name InputSource
extends Node
# Abstract base. Swap this to switch between keyboard, AI, or network control.

func get_move_direction() -> Vector2:
	return Vector2.ZERO

func get_look_delta() -> Vector2:
	return Vector2.ZERO

func is_firing_primary() -> bool:
	return false

func is_firing_secondary() -> bool:
	return false

# Returns 0-based slot index to toggle, or -1 if no toggle this frame.
func get_slot_toggle() -> int:
	return -1

func is_reload_pressed() -> bool:
	return false

func is_human_input() -> bool:
	return false
