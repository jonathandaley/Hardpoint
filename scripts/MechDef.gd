class_name MechDef
extends Resource
# Data-only descriptor for a named mech chassis.
# Stored as a .tres file in resources/mechs/.
# Arena reads this to instantiate and configure mech nodes.

@export var display_name: String = ""
@export var class_tag: String = ""       # "Light" / "Medium" / "Heavy" — label only
@export var max_health: float = 100.0
@export var walk_speed: float = 5.25
@export var has_shields: bool = false
@export var hardpoint_count: int = 2
@export var scene: PackedScene           # mech scene to instantiate in Arena
