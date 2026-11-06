extends Node3D
# T264 (HUMAN_FOUND 2026-11-05: drops from destroyed bots; user: coins by bot difficulty +
# powerups repair / ammo / damage boost / speed boost): one dropped pickup, the same on every
# peer. Arena spawns and removes it by id (server-authoritative); this node is only its look.

const COLORS := {
	"coin":   Color(1.0, 0.82, 0.2),
	"repair": Color(0.3, 1.0, 0.45),
	"ammo":   Color(1.0, 0.6, 0.15),
	"damage": Color(1.0, 0.25, 0.2),
	"speed":  Color(0.3, 0.7, 1.0),
}

var kind := "coin"
var value := 0
var age := 0.0
var _mesh: MeshInstance3D = null

func setup(k: String, v: int) -> void:
	kind = k
	value = v

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COLORS.get(kind, Color.WHITE)
	_mesh = MeshInstance3D.new()
	if kind == "coin":
		var c := CylinderMesh.new()
		c.top_radius = 0.32
		c.bottom_radius = 0.32
		c.height = 0.08
		_mesh.mesh = c
		_mesh.rotation.x = PI * 0.5  # stands on its edge, spins about y
	else:
		var b := BoxMesh.new()
		b.size = Vector3.ONE * 0.55
		_mesh.mesh = b
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

func _process(delta: float) -> void:
	age += delta
	rotation.y += delta * 2.5
	_mesh.position.y = 0.7 + sin(age * 3.0) * 0.12
