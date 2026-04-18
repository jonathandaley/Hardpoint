class_name WeaponSlotDef
extends Resource

# 0 = Light, 1 = Heavy -- must match weapon's slot_size or the weapon is rejected
@export var slot_size: int = 0
@export var position: Vector3 = Vector3.ZERO
@export var weapon_scene: PackedScene = null
