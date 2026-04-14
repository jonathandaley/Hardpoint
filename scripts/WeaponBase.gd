class_name WeaponBase
extends Node3D
# Base weapon. Attach as a child of a hardpoint on a Mech.
# Stage 1: stub — override _do_fire() in subclasses.

@export var damage: float = 10.0
@export var fire_rate: float = 2.0   # shots per second
@export var range: float = 100.0

var _cooldown: float = 0.0

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

func fire() -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 1.0 / fire_rate
	_do_fire()

func _do_fire() -> void:
	print("[WeaponBase] _do_fire() — override in subclass")
