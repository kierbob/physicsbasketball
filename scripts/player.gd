class_name Player
extends CharacterBody3D
## First-person player with two floppy physics hands.
##
## Hold LMB to reach out and grab a ball, keep holding to carry it, then whip
## the mouse and let go of LMB to hurl it. The ball keeps the speed your arms
## gave it. A small hidden assist nudges throws that were already close.

signal grabbed_ball(ball: Ball)
signal threw_ball(ball: Ball, speed: float)
signal fumbled

enum State { EMPTY, HOLD }

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 4.2
const MOUSE_SENS := 0.0022
const EYE_HEIGHT := 1.65

const HAND_RADIUS := 0.055
const REACH := 1.7
const GRAB_DISTANCE := Ball.RADIUS + 0.12
const UPPER_ARM := 0.3
const FOREARM := 0.3

# Floppy arms: an underdamped spring pulls each hand toward where it wants to be.
const HAND_SPRING := 450.0
const HAND_DAMP := 16.0
const HAND_MAX_SPEED := 30.0
const BALL_GAIN := 30.0 ## how tightly the ball sticks between the hands
const STUCK_DISTANCE := 1.0 ## ball this far from the hands for a moment = fumble

# Throwing.
const HOLD_OFFSET := Vector3(0.0, -0.15, -0.62) ## ball position, camera space
const THROW_WINDOW := 0.15 ## s; the fastest arm speed in this window is used
const THROW_BOOST := 1.35 ## multiplies the arm's whip speed
const THROW_FORWARD := 1.1 ## forward push per m/s of whip speed
const MIN_THROW := 2.5 ## slower than this is a gentle drop, not a shot
const MAX_THROW := 22.0
const BACKSPIN := 10.0

# Hidden assist: throws whose path already comes near the hoop get nudged in.
const ASSIST_RADIUS := 1.4
const ASSIST_STRENGTH := 0.85

var hud: Hud
var hoop: Hoop
var state := State.EMPTY
var ball: Ball
var pitch := 0.0

var head: Node3D
var camera: Camera3D
var hands: Array[RigidBody3D] = []
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _samples: Array[Vector3] = [] # recent ball velocity relative to the player
var _sample_times: Array[float] = []
var _stuck_time := 0.0
var _follow_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _follow_time := 0.0
var _excepted: Dictionary = {} # Ball -> seconds left (INF while held)


func _ready() -> void:
	collision_layer = Util.LAYER_PLAYER
	collision_mask = Util.LAYER_WORLD | Util.LAYER_BALL

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.9
	add_child(col)

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 80.0
	camera.near = 0.03
	head.add_child(camera)
	camera.current = true

	var skin := Util.material(Color(0.87, 0.66, 0.52), 0.7)
	var sleeve := Util.material(Color(0.12, 0.35, 0.8), 0.8)
	for i in 2:
		var hand := RigidBody3D.new()
		hand.top_level = true
		hand.gravity_scale = 0.0
		hand.mass = 1.2
		hand.lock_rotation = true
		hand.continuous_cd = true
		hand.collision_layer = Util.LAYER_HAND
		hand.collision_mask = Util.LAYER_WORLD | Util.LAYER_BALL
		var sphere := SphereShape3D.new()
		sphere.radius = HAND_RADIUS
		var hand_col := CollisionShape3D.new()
		hand_col.shape = sphere
		hand.add_child(hand_col)
		var hand_mesh := SphereMesh.new()
		hand_mesh.radius = HAND_RADIUS + 0.005
		hand_mesh.height = HAND_RADIUS * 1.6
		var hand_mi := MeshInstance3D.new()
		hand_mi.mesh = hand_mesh
		hand_mi.material_override = skin
		hand.add_child(hand_mi)
		add_child(hand)
		hand.global_position = camera.to_global(_idle_offset(i))
		hands.append(hand)

		_upper_arms.append(_make_arm_segment(0.045, sleeve))
		_forearms.append(_make_arm_segment(0.035, skin))


func _make_arm_segment(radius: float, mat: Material) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	cyl.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# --- Input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if hud:
				hud.set_banner("")
		return

	if event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		rotate_y(-rel.x * MOUSE_SENS)
		pitch = clampf(pitch - rel.y * MOUSE_SENS, -1.45, 1.45)
		head.rotation.x = pitch
	elif event.is_action_pressed("drop") and state == State.HOLD:
		_let_go(velocity + _flat_forward(), Vector3.ZERO, false)


