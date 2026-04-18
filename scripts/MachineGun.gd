class_name MachineGun
extends "res://scripts/ProjectileGun.gd"
# Fixed mag, accelerating fire rate while trigger held, resets on release.
# base_fire_rate -> ramps to max_fire_rate at rate_accel rps/s.
# Releasing trigger decays back to base at rate_decay rps/s.

@export var base_fire_rate: float = 4.0
@export var max_fire_rate: float = 14.0
@export var rate_accel: float = 10.0   # rps added per second while held
@export var rate_decay: float = 25.0   # rps lost per second after release

var _current_rate: float = 0.0
var _trigger_held: bool = false

func _ready() -> void:
	super._ready()
	_current_rate = base_fire_rate

func _process(delta: float) -> void:
	super._process(delta)
	if _trigger_held:
		_current_rate = minf(_current_rate + rate_accel * delta, max_fire_rate)
	else:
		_current_rate = maxf(_current_rate - rate_decay * delta, base_fire_rate)
	_trigger_held = false

func fire() -> void:
	_trigger_held = true
	if _cooldown > 0.0:
		return
	if _reloading:
		return
	if max_ammo >= 0 and ammo <= 0:
		if magazine_type == MagazineType.FIXED:
			_start_reload()
		return
	_cooldown = 1.0 / _current_rate
	_do_fire()
	if shake_magnitude > 0.0 and owner_mech != null and owner_mech.has_method("apply_camera_shake"):
		owner_mech.apply_camera_shake(shake_magnitude)
	if max_ammo >= 0:
		ammo -= 1
		if ammo <= 0 and magazine_type == MagazineType.FIXED:
			_start_reload()
