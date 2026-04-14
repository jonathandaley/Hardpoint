class_name Pilot
extends Node
# Small data object on Player. Applies stat modifiers to the possessed pawn.

@export var pilot_name: String = "Unknown"
@export var walk_speed_modifier: float = 1.0
@export var reload_rate_modifier: float = 1.0

var _pawn: Node = null

func attach_to_pawn(pawn: Node) -> void:
	_pawn = pawn
	if pawn.has_method("apply_modifier"):
		pawn.apply_modifier("walk_speed", walk_speed_modifier)
		pawn.apply_modifier("reload_rate", reload_rate_modifier)

func detach_from_pawn() -> void:
	if _pawn != null and _pawn.has_method("remove_modifier"):
		_pawn.remove_modifier("walk_speed")
		_pawn.remove_modifier("reload_rate")
	_pawn = null
