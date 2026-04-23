class_name WeaponBase
extends Node3D
# Base weapon. Attach as a child of a hardpoint on a Mech.
# Override _do_fire() in subclasses.

signal hit_confirmed   # emitted when a shot lands on a valid target

enum MagazineType { FIXED, REFILLING }

# 0 = Light, 1 = Heavy -- must match the slot this weapon is placed in
@export var slot_size: int = 0
@export var damage: float = 10.0
@export var fire_rate: float = 2.0      # shots per second
@export var range: float = 100.0
@export var max_ammo: int = -1          # -1 = infinite; ignored by magazine logic
@export var magazine_type: MagazineType = MagazineType.FIXED
@export var reload_time: float = 1.5   # FIXED: seconds to reload full magazine
@export var refill_rate: float = 5.0   # REFILLING: ammo per second
@export var shake_magnitude: float = 0.0  # radians; 0 = no shake
@export var requires_lock: bool = false

var owner_mech: Node3D = null   # set by Mech._setup_weapon_owners() at ready time
var ammo: int = -1
var _cooldown: float = 0.0
var _reloading: bool = false
var _reload_timer: float = 0.0
var _refill_accum: float = 0.0

func _ready() -> void:
	ammo = max_ammo

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

	if max_ammo < 0:
		return  # infinite - no magazine logic

	match magazine_type:
		MagazineType.FIXED:
			if _reloading:
				_reload_timer -= delta
				if _reload_timer <= 0.0:
					_reloading = false
					ammo = max_ammo
		MagazineType.REFILLING:
			if ammo < max_ammo:
				_refill_accum += refill_rate * delta
				var add: int = int(_refill_accum)
				if add > 0:
					ammo = mini(max_ammo, ammo + add)
					_refill_accum -= float(add)

func fire() -> void:
	if _cooldown > 0.0:
		return
	if _reloading:
		return
	if max_ammo >= 0 and ammo <= 0:
		if magazine_type == MagazineType.FIXED:
			_start_reload()
		return
	_cooldown = 1.0 / fire_rate
	_do_fire()
	if shake_magnitude > 0.0 and owner_mech != null and owner_mech.has_method("apply_camera_shake"):
		owner_mech.apply_camera_shake(shake_magnitude)
	if max_ammo >= 0:
		ammo -= 1
		if ammo <= 0 and magazine_type == MagazineType.FIXED:
			_start_reload()

func try_reload() -> void:
	if magazine_type != MagazineType.FIXED:
		return
	if _reloading or max_ammo < 0 or ammo == max_ammo:
		return
	_start_reload()

func is_reloading() -> bool:
	return _reloading

func get_reload_progress() -> float:
	if not _reloading or reload_time <= 0.0:
		return 1.0
	return clampf(1.0 - _reload_timer / reload_time, 0.0, 1.0)

func _start_reload() -> void:
	_reloading = true
	_reload_timer = reload_time

func _emit_hit_if_visible(target: Node) -> void:
	if target != null and target.get("is_stealthy"):
		return
	hit_confirmed.emit()

func _do_fire() -> void:
	print("[WeaponBase] _do_fire() -- override in subclass")
