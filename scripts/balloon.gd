class_name Balloon
extends StaticBody3D
## A floating balloon that drifts and bobs around. Arrows go straight through.

const RADIUS := 0.3

var _base := Vector3.ZERO
var _phase := 0.0
var _time := 0.0


func _ready() -> void:
	add_to_group("balloon")
	collision_layer = Util.LAYER_PROP
	collision_mask = 0
	_base = position
	_phase = randf() * TAU

	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.5
	var mat := Util.material(Color.from_hsv(randf(), 0.8, 0.95), 0.25)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	var string := Util.cylinder(0.003, Util.material(Color(0.9, 0.9, 0.9)), 4)
	add_child(string)
	Util.place_segment_local(string, Vector3(0, -RADIUS * 1.2, 0), Vector3(0, -RADIUS * 1.2 - 1.0, 0))


func _physics_process(delta: float) -> void:
	_time += delta
	var t := _time + _phase
	position = _base + Vector3(sin(t * 0.4) * 1.5, sin(t * 1.3) * 0.3, cos(t * 0.3) * 1.0)


func pop() -> void:
	collision_layer = 0
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 1.5, 0.06)
	tween.tween_callback(queue_free)
