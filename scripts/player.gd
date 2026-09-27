class_name Player
extends CharacterBody3D
## First-person archer with two floppy physics hands, Half Sword style: while
## you hold something, the mouse moves your hand, not the camera.
##
## Hold RMB to grab the bow, and keep holding it or you drop it. While you hold
## the bow, the mouse moves your bow arm; push past the edge of your reach to
## turn. Hold LMB to grab the string and haul it back to your cheek, let go to
## loose. The arrow flies along the line from your string hand through your bow
## hand. Hold full draw too long and your arm shakes, sags and gives out.
## Without a bow, holding LMB lets the mouse flail your right hand at things.

signal arrow_loosed(tip: Vector3, vel: Vector3, draw: float, accidental: bool)
signal dry_fired
signal bow_grabbed
signal bow_dropped

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 4.2
const MOUSE_SENS := 0.0022
const EYE_HEIGHT := 1.65

const HAND_RADIUS := 0.05
const REACH := 1.8
const UPPER_ARM := 0.3
const FOREARM := 0.3

# Floppy arms: an underdamped spring pulls each hand toward where it wants to be.
const HAND_SPRING := 450.0
const HAND_DAMP := 18.0
const HAND_MAX_SPEED := 30.0

# Mouse-driven hands (camera space).
const HAND_SENS := 0.0012 ## metres of hand travel per pixel of mouse
const HAND_MIN := Vector2(-0.5, -0.45) ## how far the hand can go before you turn instead
const HAND_MAX := Vector2(0.35, 0.35)
const HAND_DEPTH := -0.6
const BOW_HAND_START := Vector3(-0.06, -0.07, HAND_DEPTH)
const CHEEK_ANCHOR := Vector3(0.0, -0.06, 0.03) ## where the string hand pulls to

# Bow handling.
const BOW_GRAB_DISTANCE := 0.3
const STRING_GRAB_DISTANCE := 0.12
const BOW_CANT_DEG := 8.0 ## slight sideways tilt, like a real archer
const BOW_FOLLOW := 0.25 ## per tick; lower = heavier, laggier bow
const DRAW_SPEED := 1.3 ## draw per second when fresh; slows near full draw
const MIN_ARROW_SPEED := 6.0
const MAX_ARROW_SPEED := 62.0
const MIN_LOOSE_DRAW := 0.05
const SHAKE_DELAY := 1.5 ## seconds at full draw before the arm starts shaking
const SHAKE_GROWTH := 0.6 ## how fast the shaking gets worse
const MAX_SHAKE := 1.0
const SAG_SPEED := 0.05 ## m/s the tired bow arm droops at full shake
const CREEP_SPEED := 0.25 ## draw/s the tired string hand gives back at full shake
const SIGHT_DISTANCE := 25.0
const QUIVER := 10

var hud: Hud
var bow: Bow
var arrows_left := QUIVER
var pitch := 0.0

var head: Node3D
var camera: Camera3D
var hands: Array[RigidBody3D] = [] # 0 = left (bow), 1 = right (string)
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _gripping_string := false
var _pull := 0.0
var _bow_local := BOW_HAND_START
var _free_local := Vector3.ZERO
var _full_draw_time := 0.0
var _kick := 0.0
var _time := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = Util.LAYER_PLAYER
	collision_mask = Util.LAYER_WORLD | Util.LAYER_PROP

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
	camera.fov = 75.0
	camera.near = 0.02
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
		hand.global_position = camera.to_global(_idle_offset(i))
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("draw") and not _holding_bow():
		_free_local = _idle_offset(1)
	if event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		if _holding_bow():
			_bow_local = _move_hand(_bow_local, rel)
		elif Input.is_action_pressed("draw"):
			_free_local = _move_hand(_free_local, rel)
		else:
			_look(rel)


func _look(rel: Vector2) -> void:
	rotate_y(-rel.x * MOUSE_SENS)
	pitch = clampf(pitch - rel.y * MOUSE_SENS, -1.45, 1.45)
	head.rotation.x = pitch


