class_name EnergyShield
extends Node

signal depleted
signal recharged

@export var max_shield_hp: float = 200.0
@export var regen_rate: float = 30.0     # HP/sec
@export var regen_delay: float = 3.0    # sec after last hit before regen starts

var shield_hp: float = 0.0
var _active: bool = false
var _regen_timer: float = 0.0

func activate(max_hp: float, rate: float, delay: float) -> void:
	max_shield_hp = max_hp
	regen_rate = rate
	regen_delay = delay
	shield_hp = max_hp
	_active = true

func _process(delta: float) -> void:
	if not _active or shield_hp >= max_shield_hp:
		return
	if _regen_timer > 0.0:
		_regen_timer = maxf(0.0, _regen_timer - delta)
		return
	var was_empty := shield_hp <= 0.0
	shield_hp = minf(shield_hp + regen_rate * delta, max_shield_hp)
	if was_empty and shield_hp > 0.0:
		recharged.emit()

# Returns overflow damage that passes through to the mech hull.
func absorb(amount: float) -> float:
	if not _active or shield_hp <= 0.0:
		return amount
	_regen_timer = regen_delay
	if amount <= shield_hp:
		shield_hp -= amount
		return 0.0
	var overflow := amount - shield_hp
	shield_hp = 0.0
	depleted.emit()
	return overflow
