class_name Player
extends CharacterBody3D
## First-person player with two physics hands.
##
## Hold LMB to reach out and grab a ball. Hold RMB to bring it up into shooting
## form, pull the mouse back (down) to load the shot, then flick it forward (up)
## to shoot. How far you pull back decides the power; where you look decides the
## direction and arc.

signal grabbed_ball(ball: Ball)
signal fumbled

enum State { EMPTY, HOLD, FORM, LAUNCH }

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 4.2
const MOUSE_SENS := 0.0022
const FORM_TURN_SCALE := 0.6
const EYE_HEIGHT := 1.65

const HAND_RADIUS := 0.055
const REACH := 1.7
const GRAB_DISTANCE := Ball.RADIUS + 0.12
const FUMBLE_DISTANCE := 0.6
const SETTLE_TIME := 0.35 ## grace period while the ball travels into the hands
const HAND_GAIN := 25.0
const BALL_GAIN := 20.0
const UPPER_ARM := 0.3
const FOREARM := 0.3

# Shot tuning.
const PULL_PIXELS := 500.0 ## mouse travel (px) for a full pull-back
const FLICK_PIXELS := 25.0 ## quick upward mouse travel (px) that fires the shot
const FLICK_DECAY := 300.0 ## px/s; easing the mouse up slower than this just fine-tunes power
const MIN_SHOT_SPEED := 6.0
const MAX_SHOT_SPEED := 11.5
const LOAD_DISTANCE := 0.28 ## how far back the ball comes at full pull
const EXTEND_DISTANCE := 0.5 ## push from the set point to the release
const BACKSPIN := 14.0 ## rad/s
const BASE_ARC_DEG := 45.0 ## launch angle when looking level
const ARC_PER_PITCH := 0.5 ## extra launch angle per degree of looking up

var hud: Hud
var state := State.EMPTY
var ball: Ball
var pitch := 0.0

var head: Node3D
var camera: Camera3D
var hands: Array[RigidBody3D] = []
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _stroke := 0.0 # 0 = set point, -1 = fully loaded
var _flick := 0.0
var _flick_start_stroke := 0.0
var _launch_pos := 0.0
var _launch_speed := 0.0
var _launch_pull := 0.0
var _follow_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _follow_time := 0.0
var _excepted: Dictionary = {} # Ball -> seconds left (INF while held)
var _settle := 0.0


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
		var shooting := state == State.FORM or state == State.LAUNCH
		rotate_y(-rel.x * MOUSE_SENS * (FORM_TURN_SCALE if shooting else 1.0))
		if state == State.FORM:
			_shot_motion(rel.y)
		elif not shooting:
			pitch = clampf(pitch - rel.y * MOUSE_SENS, -1.45, 1.45)
			head.rotation.x = pitch
	elif event.is_action_pressed("form") and state == State.HOLD:
		state = State.FORM
		_stroke = 0.0
		_flick = 0.0
		_settle = SETTLE_TIME
	elif event.is_action_released("form") and state == State.FORM:
		state = State.HOLD
	elif event.is_action_pressed("drop") and (state == State.HOLD or state == State.FORM):
		var fwd := -camera.global_transform.basis.z
		_let_go(velocity + fwd * 1.0, Vector3.ZERO, false)


## Mouse Y while in form: pulling back (down) loads, easing up slowly unloads,
## and a quick flick up shoots with the power you had when the flick started.
func _shot_motion(dy: float) -> void:
	if dy > 0.0:
		_stroke = maxf(_stroke - dy / PULL_PIXELS, -1.0)
		_flick = 0.0
	elif dy < 0.0:
		if _flick <= 0.0:
			_flick_start_stroke = _stroke
		_flick += -dy
		_stroke = minf(_stroke - dy / PULL_PIXELS, 0.0)
		if _flick >= FLICK_PIXELS and _flick_start_stroke <= -0.05:
			_launch_pull = -_flick_start_stroke
			_launch_speed = lerpf(MIN_SHOT_SPEED, MAX_SHOT_SPEED, _launch_pull)
			_launch_pos = _stroke * LOAD_DISTANCE
			state = State.LAUNCH


