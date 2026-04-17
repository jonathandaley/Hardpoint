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
# weapon_slots: Array of {size: "Light"/"Heavy", position: Vector3}
# Empty means use whatever is in the scene; populated = dynamic instantiation (Phase 2+)
@export var weapon_slots: Array = []
@export var turn_acceleration: float = 60.0   # m/s² per axis — how fast velocity changes direction
@export var leg_rotation_speed: float = 15.0  # rad/s — how fast legs swing to match velocity
@export var body_scale: float = 1.0            # uniform scale applied to the spawned mech node
@export var scene: PackedScene                 # mech scene to instantiate in Arena
