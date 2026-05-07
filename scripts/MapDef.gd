class_name MapDef
extends Resource
# Data descriptor for an arena map theme.
# Stored as .tres in resources/maps/.
# Arena reads this to vary column color, density, and lighting per map.

@export var map_name: String = "Math Temple"
@export var theme: String = "penrose"        # human-readable theme label
@export var cover_seed: int = 0              # seed for RandomNumberGenerator column filter
@export var cover_density: float = 1.0      # 0.0-1.0 fraction of columns kept per seed roll
@export var column_color: Color = Color(0.88, 0.90, 0.95, 1)
@export var floor_tint: Color = Color(0.30, 0.30, 0.35, 1)
@export var ambient_color: Color = Color(0.72, 0.78, 0.92, 1)
@export var ambient_energy: float = 0.85
