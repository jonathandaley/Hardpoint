class_name Player
extends Node
# Owns a pilot, an input source, and possesses one pawn (mech) at a time.
# Stage 1: 1 life, single mech in hangar.

var input_source: Node = null   # InputSource — untyped to avoid cache dependency
var pilot: Node = null           # Pilot
var pawn: Node = null
var lives: int = 1
var team: int = 0

var hangar: Array[String] = []

func possess(new_pawn: Node) -> void:
	if pawn != null:
		pawn.set_input_source(null)
	pawn = new_pawn
	if pawn == null:
		return
	pawn.set("team", team)
	pawn.set_input_source(input_source)
	if pilot != null:
		pilot.attach_to_pawn(pawn)

func on_pawn_destroyed() -> void:
	if pilot != null:
		pilot.detach_from_pawn()
	pawn = null
	lives -= 1
	if lives <= 0:
		get_parent().on_player_eliminated(self)
