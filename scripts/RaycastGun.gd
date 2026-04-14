class_name RaycastGun
extends "res://scripts/WeaponBase.gd"
# Hitscan weapon. Ray fires from screen centre in camera's forward direction.
# Muzzle flash is cosmetic — stays at hardpoint position.

@onready var muzzle_flash: MeshInstance3D = $MuzzleFlash
var _flash_timer: float = 0.0

func _process(delta: float) -> void:
	super._process(delta)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			muzzle_flash.visible = false

func _do_fire() -> void:
	var mech: Node3D = get_parent().get_parent()  # hardpoint → mech
	var cam := mech.get_node_or_null("CameraArm/Camera3D") as Camera3D
	if cam == null:
		return

	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z * range)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [mech.get_rid()]

	var result := space.intersect_ray(query)
	if result:
		print("[Gun] Hit %s at %.1f %.1f %.1f" % [
			result.collider.name,
			result.position.x, result.position.y, result.position.z
		])
		if result.collider.has_method("take_damage"):
			result.collider.take_damage(damage)

	muzzle_flash.visible = true
	_flash_timer = 0.08
