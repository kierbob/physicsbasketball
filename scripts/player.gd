class_name Player
extends CharacterBody3D
## First-person archer with two floppy physics hands.
##
## Click while looking at the bow to grab it, Q to drop it. Hold LMB to grab the
## string and haul it back, let go to loose. Hold RMB to zoom. The mouse always
## turns the camera (smoothed); the heavy bow swings after your aim with some
## lag, and holding full draw too long makes your arm shake.

signal arrow_loosed(tip: Vector3, vel: Vector3, draw: float, accidental: bool)
signal bow_grabbed
signal bow_dropped

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 4.2
const EYE_HEIGHT := 1.65

# Camera.
const MOUSE_SENS := 0.0022
const LOOK_SMOOTH := 28.0 ## higher = snappier, lower = smoother
const FOV := 80.0
const ZOOM_FOV := 40.0
const ZOOM_SMOOTH := 10.0
## Camera sits a little back and to the right of your eyes so the bow doesn't
## cover the middle of the screen.
const CAMERA_OFFSET := Vector3(0.12, 0.06, 0.16)

const HAND_RADIUS := 0.05
const REACH := 1.8
const UPPER_ARM := 0.3
const FOREARM := 0.3

# Floppy arms: an underdamped spring pulls each hand toward where it wants to be.
const HAND_SPRING := 450.0
const HAND_DAMP := 18.0
const HAND_MAX_SPEED := 30.0

# Bow handling (hand offsets are in head space).
const PICKUP_RANGE := 3.5
const PICKUP_CONE := 0.9 ## cosine of how directly you must look at the bow
const PICKUP_TIMEOUT := 1.5
const BOW_GRAB_DISTANCE := 0.3
const STRING_GRAB_DISTANCE := 0.12
const STRING_GRAB_TIMEOUT := 0.3
const BOW_HAND_OFFSET := Vector3(-0.12, -0.12, -0.6)
const BOW_CANT_DEG := 12.0 ## sideways tilt, like a real archer
const BOW_FOLLOW := 0.3 ## per tick; lower = heavier, laggier bow
const AIM_RANGE := 150.0

# War bow: heavy draw, fast arrows.
const DRAW_SPEED := 1.6 ## draw per second when fresh; slows near full draw
const MIN_ARROW_SPEED := 25.0
const MAX_ARROW_SPEED := 85.0
const MIN_LOOSE_DRAW := 0.05
const SHAKE_DELAY := 2.5 ## seconds at full draw before the arm starts shaking
const SHAKE_GROWTH := 0.5
const MAX_SHAKE := 1.0

var hud: Hud
var bow: Bow
var pitch := 0.0

var head: Node3D
var camera: Camera3D
var hands: Array[RigidBody3D] = [] # 0 = left (bow), 1 = right (string)
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw_target := 0.0
var _pitch_target := 0.0
var _reaching_for_bow := false
var _reach_time := 0.0
var _draw_armed := false
var _gripping_string := false
var _string_reach_time := 0.0
var _pull := 0.0
var _full_draw_time := 0.0
var _kick := 0.0
var _time := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = Util.LAYER_PLAYER
	collision_mask = Util.LAYER_WORLD | Util.LAYER_PROP
	_yaw_target = rotation.y

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
	camera.fov = FOV
	camera.near = 0.02
	camera.position = CAMERA_OFFSET
	head.add_child(camera)
	camera.current = true

	var skin := Util.material(Color(0.87, 0.66, 0.52), 0.7)
	var sleeve := Util.material(Color(0.2, 0.45, 0.25), 0.8)
	for i in 2:
		var hand := RigidBody3D.new()
		hand.top_level = true
		hand.gravity_scale = 0.0
		hand.mass = 1.0
		hand.lock_rotation = true
		hand.collision_layer = Util.LAYER_HAND
		hand.collision_mask = Util.LAYER_WORLD | Util.LAYER_PROP
		var sphere := SphereShape3D.new()
		sphere.radius = HAND_RADIUS
		var hand_col := CollisionShape3D.new()
		hand_col.shape = sphere
		hand.add_child(hand_col)
		var hand_mesh := SphereMesh.new()
		hand_mesh.radius = HAND_RADIUS + 0.005
		hand_mesh.height = HAND_RADIUS * 1.8
		var hand_mi := MeshInstance3D.new()
		hand_mi.mesh = hand_mesh
		hand_mi.material_override = skin
		hand.add_child(hand_mi)
		add_child(hand)
		hand.global_position = head.to_global(_idle_offset(i))
		hands.append(hand)

		var upper := Util.cylinder(0.045, sleeve, 10)
		upper.top_level = true
		upper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(upper)
		_upper_arms.append(upper)
		var fore := Util.cylinder(0.035, skin, 10)
		fore.top_level = true
		fore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fore)
		_forearms.append(fore)


