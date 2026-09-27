class_name Util
extends RefCounted
## Small helpers for building the scene from code.

# Collision layers (bit values).
const LAYER_WORLD := 1
const LAYER_BALL := 2
const LAYER_HAND := 4
const LAYER_PLAYER := 8

const BALL_SHADER := """
shader_type spatial;
uniform vec3 base_color : source_color = vec3(0.86, 0.38, 0.1);
uniform vec3 alt_color : source_color = vec3(0.86, 0.38, 0.1);
uniform vec3 seam_color : source_color = vec3(0.04, 0.03, 0.03);
varying vec3 obj_normal;

void vertex() {
	obj_normal = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(obj_normal);
	float w = 0.022;
	float seam = step(abs(n.x), w) + step(abs(n.y), w) + step(abs(abs(n.z) - 0.72), w * 0.8);
	vec3 panel = mix(base_color, alt_color, step(0.0, n.x * n.y));
	ALBEDO = mix(panel, seam_color, clamp(seam, 0.0, 1.0));
	ROUGHNESS = 0.8;
}
"""

const LATTICE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 color : source_color = vec3(0.95);
uniform vec2 cells = vec2(16.0, 5.0);
uniform float thickness = 0.08;

void fragment() {
	vec2 uv = UV * cells;
	float a = abs(fract(uv.x + uv.y) - 0.5);
	float b = abs(fract(uv.x - uv.y) - 0.5);
	if (min(a, b) > thickness) {
		discard;
	}
	ALBEDO = color;
	ROUGHNESS = 0.8;
}
"""


## Basis whose Y axis points along `dir` (used for cylinders and capsules).
static func basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


## Places a height-1 Y-aligned mesh (cylinder) so it spans from `a` to `b`.
static func place_segment(node: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		node.visible = false
		return
	node.visible = true
	var basis := basis_y_to(d)
	basis.y *= length
	node.global_transform = Transform3D(basis, (a + b) * 0.5)


static func material(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


static func shader_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


static func surface(bounce: float, friction: float) -> PhysicsMaterial:
	var phys := PhysicsMaterial.new()
	phys.bounce = bounce
	phys.friction = friction
	return phys


static func mesh_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	return mi


## A static box with a matching visual. Pass `mat = null` for an invisible wall.
static func static_box(size: Vector3, mat: Material, phys: PhysicsMaterial = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	if phys:
		body.physics_material_override = phys
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	if mat:
		body.add_child(mesh_box(size, mat))
	return body
