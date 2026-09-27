class_name Util
extends RefCounted
## Small helpers for building the scene from code.

# Collision layers (bit values).
const LAYER_WORLD := 1
const LAYER_PROP := 2
const LAYER_HAND := 4
const LAYER_PLAYER := 8
const LAYER_BOW := 16

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


## Same as place_segment, but in the parent's local space.
static func place_segment_local(node: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		node.visible = false
		return
	node.visible = true
	var basis := basis_y_to(d)
	basis.y *= length
	node.transform = Transform3D(basis, (a + b) * 0.5)


static func cylinder(radius: float, mat: Material, segments := 8) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	cyl.radial_segments = segments
	cyl.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	return mi


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