# --- Simulation ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	_move(delta)
	_tick_exceptions(delta)
	_flick = maxf(0.0, _flick - FLICK_DECAY * delta)
	_settle = maxf(0.0, _settle - delta)

	var targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var hand_ff := velocity
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
			var hold := camera.to_global(Vector3(0.0, -0.26, -0.48))
			var side := camera.global_transform.basis.x * (Ball.RADIUS + HAND_RADIUS)
			targets[0] = hold - side
			targets[1] = hold + side
			_drive_ball(hold, velocity)
		State.FORM, State.LAUNCH:
			var shot := _shot_frame()
			var set_point: Vector3 = shot[0]
			var dir: Vector3 = shot[1]
			var right: Vector3 = shot[2]
			var along := _stroke * LOAD_DISTANCE
			var ball_ff := velocity
			if state == State.LAUNCH:
				_launch_pos += _launch_speed * delta
				along = _launch_pos
				ball_ff += dir * _launch_speed
				hand_ff = ball_ff
			var target := set_point + dir * along
			var off := Ball.RADIUS + HAND_RADIUS
			# Shooting hand under/behind the ball, guide hand on its side.
			targets[0] = target - right * off
			targets[1] = target - dir * off
			if state == State.LAUNCH and _launch_pos >= EXTEND_DISTANCE:
				_follow_local[0] = camera.to_local(targets[0])
				_follow_local[1] = camera.to_local(targets[1] + dir * 0.1)
				_follow_time = 0.45
				_let_go(velocity + dir * _launch_speed, right * BACKSPIN, true)
			else:
				_drive_ball(target, ball_ff)

	_drive_hands(targets, hand_ff)
	_update_arms()
	if hud:
		var aiming := state == State.FORM or state == State.LAUNCH
		hud.set_power(_launch_pull if state == State.LAUNCH else -_stroke, aiming)


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


## Returns [set_point, launch_dir, right] for the current aim.
func _shot_frame() -> Array:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var set_point := camera.global_position + Vector3.UP * 0.2 + fwd * 0.28 + right * 0.16
	# The ball sits off to the right of the eye, so aim it from there at
	# whatever the crosshair is on.
	var to_aim := _aim_point() - set_point
	to_aim.y = 0.0
	if to_aim.length() > 0.5:
		fwd = to_aim.normalized()
		right = fwd.cross(Vector3.UP)
	var arc := deg_to_rad(clampf(BASE_ARC_DEG + rad_to_deg(pitch) * ARC_PER_PITCH, 30.0, 70.0))
	var dir := (fwd * cos(arc) + Vector3.UP * sin(arc)).normalized()
	return [set_point, dir, right]


func _aim_point() -> Vector3:
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + fwd * 40.0, Util.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return from + fwd * 20.0
	return hit["position"]


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


func _drive_hands(targets: Array[Vector3], ff: Vector3) -> void:
	for i in 2:
		var hand := hands[i]
		var err := targets[i] - hand.global_position
		if err.length() > 1.5:
			# Got stuck somewhere silly; snap back.
			hand.global_position = targets[i]
			hand.linear_velocity = ff
		else:
			hand.linear_velocity = (ff + err * HAND_GAIN).limit_length(25.0)


func _drive_ball(target: Vector3, ff: Vector3) -> void:
	var err := target - ball.global_position
	if _settle > 0.0:
		# Still pulling the ball in (from a rack, or up into form): gentler, no fumbles.
		ball.linear_velocity = (ff + err * BALL_GAIN).limit_length(ff.length() + 6.0)
		ball.angular_velocity *= 0.85
		return
	if err.length() > FUMBLE_DISTANCE:
		_let_go(ball.linear_velocity, ball.angular_velocity, false)
		fumbled.emit()
		return
	ball.linear_velocity = (ff + err * BALL_GAIN).limit_length(20.0)
	ball.angular_velocity *= 0.85


func _try_grab() -> void:
	for node in get_tree().get_nodes_in_group("balls"):
		var b := node as Ball
		if b == null or b.held:
			continue
		for hand in hands:
			if hand.global_position.distance_to(b.global_position) < GRAB_DISTANCE:
				ball = b
				state = State.HOLD
				_settle = SETTLE_TIME
				_stroke = 0.0
				_launch_pull = 0.0
				b.grab()
				_set_exception(b, true)
				_excepted[b] = INF
				grabbed_ball.emit(b)
				return


func _let_go(vel: Vector3, spin: Vector3, is_shot: bool) -> void:
	var b := ball
	ball = null
	state = State.EMPTY
	_stroke = 0.0
	b.release(vel, spin, is_shot)
	# Keep ignoring the ball briefly so it doesn't clip our own hands on release.
	_excepted[b] = 0.3


## Drops the ball without any throw (used when the round resets).
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
