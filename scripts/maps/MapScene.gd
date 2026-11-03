class_name MapScene
extends Node3D
# T210: a map is its own scene: geometry, the 5 beacons (V18), spawn points, minimap
# shape. Arena instantiates MapDef.scene_path as its "Map" child, calls build() after the
# mechs spawn (match-start order as before), and asks the map for the rest. The map's
# static colliders bake into the navmesh through Arena's nav_source group (V55).

var center := Vector2.ZERO   # world XZ: spawns face it, minimap centre
var minimap_half := 100.0    # metres from center to the minimap edge

func build() -> void:
	pass

## World positions of `team`'s spawn points (y = ground_y there).
func spawn_points(_team: int) -> Array:
	return []

## Floor height before the floor colliders exist (the match-start spawn runs first).
func ground_y(_x: float, _z: float) -> float:
	return 0.0

## Map boundary for the minimap, world XZ.
func minimap_outline() -> PackedVector2Array:
	return PackedVector2Array()
