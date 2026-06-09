class_name PhysicalShield
extends StaticBody3D

signal shield_broken

@export var max_shield_hp: float = 300.0
var shield_hp: float = 0.0

func activate(max_hp: float) -> void:
	max_shield_hp = max_hp
	shield_hp = max_hp
	visible = true
	$CollisionShape3D.disabled = false

func take_damage(amount: float, _source: Node3D = null) -> void:
	# _source unused; signature matches Mech.take_damage for uniform caller surface.
	if shield_hp <= 0.0:
		return
	shield_hp -= amount
	if shield_hp <= 0.0:
		shield_hp = 0.0
		_break()

func _break() -> void:
	$CollisionShape3D.disabled = true
	visible = false
	shield_broken.emit()