# --- Input and camera ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		# Zoomed in, the same mouse movement turns you less, so aim stays steady.
		var sens := MOUSE_SENS * camera.fov / FOV
		_yaw_target -= rel.x * sens
		_pitch_target = clampf(_pitch_target - rel.y * sens, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed and not _holding_bow():
		_start_pickup()
	elif event.is_action_pressed("drop") and _holding_bow():
		_drop_bow()


## Camera turning happens every rendered frame (not physics tick) and is eased,
## so it stays smooth whatever you're doing with your hands.
func _process(delta: float) -> void:
	var t := 1.0 - exp(-LOOK_SMOOTH * delta)
	rotation.y = lerp_angle(rotation.y, _yaw_target, t)
	pitch = lerpf(pitch, _pitch_target, t)
	head.rotation.x = pitch
	var zooming := Input.is_action_pressed("zoom") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var fov_target := ZOOM_FOV if zooming else FOV
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-ZOOM_SMOOTH * delta))
	_update_arms()


func _holding_bow() -> bool:
	return bow != null and bow.held


# --- Simulation ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	_move(delta)
	_kick = move_toward(_kick, 0.0, delta * 1.5)

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var want_string := captured and Input.is_action_pressed("draw")
	if not want_string:
		_draw_armed = true

	var targets: Array[Vector3] = [head.to_global(_idle_offset(0)), head.to_global(_idle_offset(1))]

	# Left hand: the bow.
	if _holding_bow():
		targets[0] = head.to_global(BOW_HAND_OFFSET) + _shake_offset()
	elif _reaching_for_bow:
		_reach_time += delta
		targets[0] = bow.global_position
		if hands[0].global_position.distance_to(bow.global_position) < BOW_GRAB_DISTANCE:
			_reaching_for_bow = false
			bow.pick_up()
			bow_grabbed.emit()
		elif _reach_time > PICKUP_TIMEOUT:
			_reaching_for_bow = false

	# Right hand: the string.
	if _holding_bow() and want_string and _draw_armed:
		var nock_rest := bow.to_global(Vector3(0, 0, Bow.BRACE))
		if not _gripping_string:
			targets[1] = nock_rest
			_string_reach_time += delta
			var near := hands[1].global_position.distance_to(nock_rest) < STRING_GRAB_DISTANCE
			if near or _string_reach_time > STRING_GRAB_TIMEOUT:
				_gripping_string = true
				_pull = 0.0
				bow.string_held = true
				bow.arrow_nocked = true
		else:
			# Heavy war bow: the last bit of the draw is the hardest.
			_pull = minf(1.0, _pull + delta * DRAW_SPEED * (1.0 - 0.6 * _pull))
			targets[1] = bow.to_global(Vector3(0, 0, Bow.nock_z_for(_pull)))
	elif _gripping_string:
		_loose(false)
	else:
		_string_reach_time = 0.0
		if want_string and not _holding_bow():
			# No bow: just poke at things.
			targets[1] = _reach_point(0.1)

	_drive_hands(targets, delta)
	if _holding_bow():
		_drive_bow(delta)
	_update_sight()


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

	# CharacterBody3D doesn't push rigid bodies on its own; shove loose props.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider()
		if body is RigidBody3D and not (body as RigidBody3D).freeze:
			var push := -c.get_normal() * minf(velocity.length(), 6.0) * 0.08
			(body as RigidBody3D).apply_central_impulse(push)