## Moves a camera-space hand target with the mouse. Pushing past the edge of
## your reach turns your body instead, like dragging a sword around.
func _move_hand(local: Vector3, rel: Vector2) -> Vector3:
	var want := Vector2(local.x + rel.x * HAND_SENS, local.y - rel.y * HAND_SENS)
	var clamped := want.clamp(HAND_MIN, HAND_MAX)
	var overflow := want - clamped
	if overflow != Vector2.ZERO:
		_look(Vector2(overflow.x, -overflow.y) / HAND_SENS)
	return Vector3(clamped.x, clamped.y, HAND_DEPTH)


func _holding_bow() -> bool:
	return bow != null and bow.held


func _physics_process(delta: float) -> void:
	_time += delta
	_move(delta)
	_kick = move_toward(_kick, 0.0, delta * 1.5)

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var want_bow := captured and Input.is_action_pressed("bow")
	var want_string := captured and Input.is_action_pressed("draw")

	if _holding_bow() and not want_bow:
		_drop_bow()

	var targets: Array[Vector3] = [camera.to_global(_idle_offset(0)), camera.to_global(_idle_offset(1))]

	# Left hand: the bow.
	if _holding_bow():
		var shake := _shake_amount()
		_bow_local.y = maxf(HAND_MIN.y, _bow_local.y - SAG_SPEED * shake * delta)
		targets[0] = camera.to_global(_bow_local) + _shake_offset()
	elif want_bow:
		targets[0] = _reach_point(-0.1)
		_try_grab_bow()

	# Right hand: the string.
	if _holding_bow() and want_string:
		var nock_rest := bow.to_global(Vector3(0, 0, Bow.BRACE))
		if not _gripping_string:
			targets[1] = nock_rest
			if hands[1].global_position.distance_to(nock_rest) < STRING_GRAB_DISTANCE:
				_gripping_string = true
				_pull = 0.0
				bow.string_held = true
				bow.arrow_nocked = arrows_left > 0
		else:
			# Pulling gets harder the further back the string is, and a tired arm gives it back.
			_pull += delta * DRAW_SPEED * (1.0 - 0.7 * _pull) - delta * CREEP_SPEED * _shake_amount()
			_pull = clampf(_pull, 0.0, 1.0)
			targets[1] = nock_rest.lerp(camera.to_global(CHEEK_ANCHOR), _pull)
	elif _gripping_string:
		_loose(false)
	elif want_string:
		targets[1] = camera.to_global(_free_local)

	_drive_hands(targets, delta)
	if _holding_bow():
		_drive_bow(delta)
	_update_arms()
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
			# Got stuck somewhere silly; snap back.
			hand.global_position = targets[i]
			hand.linear_velocity = velocity
			continue
		var accel := err * HAND_SPRING + (velocity - hand.linear_velocity) * HAND_DAMP
		hand.linear_velocity = (hand.linear_velocity + accel * delta).limit_length(HAND_MAX_SPEED)


## The bow hangs off the left hand with some lag. Once the string is drawn it
## points along the line from the string hand through the bow hand.
func _drive_bow(delta: float) -> void:
	var grip := hands[0].global_position
	var aim_dir := (grip - camera.global_position).normalized()
	if _gripping_string:
		var along := grip - hands[1].global_position
		if along.length() > 0.1:
			aim_dir = aim_dir.lerp(along.normalized(), clampf(_pull * 3.0, 0.0, 1.0)).normalized()
	var up := camera.global_transform.basis.y
	var target := Basis.looking_at(aim_dir, up) * Basis(Vector3.BACK, deg_to_rad(BOW_CANT_DEG))
	var shake := _shake_amount()
	if shake > 0.0 or _kick > 0.0:
		var nx := (sin(_time * 13.0) + sin(_time * 29.0 + 1.3)) * 0.02 * shake + _kick
		var ny := (sin(_time * 11.0 + 0.7) + sin(_time * 23.0)) * 0.02 * shake
		target = target * Basis.from_euler(Vector3(nx, ny, 0.0))
	var current := bow.global_transform.basis.get_rotation_quaternion()
	var q := current.slerp(target.get_rotation_quaternion(), BOW_FOLLOW)
	bow.global_transform = Transform3D(Basis(q), grip)

	if _gripping_string:
		var drawn := grip.distance_to(hands[1].global_position)
		bow.draw = clampf((drawn - Bow.BRACE) / Bow.DRAW_LENGTH, 0.0, 1.0)
		if bow.draw > 0.85:
			_full_draw_time += delta
		else:
			_full_draw_time = maxf(0.0, _full_draw_time - delta * 2.0)
	else:
		_full_draw_time = 0.0


