class_name ArcheryTarget
extends StaticBody3D
## A straw target boss with a standard 10-ring face. Its local +Y axis is the
## face normal; place it so +Y points back at the shooter.

const RADIUS := 0.61
const THICKNESS := 0.3

const FACE_SHADER := """
shader_type spatial;
uniform float radius = 0.61;
uniform float half_thickness = 0.15;
varying vec3 p;

void vertex() {
	p = VERTEX;
}

void fragment() {
	float r = length(p.xz) / radius;
	vec3 c = vec3(0.95);
	if (r < 0.2) { c = vec3(1.0, 0.82, 0.1); }
	else if (r < 0.4) { c = vec3(0.9, 0.15, 0.12); }
	else if (r < 0.6) { c = vec3(0.15, 0.45, 0.9); }
	else if (r < 0.8) { c = vec3(0.1); }
	float ring = fract(r * 10.0);
	if (ring < 0.04 || ring > 0.96) { c *= 0.55; }
	if (p.y < half_thickness - 0.002) { c = vec3(0.78, 0.66, 0.36); }
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
"""

## Points per ring are multiplied by this (farther targets are worth more).
var multiplier := 1


func _ready() -> void:
	add_to_group("target")
	collision_layer = Util.LAYER_WORLD
	collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = THICKNESS
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = THICKNESS
	mesh.radial_segments = 48
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := Util.shader_material(FACE_SHADER)
	mat.set_shader_parameter("radius", RADIUS)
	mat.set_shader_parameter("half_thickness", THICKNESS * 0.5)
	mi.material_override = mat
	add_child(mi)


## Ring score (10 = bullseye, 0 = missed the face) for a world-space hit point.
func ring_at(point: Vector3) -> int:
	var local := to_local(point)
	var r := Vector2(local.x, local.z).length()
	if r > RADIUS:
		return 0
	return clampi(10 - int(r / (RADIUS / 10.0)), 1, 10)
