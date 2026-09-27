class_name Bow
extends RigidBody3D
## A recurve-ish bow. When nobody holds it, it's a normal rigid body that falls
## over and slides around. The limbs bend and the string follows the draw.
## Bow space: grip at the origin, limbs along Y, shoots toward -Z.

const HALF_LENGTH := 0.6
const BRACE := 0.18 ## string distance behind the grip at rest
const DRAW_LENGTH := 0.5 ## extra pull at full draw
const LIMB_SEGMENTS := 6

var held := false
## 0 = resting, 1 = full draw. Set by whoever is pulling the string.
var draw := 0.0
var string_held := false
var arrow_nocked := false

var _limbs: Array[MeshInstance3D] = []
var _strings: Array[MeshInstance3D] = []
var _nocked_arrow: Node3D
var _twang := 0.0
var _twang_time := 0.0


func _ready() -> void:
	mass = 1.0
	continuous_cd = true
	collision_layer = Util.LAYER_BOW
	collision_mask = Util.LAYER_WORLD | Util.LAYER_PROP
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.05, HALF_LENGTH * 2.0, 0.25)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0, 0.08)
	add_child(col)

	var wood := Util.material(Color(0.42, 0.24, 0.12), 0.6)
	var grip := Util.material(Color(0.12, 0.1, 0.09), 0.9)
	var string_mat := Util.material(Color(0.95, 0.93, 0.85), 0.9)
	var riser := Util.mesh_box(Vector3(0.035, 0.22, 0.04), grip)
	add_child(riser)
	for i in LIMB_SEGMENTS * 2:
		var limb := Util.cylinder(0.014, wood, 6)
		add_child(limb)
		_limbs.append(limb)
	for i in 2:
		var s := Util.cylinder(0.0025, string_mat, 4)
		add_child(s)
		_strings.append(s)
	_nocked_arrow = Arrow.make_visual()
	add_child(_nocked_arrow)
	_update_visuals()


func _process(delta: float) -> void:
	if _twang > 0.0:
		_twang_time += delta
		_twang = maxf(0.0, _twang - delta * 3.0)
	_update_visuals()


func _update_visuals() -> void:
	# Tips curl back toward the archer as the bow is drawn.
	var bend := 0.1 + 0.12 * draw
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		for k in LIMB_SEGMENTS:
			var y0 := 0.1 + (HALF_LENGTH - 0.1) * k / LIMB_SEGMENTS
			var y1 := 0.1 + (HALF_LENGTH - 0.1) * (k + 1) / LIMB_SEGMENTS
			var a := Vector3(0, y0 * s, bend * pow(y0 / HALF_LENGTH, 2.0))
			var b := Vector3(0, y1 * s, bend * pow(y1 / HALF_LENGTH, 2.0))
			Util.place_segment_local(_limbs[side * LIMB_SEGMENTS + k], a, b)

	var nock_z := nock_z_for(draw)
	if not string_held and _twang > 0.0:
		nock_z += sin(_twang_time * 90.0) * 0.04 * _twang
	var nock := Vector3(0, 0, nock_z)
	Util.place_segment_local(_strings[0], Vector3(0, -HALF_LENGTH, bend), nock)
	Util.place_segment_local(_strings[1], Vector3(0, HALF_LENGTH, bend), nock)

	_nocked_arrow.visible = arrow_nocked
	_nocked_arrow.position = Vector3(-0.018, 0, nock_z - Arrow.LENGTH)


static func nock_z_for(amount: float) -> float:
	return BRACE + amount * DRAW_LENGTH


func pick_up() -> void:
	held = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true


func drop(vel: Vector3, spin: Vector3) -> void:
	held = false
	string_held = false
	arrow_nocked = false
	draw = 0.0
	freeze = false
	linear_velocity = vel
	angular_velocity = spin


## String let go: it snaps forward and wobbles for a moment.
func release_string() -> void:
	string_held = false
	_twang = draw
	_twang_time = 0.0
	draw = 0.0