func _drive_hands(targets: Array[Vector3], delta: float) -> void:
	for i in 2:
		var hand := hands[i]
		var err := targets[i] - hand.global_position
		if err.length() > 1.5:
			# Got stuck somewhere silly (or stretched for the bow); snap.
			hand.global_position = targets[i]
			hand.linear_velocity = velocity
			continue
		var accel := err * HAND_SPRING + (velocity - hand.linear_velocity) * HAND_DAMP
		hand.linear_velocity = (hand.linear_velocity + accel * delta).limit_length(HAND_MAX_SPEED)


## The bow hangs off the left hand and swings after your aim with some lag.
## It's angled up so a full-draw arrow drops right onto the crosshair.
func _drive_bow(delta: float) -> void:
	var grip := hands[0].global_position
	var aim_dir := _ballistic_dir(grip, _aim_point(), MAX_ARROW_SPEED)
	var target := Basis.looking_at(aim_dir, head.global_transform.basis.y)
	target = target * Basis(Vector3.BACK, deg_to_rad(BOW_CANT_DEG))
	var shake := _shake_amount()
	if shake > 0.0 or _kick > 0.0:
		var nx := (sin(_time * 13.0) + sin(_time * 29.0 + 1.3)) * 0.02 * shake + _kick
		var ny := (sin(_time * 11.0 + 0.7) + sin(_time * 23.0)) * 0.02 * shake
		target = target * Basis.from_euler(Vector3(nx, ny, 0.0))
	var current := bow.global_transform.basis.get_rotation_quaternion()
	var q := current.slerp(target.get_rotation_quaternion(), BOW_FOLLOW)
	bow.global_transform = Transform3D(Basis(q), grip)

	if _gripping_string:
		var local := bow.to_local(hands[1].global_position)
		bow.draw = clampf((local.z - Bow.BRACE) / Bow.DRAW_LENGTH, 0.0, 1.0)
		if bow.draw > 0.85:
			_full_draw_time += delta
		else:
			_full_draw_time = maxf(0.0, _full_draw_time - delta * 2.0)
	else:
		_full_draw_time = 0.0


## What the crosshair is on (or a point far away along it).
func _aim_point() -> Vector3:
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + fwd * AIM_RANGE, Util.LAYER_WORLD | Util.LAYER_PROP)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return from + fwd * AIM_RANGE
	return hit["position"]


