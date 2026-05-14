class_name Pilot
extends Node
# Small data object on Player. Applies stat modifiers to the possessed pawn.

@export var pilot_name: String = "Unknown"

var _pawn: Node = null

func attach_to_pawn(pawn: Node) -> void:
	_pawn = pawn

func detach_from_pawn() -> void:
	_pawn = null
