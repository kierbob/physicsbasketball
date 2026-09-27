class_name Arrow
extends Node3D
## A flying arrow. It's swept with raycasts every tick (thin fast things and
## rigid bodies don't mix), falls with gravity, slows with drag and always
## points along its velocity like a fletched arrow. It sticks into what it hits
## head-on and fast enough; otherwise it glances off and tumbles as a rigid body.
## The origin is the tip; the shaft runs back along +Z.

signal hit(arrow: Arrow, body: Node, point: Vector3)
signal finished(arrow: Arrow)

const LENGTH := 0.75
const MASS := 0.03
const DRAG := 0.00025 ## quadratic air drag per metre
const TRAIL_TIME := 0.05 ## trail length in seconds of flight
const TRAIL_MAX := 4.0
const STICK_SPEED := 12.0
const STICK_ANGLE := 0.35 ## cosine; shallower hits than this glance off
const EMBED := 0.12
const PUSH_FUN := 8.0 ## real arrows barely shove crates; these do
const SELF_HIT_DELAY := 0.25

var velocity := Vector3.ZERO
var flying := true
var _age := 0.0
var _passed: Array[RID] = []
var _trail: MeshInstance3D


func _ready() -> void:
	add_child(make_visual())
	# A glowing streak behind the arrow so you can follow it downrange.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(1.0, 0.85, 0.4, 0.55)
	_trail = Util.cylinder(0.012, glow, 6)
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_orient()
	_update_trail()


## Arrow model with the tip at the origin, shaft along +Z. Shared with the bow.
static func make_visual() -> Node3D:
	var root := Node3D.new()
	var wood := Util.material(Color(0.95, 0.85, 0.55), 0.6)
	var steel := Util.material(Color(0.8, 0.82, 0.85), 0.25, 0.9)
	var feather := Util.material(Color(1.0, 0.2, 0.55), 0.9)
	feather.emission_enabled = true
	feather.emission = Color(1.0, 0.2, 0.55)
	feather.emission_energy_multiplier = 0.6
	var shaft := Util.cylinder(0.008, wood, 6)
	root.add_child(shaft)
	Util.place_segment_local(shaft, Vector3(0, 0, 0.03), Vector3(0, 0, LENGTH))
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.016
	head.height = 0.06
	head.radial_segments = 6
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.material_override = steel
	# Cylinder top is +Y; point it at -Z.
	head_mi.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.03))
	root.add_child(head_mi)
	for i in 3:
		var fin := Util.mesh_box(Vector3(0.003, 0.05, 0.13), feather)
		fin.transform = Transform3D(Basis(Vector3.BACK, TAU * i / 3.0), Vector3(0, 0, LENGTH - 0.09))
		fin.transform = fin.transform.translated_local(Vector3(0, 0.028, 0))
		root.add_child(fin)
	return root


func _physics_process(delta: float) -> void:
	if not flying:
		return
	_age += delta
	velocity += Vector3.DOWN * 9.8 * delta
	velocity -= velocity * velocity.length() * DRAG * delta

	var from := global_position
	var to := from + velocity * delta
	var mask := Util.LAYER_WORLD | Util.LAYER_PROP
	if _age > SELF_HIT_DELAY:
		mask |= Util.LAYER_PLAYER
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, _passed)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		global_position = to
		_orient()
	else:
		_impact(result)
	_update_trail()

	if global_position.y < -10.0 or global_position.length() > 400.0:
		_finish()
		queue_free()


func _impact(result: Dictionary) -> void:
	var body: Node = result["collider"]
	var point: Vector3 = result["position"]
	var normal: Vector3 = result["normal"]
	var dir := velocity.normalized()
	var speed := velocity.length()

	if body.is_in_group("balloon"):
		# Straight through. The balloon pops; the arrow keeps going.
		_passed.append(result["rid"])
		global_position = point
		hit.emit(self, body, point)
		return
	if body.is_in_group("player"):
		hit.emit(self, body, point)
		_finish()
		queue_free()
		return

	if body is RigidBody3D:
		var rb := body as RigidBody3D
		rb.apply_impulse(velocity * MASS * PUSH_FUN, point - rb.global_position)

	if speed > STICK_SPEED and -dir.dot(normal) > STICK_ANGLE:
		global_position = point + dir * EMBED
		_orient()
		if body is RigidBody3D:
			reparent(body)
		hit.emit(self, body, point)
		_finish()
	else:
		# Glance off and tumble around like a stick.
		var bounce := velocity.bounce(normal) * 0.35
		_spawn_tumbler(point + normal * 0.02, bounce)
		_finish()
		queue_free()


func _orient() -> void:
	if velocity.length() < 0.01:
		return
	var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
	look_at(global_position + velocity, up)


func _update_trail() -> void:
	if not flying:
		_trail.visible = false
		return
	var length := minf(velocity.length() * TRAIL_TIME, TRAIL_MAX)
	Util.place_segment_local(_trail, Vector3(0, 0, LENGTH), Vector3(0, 0, LENGTH + length))


func _finish() -> void:
	if flying:
		flying = false
		finished.emit(self)


func _spawn_tumbler(pos: Vector3, vel: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.mass = MASS * 3.0
	rb.continuous_cd = true
	rb.collision_layer = Util.LAYER_PROP
	rb.collision_mask = Util.LAYER_WORLD | Util.LAYER_PROP
	rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	rb.center_of_mass = Vector3(0, 0, LENGTH * 0.35)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.02, 0.02, LENGTH)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0, LENGTH * 0.5)
	rb.add_child(col)
	rb.add_child(make_visual())
	get_parent().add_child(rb)
	rb.global_transform = global_transform
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-5, 5))
	# Don't let the range fill up with sticks forever.
	get_tree().create_timer(20.0).timeout.connect(rb.queue_free)