## Shows where the bow is pointing as a little dot on screen.
func _update_sight() -> void:
	if hud == null:
		return
	if not _holding_bow():
		hud.set_sight(false, Vector2.ZERO)
		return
	var dir := -bow.global_transform.basis.z
	var point := bow.global_position + dir * SIGHT_DISTANCE
	if camera.is_position_behind(point):
		hud.set_sight(false, Vector2.ZERO)
	else:
		hud.set_sight(true, camera.unproject_position(point))


func _shake_amount() -> float:
	return clampf((_full_draw_time - SHAKE_DELAY) * SHAKE_GROWTH, 0.0, MAX_SHAKE)


func _shake_offset() -> Vector3:
	var s := _shake_amount()
	if s <= 0.0:
		return Vector3.ZERO
	var b := camera.global_transform.basis
	return (b.x * sin(_time * 17.0) + b.y * sin(_time * 21.0 + 2.0)) * 0.012 * s


## Let go of the string. Fires the nocked arrow if there's any draw on it.
func _loose(accidental: bool) -> void:
	var draw := bow.draw
	_gripping_string = false
	_pull = 0.0
	_full_draw_time = 0.0
	var had_arrow := bow.arrow_nocked
	bow.arrow_nocked = false
	bow.release_string()
	if draw < MIN_LOOSE_DRAW:
		return
	if not had_arrow:
		dry_fired.emit()
		return
	arrows_left -= 1
	var dir := -bow.global_transform.basis.z
	var nock := bow.to_global(Vector3(0, 0, Bow.nock_z_for(draw)))
	var speed := lerpf(MIN_ARROW_SPEED, MAX_ARROW_SPEED, draw)
	arrow_loosed.emit(nock + dir * Arrow.LENGTH, dir * speed + velocity, draw, accidental)
	# Recoil: the bow kicks up and the string hand flies back past your ear.
	_kick = 0.08 * draw
	hands[1].linear_velocity += (-dir * 2.0 + camera.global_transform.basis.x * 1.0) * draw


func _drop_bow() -> void:
	if _gripping_string:
		_loose(true)
	var spin := camera.global_transform.basis.x * randf_range(-3.0, 3.0)
	bow.drop(hands[0].linear_velocity, spin)
	bow_dropped.emit()


func _try_grab_bow() -> void:
	if bow == null or bow.held:
		return
	if hands[0].global_position.distance_to(bow.global_position) < BOW_GRAB_DISTANCE:
		bow.pick_up()
		_bow_local = BOW_HAND_START
		bow_grabbed.emit()


func _reach_point(side: float) -> Vector3:
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var mask := Util.LAYER_WORLD | Util.LAYER_PROP | Util.LAYER_BOW
	var query := PhysicsRayQueryParameters3D.create(from, from + fwd * REACH, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var side_offset := camera.global_transform.basis.x * side
	if hit.is_empty():
		return from + fwd * 0.95 + side_offset
	var pos: Vector3 = hit["position"]
	return pos - fwd * 0.04 + side_offset


func _idle_offset(i: int) -> Vector3:
	return Vector3(-0.24 if i == 0 else 0.24, -0.32, -0.42)


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
