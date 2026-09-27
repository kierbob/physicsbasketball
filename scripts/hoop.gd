class_name Hoop
extends Node3D
## Regulation-ish (FIBA) hoop: rim, backboard, net and support. The node's origin
## is the floor point directly under the rim center; the backboard sits toward -Z.

const RIM_HEIGHT := 3.05
const RIM_HOLE_RADIUS := 0.2286
const RIM_TUBE := 0.01
const RIM_SEGMENTS := 28
const BOARD_OFFSET := 0.375 # rim center to backboard front face
const BOARD_SIZE := Vector3(1.8, 1.05, 0.03)
const BOARD_BOTTOM := 2.9

var rim_center := Vector3.ZERO


func _ready() -> void:
	rim_center = global_position + Vector3(0.0, RIM_HEIGHT, 0.0)
	_build_rim()
	_build_net()
	_build_backboard()
	_build_support()


func _build_rim() -> void:
	var body := StaticBody3D.new()
	body.add_to_group("rim")
	body.collision_layer = Util.LAYER_WORLD
	body.collision_mask = 0
	body.physics_material_override = Util.surface(0.0, 0.6)
	body.position = Vector3(0.0, RIM_HEIGHT, 0.0)
	add_child(body)

	# The rim is a ring of short capsules so the ball can rattle around it.
	var ring_r := RIM_HOLE_RADIUS + RIM_TUBE
	for i in RIM_SEGMENTS:
		var a0 := TAU * i / RIM_SEGMENTS
		var a1 := TAU * (i + 1) / RIM_SEGMENTS
		var p0 := Vector3(cos(a0), 0.0, sin(a0)) * ring_r
		var p1 := Vector3(cos(a1), 0.0, sin(a1)) * ring_r
		var cap := CapsuleShape3D.new()
		cap.radius = RIM_TUBE
		cap.height = p0.distance_to(p1) + RIM_TUBE * 2.0
		var col := CollisionShape3D.new()
		col.shape = cap
		col.transform = Transform3D(Util.basis_y_to(p1 - p0), (p0 + p1) * 0.5)
		body.add_child(col)

	var rim_mat := Util.material(Color(0.95, 0.3, 0.08), 0.35, 0.6)
	var torus := TorusMesh.new()
	torus.inner_radius = RIM_HOLE_RADIUS
	torus.outer_radius = RIM_HOLE_RADIUS + RIM_TUBE * 2.0
	torus.rings = 48
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = rim_mat
	body.add_child(mi)

	# Bracket joining the rim to the backboard.
	var back := -(ring_r + RIM_TUBE)
	var depth := BOARD_OFFSET + back
	var bracket_shape := BoxShape3D.new()
	bracket_shape.size = Vector3(0.12, 0.03, depth)
	var bracket := CollisionShape3D.new()
	bracket.shape = bracket_shape
	bracket.position = Vector3(0.0, -0.01, back - depth * 0.5)
	body.add_child(bracket)
	var bracket_mesh := Util.mesh_box(bracket_shape.size, rim_mat)
	bracket_mesh.position = bracket.position
	body.add_child(bracket_mesh)


func _build_net() -> void:
	var net := CylinderMesh.new()
	net.top_radius = RIM_HOLE_RADIUS + 0.005
	net.bottom_radius = 0.14
	net.height = 0.42
	net.cap_top = false
	net.cap_bottom = false
	net.radial_segments = 24
	var mat := Util.shader_material(Util.LATTICE_SHADER)
	mat.set_shader_parameter("cells", Vector2(12.0, 4.0))
	var mi := MeshInstance3D.new()
	mi.mesh = net
	mi.material_override = mat
	mi.position = Vector3(0.0, RIM_HEIGHT - net.height * 0.5, 0.0)
	add_child(mi)

	# The net has no collision, but it drags on the ball like a real one.
	var drag := Area3D.new()
	drag.collision_layer = 0
	drag.collision_mask = Util.LAYER_BALL
	drag.linear_damp_space_override = Area3D.SPACE_OVERRIDE_COMBINE
	drag.linear_damp = 2.5
	var shape := CylinderShape3D.new()
	shape.radius = 0.2
	shape.height = 0.4
	var col := CollisionShape3D.new()
	col.shape = shape
	drag.add_child(col)
	drag.position = Vector3(0.0, RIM_HEIGHT - 0.22, 0.0)
	add_child(drag)


func _build_backboard() -> void:
	var glass := Util.material(Color(0.85, 0.92, 1.0, 0.25), 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var board := Util.static_box(BOARD_SIZE, glass, Util.surface(0.0, 0.5))
	board.add_to_group("backboard")
	board.position = Vector3(0.0, BOARD_BOTTOM + BOARD_SIZE.y * 0.5, -BOARD_OFFSET - BOARD_SIZE.z * 0.5)
	add_child(board)

	# Painted border and shooter's square on the front face.
	var paint := Util.material(Color(0.97, 0.97, 0.97), 0.6)
	var face_z := -BOARD_OFFSET + 0.003
	var w := 0.05
	var board_center_y := BOARD_BOTTOM + BOARD_SIZE.y * 0.5
	_paint_rect(Vector2(BOARD_SIZE.x, BOARD_SIZE.y), Vector3(0.0, board_center_y, face_z), w, paint)
	_paint_rect(Vector2(0.59, 0.45), Vector3(0.0, RIM_HEIGHT + 0.225, face_z), w, paint)


func _paint_rect(size: Vector2, center: Vector3, w: float, mat: Material) -> void:
	var hx := size.x * 0.5 - w * 0.5
	var hy := size.y * 0.5 - w * 0.5
	var strips := [
		[Vector3(size.x, w, 0.004), Vector3(0.0, hy, 0.0)],
		[Vector3(size.x, w, 0.004), Vector3(0.0, -hy, 0.0)],
		[Vector3(w, size.y, 0.004), Vector3(hx, 0.0, 0.0)],
		[Vector3(w, size.y, 0.004), Vector3(-hx, 0.0, 0.0)],
	]
	for strip in strips:
		var s: Vector3 = strip[0]
		var offset: Vector3 = strip[1]
		var mi := Util.mesh_box(s, mat)
		mi.position = center + offset
		add_child(mi)


func _build_support() -> void:
	var steel := Util.material(Color(0.2, 0.22, 0.25), 0.5, 0.5)
	var pole_z := -BOARD_OFFSET - 2.2
	var pole := Util.static_box(Vector3(0.2, 4.0, 0.2), steel)
	pole.position = Vector3(0.0, 2.0, pole_z)
	add_child(pole)

	var board_back := -BOARD_OFFSET - BOARD_SIZE.z
	var arm_len := board_back - pole_z
	var arm := Util.static_box(Vector3(0.14, 0.14, arm_len), steel)
	arm.position = Vector3(0.0, BOARD_BOTTOM + 0.5, pole_z + arm_len * 0.5)
	add_child(arm)

	var pad := Util.static_box(Vector3(0.5, 1.8, 0.5), Util.material(Color(0.1, 0.25, 0.6)))
	pad.position = Vector3(0.0, 0.9, pole_z)
	add_child(pad)