# --- Simulation ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	_move(delta)
	_tick_exceptions(delta)

	var targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	if state == State.HOLD and not Input.is_action_pressed("grab"):
		_throw()

	match state:
		State.EMPTY:
			if Input.is_action_pressed("grab") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				var reach := _reach_point()
				var side := camera.global_transform.basis.x * 0.11
				targets[0] = reach - side
				targets[1] = reach + side
				_try_grab()
			elif _follow_time > 0.0:
				_follow_time -= delta
				targets[0] = camera.to_global(_follow_local[0])
				targets[1] = camera.to_global(_follow_local[1])
			else:
				targets[0] = camera.to_global(_idle_offset(0))
				targets[1] = camera.to_global(_idle_offset(1))
		State.HOLD:
			var hold := camera.to_global(HOLD_OFFSET)
			var side := camera.global_transform.basis.x * (Ball.RADIUS + HAND_RADIUS)
			targets[0] = hold - side
			targets[1] = hold + side

	_drive_hands(targets, delta)
	if state == State.HOLD:
		_drive_ball(delta)
	_update_arms()


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var accel := (12.0 if is_on_floor() else 3.0) * speed * delta
	velocity.x = move_toward(velocity.x, dir.x * speed, accel)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel)
	move_and_slide()

	# CharacterBody3D doesn't push rigid bodies on its own; nudge loose balls.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider()
		if body is RigidBody3D and not (body as RigidBody3D).freeze:
			var push := -c.get_normal() * minf(velocity.length(), 6.0) * 0.04
			(body as RigidBody3D).apply_central_impulse(push)


func _drive_hands(targets: Array[Vector3], delta: float) -> void:
	for i in 2:
		var hand := hands[i]
		var err := targets[i] - hand.global_position
		if err.length() > 1.5:
			# Got stuck somewhere silly; snap back.
			hand.global_position = targets[i]
			hand.linear_velocity = velocity
			continue
		var accel := err * HAND_SPRING + (velocity - hand.linear_velocity) * HAND_DAMP
		hand.linear_velocity = (hand.linear_velocity + accel * delta).limit_length(HAND_MAX_SPEED)


## The ball rides between the hands, so it wobbles and whips along with them.
func _drive_ball(delta: float) -> void:
	var mid := (hands[0].global_position + hands[1].global_position) * 0.5
	var mid_vel := (hands[0].linear_velocity + hands[1].linear_velocity) * 0.5
	var err := mid - ball.global_position
	if err.length() > STUCK_DISTANCE:
		_stuck_time += delta
		if _stuck_time > 0.3:
			_let_go(ball.linear_velocity, ball.angular_velocity, false)
			fumbled.emit()
			return
	else:
		_stuck_time = 0.0
	ball.linear_velocity = (mid_vel + err * BALL_GAIN).limit_length(MAX_THROW)
	ball.angular_velocity *= 0.85

	var now := Time.get_ticks_msec() / 1000.0
	_samples.append(ball.linear_velocity - velocity)
	_sample_times.append(now)
	while not _sample_times.is_empty() and now - _sample_times[0] > THROW_WINDOW:
		_samples.pop_front()
		_sample_times.pop_front()


func _throw() -> void:
	# Use the fastest whip from the last moment, so letting go a hair late still works.
	var whip := Vector3.ZERO
	for s in _samples:
		if s.length() > whip.length():
			whip = s
	var fwd := _flat_forward()
	var fling := whip * THROW_BOOST + fwd * whip.length() * THROW_FORWARD
	if fling.length() < MIN_THROW:
		_let_go(velocity + fwd * 1.0, Vector3.ZERO, false)
		return
	fling = fling.limit_length(MAX_THROW)
	var vel := _assist(ball.global_position, velocity + fling)
	var spin := camera.global_transform.basis.x * BACKSPIN if vel.y > 0.0 else Vector3.ZERO
	var b := ball
	_follow_local[0] = camera.to_local(hands[0].global_position + fling.normalized() * 0.3)
	_follow_local[1] = camera.to_local(hands[1].global_position + fling.normalized() * 0.3)
	_follow_time = 0.35
	_let_go(vel, spin, true)
	threw_ball.emit(b, fling.length())


