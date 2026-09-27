class_name Ball
extends RigidBody3D
## A basketball. Knows whether it went through the hoop and whether that counts.

signal scored(ball: Ball)

const RADIUS := 0.12
const RESPAWN_POINT := Vector3(0.0, 1.5, 6.0)

var is_money := false
var hoop: Hoop
var held := false
## True while this ball can still earn contest points (until its first shot is used up).
var live := true
## How many times this ball has been properly shot.
var shots := 0
## True from a shot's release until the ball is picked up again or goes in.
var in_flight_shot := false
var touched_rim := false
var touched_board := false

var _prev_pos := Vector3.ZERO
var _came_up_through_until := 0.0


func _init(money := false) -> void:
	is_money = money


func _ready() -> void:
	add_to_group("balls")
	mass = 0.62
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = Util.LAYER_BALL
	collision_mask = Util.LAYER_WORLD | Util.LAYER_BALL | Util.LAYER_HAND | Util.LAYER_PLAYER
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.02
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.15
	# Static surfaces use bounce 0, so this value decides every bounce.
	physics_material_override = Util.surface(0.78, 0.8)

	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	var col := CollisionShape3D.new()
	col.shape = sphere
	add_child(col)

	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := Util.shader_material(Util.BALL_SHADER)
	if is_money:
		mat.set_shader_parameter("base_color", Color(0.85, 0.12, 0.14))
		mat.set_shader_parameter("alt_color", Color(0.15, 0.3, 0.85))
	mi.material_override = mat
	add_child(mi)

	body_entered.connect(_on_body_entered)
	_prev_pos = global_position


func _physics_process(_delta: float) -> void:
	var pos := global_position
	if hoop and not held:
		_check_hoop(pos)
	if pos.y < -3.0 or absf(pos.x) > 12.0 or pos.z < -6.0 or pos.z > 16.0:
		global_position = RESPAWN_POINT
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		pos = RESPAWN_POINT
	_prev_pos = pos


func _check_hoop(pos: Vector3) -> void:
	var c := hoop.rim_center
	var plane_y := c.y - 0.06
	var flat := Vector2(pos.x - c.x, pos.z - c.z).length()
	if flat >= Hoop.RIM_HOLE_RADIUS:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _prev_pos.y >= plane_y and pos.y < plane_y:
		if now > _came_up_through_until:
			scored.emit(self)
	elif _prev_pos.y < plane_y and pos.y >= plane_y:
		# Went up through the net from below; don't let it count on the way back down.
		_came_up_through_until = now + 1.5


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("rim"):
		touched_rim = true
	elif body.is_in_group("backboard"):
		touched_board = true


## Puts the ball back on its rack, frozen, ready for a new round.
func rack_at(pos: Vector3) -> void:
	freeze = true
	global_position = pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gravity_scale = 1.0
	held = false
	live = true
	shots = 0
	in_flight_shot = false
	touched_rim = false
	touched_board = false
	_prev_pos = pos


func grab() -> void:
	freeze = false
	held = true
	gravity_scale = 0.0
	in_flight_shot = false
	# A ball only gets one scoring attempt per round.
	if shots > 0:
		live = false


func release(vel: Vector3, spin: Vector3, is_shot: bool) -> void:
	held = false
	gravity_scale = 1.0
	linear_velocity = vel
	angular_velocity = spin
	if is_shot:
		shots += 1
		in_flight_shot = true
		touched_rim = false
		touched_board = false