## Launch direction that hits `to` from `from` at `speed` (the low arc).
func _ballistic_dir(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var d := to - from
	var flat := Vector3(d.x, 0.0, d.z)
	var x := flat.length()
	if x < 0.5:
		return d.normalized()
	var y := d.y
	var v2 := speed * speed
	var disc := v2 * v2 - _gravity * (_gravity * x * x + 2.0 * y * v2)
	if disc < 0.0:
		# Out of range: 45 degrees is as far as it goes.
		return (flat.normalized() + Vector3.UP).normalized()
	var angle := atan((v2 - sqrt(disc)) / (_gravity * x))
	return (flat.normalized() * cos(angle) + Vector3.UP * sin(angle)).normalized()


func _arrow_speed(draw: float) -> float:
	return lerpf(MIN_ARROW_SPEED, MAX_ARROW_SPEED, draw)


## Traces where an arrow loosed right now would land and puts a dot there.
func _update_sight() -> void:
	if hud == null:
		return
	if not _holding_bow():
		hud.set_sight(false, Vector2.ZERO)
		return
	var dir := -bow.global_transform.basis.z
	var pos := bow.to_global(Vector3(0, 0, Bow.nock_z_for(bow.draw))) + dir * Arrow.LENGTH
	var vel := dir * _arrow_speed(bow.draw) + velocity
	var space := get_world_3d().direct_space_state
	var step := 1.0 / 20.0
	for i in 60:
		var next := pos + vel * step
		vel += Vector3.DOWN * _gravity * step
		var query := PhysicsRayQueryParameters3D.create(pos, next, Util.LAYER_WORLD | Util.LAYER_PROP)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			next = hit["position"]
			pos = next
			break
		pos = next
	if camera.is_position_behind(pos):
		hud.set_sight(false, Vector2.ZERO)
	else:
		hud.set_sight(true, camera.unproject_position(pos))


func _shake_amount() -> float:
	return clampf((_full_draw_time - SHAKE_DELAY) * SHAKE_GROWTH, 0.0, MAX_SHAKE)


func _shake_offset() -> Vector3:
	var s := _shake_amount()
	if s <= 0.0:
		return Vector3.ZERO
	var b := head.global_transform.basis
	return (b.x * sin(_time * 17.0) + b.y * sin(_time * 21.0 + 2.0)) * 0.012 * s


## Let go of the string. Fires the nocked arrow if there's any draw on it.
func _loose(accidental: bool) -> void:
	var draw := bow.draw
	_gripping_string = false
	_string_reach_time = 0.0
	_pull = 0.0
	_full_draw_time = 0.0
	var had_arrow := bow.arrow_nocked
	bow.arrow_nocked = false
	bow.release_string()
	if draw < MIN_LOOSE_DRAW or not had_arrow:
		return
	var dir := -bow.global_transform.basis.z
	var nock := bow.to_global(Vector3(0, 0, Bow.nock_z_for(draw)))
	arrow_loosed.emit(nock + dir * Arrow.LENGTH, dir * _arrow_speed(draw) + velocity, draw, accidental)
	# Recoil: the bow kicks up and the string hand flies back past your ear.
	_kick = 0.06 * draw
	hands[1].linear_velocity += (-dir * 2.0 + head.global_transform.basis.x * 1.0) * draw


## Click while looking at the bow: your hand goes and gets it.
func _start_pickup() -> void:
	if bow == null or _reaching_for_bow:
		return
	var to_bow := bow.global_position - camera.global_position
	var fwd := -camera.global_transform.basis.z
	if to_bow.length() > PICKUP_RANGE or fwd.dot(to_bow.normalized()) < PICKUP_CONE:
		return
	_reaching_for_bow = true
	_reach_time = 0.0
	_draw_armed = false


func _drop_bow() -> void:
	if _gripping_string:
		_loose(true)
	var spin := head.global_transform.basis.x * randf_range(-3.0, 3.0)
	bow.drop(hands[0].linear_velocity, spin)
	bow_dropped.emit()


func _reach_point(side: float) -> Vector3:
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var mask := Util.LAYER_WORLD | Util.LAYER_PROP | Util.LAYER_BOW
	var query := PhysicsRayQueryParameters3D.create(from, from + fwd * REACH, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var side_offset := head.global_transform.basis.x * side
	if hit.is_empty():
		return from + fwd * 0.95 + side_offset
	var pos: Vector3 = hit["position"]
	return pos - fwd * 0.04 + side_offset


func _idle_offset(i: int) -> Vector3:
	return Vector3(-0.24 if i == 0 else 0.24, -0.32, -0.42)


func _update_arms() -> void:
	var head_basis := head.global_transform.basis
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var shoulder := head.to_global(Vector3(0.2 * s, -0.27, 0.1))
		var hand := hands[i].global_position
		var pole := head_basis * Vector3(0.6 * s, -1.0, 0.2)
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