## Finds where the fling comes closest to the hoop on its way down and, if that
## is already near, blends the launch toward a make with the same flight time.
func _assist(from: Vector3, vel: Vector3) -> Vector3:
	if hoop == null:
		return vel
	var target := hoop.rim_center + Vector3(0.0, 0.05, 0.0)
	var g := Vector3(0.0, -_gravity, 0.0)
	var best_t := -1.0
	var best_d := INF
	var t := 0.05
	while t < 4.0:
		if vel.y + g.y * t < 0.0:
			var d := (from + vel * t + g * (0.5 * t * t)).distance_to(target)
			if d < best_d:
				best_d = d
				best_t = t
		t += 1.0 / 60.0
	if best_t < 0.0 or best_d > ASSIST_RADIUS:
		return vel
	var perfect := (target - from - g * (0.5 * best_t * best_t)) / best_t
	var strength := ASSIST_STRENGTH * sqrt(1.0 - best_d / ASSIST_RADIUS)
	return vel.lerp(perfect, strength)


func _flat_forward() -> Vector3:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized()


func _reach_point() -> Vector3:
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + fwd * REACH, Util.LAYER_WORLD | Util.LAYER_BALL)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return from + fwd * 0.95
	var pos: Vector3 = hit["position"]
	return pos - fwd * 0.04


func _idle_offset(i: int) -> Vector3:
	return Vector3(-0.24 if i == 0 else 0.24, -0.32, -0.42)


func _try_grab() -> void:
	for node in get_tree().get_nodes_in_group("balls"):
		var b := node as Ball
		if b == null or b.held:
			continue
		for hand in hands:
			if hand.global_position.distance_to(b.global_position) < GRAB_DISTANCE:
				ball = b
				state = State.HOLD
				_stuck_time = 0.0
				_samples.clear()
				_sample_times.clear()
				b.grab()
				_set_exception(b, true)
				_excepted[b] = INF
				grabbed_ball.emit(b)
				return


func _let_go(vel: Vector3, spin: Vector3, is_shot: bool) -> void:
	var b := ball
	ball = null
	state = State.EMPTY
	_samples.clear()
	_sample_times.clear()
	b.release(vel, spin, is_shot)
	# Keep ignoring the ball briefly so it doesn't clip our own hands on release.
	_excepted[b] = 0.3


## Drops the ball without any fling (used when the round resets).
func force_drop() -> void:
	if ball:
		_let_go(Vector3.ZERO, Vector3.ZERO, false)
		_tick_exceptions(1.0)


func _tick_exceptions(delta: float) -> void:
	for b in _excepted.keys():
		if b == ball:
			continue
		_excepted[b] -= delta
		if _excepted[b] <= 0.0:
			_excepted.erase(b)
			if is_instance_valid(b):
				_set_exception(b, false)


func _set_exception(b: Ball, on: bool) -> void:
	var bodies: Array[PhysicsBody3D] = [self]
	for hand in hands:
		bodies.append(hand)
	for body in bodies:
		if on:
			body.add_collision_exception_with(b)
			b.add_collision_exception_with(body)
		else:
			body.remove_collision_exception_with(b)
			b.remove_collision_exception_with(body)


func _update_arms() -> void:
	var cam_basis := camera.global_transform.basis
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var shoulder := camera.to_global(Vector3(0.2 * s, -0.27, 0.1))
		var hand := hands[i].global_position
		var pole := cam_basis * Vector3(0.6 * s, -1.0, 0.2)
		var elbow := _solve_elbow(shoulder, hand, pole)
		Util.place_segment(_upper_arms[i], shoulder, elbow)
		Util.place_segment(_forearms[i], elbow, hand)


## Two-bone IK. Past full reach the arm just stretches, which is funnier.
func _solve_elbow(shoulder: Vector3, hand: Vector3, pole: Vector3) -> Vector3:
	var d := hand - shoulder
	var length := d.length()
	if length < 0.001:
		return shoulder + pole.normalized() * UPPER_ARM
	var dn := d / length
	if length >= UPPER_ARM + FOREARM:
		return shoulder + dn * (length * UPPER_ARM / (UPPER_ARM + FOREARM))
	var x := (length * length + UPPER_ARM * UPPER_ARM - FOREARM * FOREARM) / (2.0 * length)
	var h := sqrt(maxf(UPPER_ARM * UPPER_ARM - x * x, 0.0))
	var p := pole - dn * pole.dot(dn)
	if p.length() < 0.001:
		p = Vector3.DOWN
	return shoulder + dn * x + p.normalized() * h
