extends Node3D
## Builds the outdoor court and runs the three-point contest:
## five racks of five balls around the arc, the last ball on each rack is a
## money ball worth 2. The clock starts when you pick up your first ball.

enum RoundState { READY, RUNNING, OVER }

const ROUND_TIME := 60.0
const RACKS := 5
const BALLS_PER_RACK := 5
const BALL_SPACING := 0.28
const RACK_HEIGHT := 0.85
const THREE_RADIUS := 6.75
const CORNER_X := 6.6
const BASELINE_Z := -1.575
const COURT_HALF_WIDTH := 7.5
const HALF_COURT_Z := 12.425
const FENCE_X := 11.0
const FENCE_NORTH := -5.0
const FENCE_SOUTH := 15.0
const PLAYER_SPAWN := Vector3(0.0, 0.1, 8.6)
const SAVE_PATH := "user://save.cfg"

var hoop: Hoop
var player: Player
var hud: Hud
var balls: Array[Ball] = []
var ball_homes: Array[Vector3] = []

var round_state := RoundState.READY
var time_left := ROUND_TIME
var score := 0
var made := 0
var best := 0
var _end_countdown := -1.0


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_ground_and_fence()
	_build_court_markings()

	hoop = Hoop.new()
	add_child(hoop)

	_build_racks()

	player = Player.new()
	player.position = PLAYER_SPAWN
	add_child(player)
	hud = Hud.new()
	add_child(hud)
	player.hud = hud
	player.grabbed_ball.connect(_on_player_grabbed)
	player.hoop = hoop
	player.fumbled.connect(func() -> void: hud.flash("Fumble!", Color(1.0, 0.6, 0.3)))
	player.threw_ball.connect(_on_player_threw)

	best = _load_best()
	_reset_round()
	hud.set_banner("Click to play\nGrab a ball from a rack to start the clock")


func _process(delta: float) -> void:
	if round_state == RoundState.RUNNING:
		time_left -= delta
		if _end_countdown > 0.0:
			_end_countdown -= delta
		if time_left <= 0.0 or (_end_countdown > -1.0 and _end_countdown <= 0.0):
			_finish_round()
	hud.set_clock(time_left, round_state == RoundState.RUNNING)
	hud.set_stats(score, made, _attempts(), best, _rack_text())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_reset_round()


# --- Contest ---------------------------------------------------------------

func _reset_round() -> void:
	player.force_drop()
	for i in balls.size():
		balls[i].rack_at(ball_homes[i])
	round_state = RoundState.READY
	time_left = ROUND_TIME
	score = 0
	made = 0
	_end_countdown = -1.0
	hud.set_banner("")


func _finish_round() -> void:
	round_state = RoundState.OVER
	time_left = maxf(time_left, 0.0)
	var text := "Final score: %d / %d   (%d of %d made)" % [score, RACKS * (BALLS_PER_RACK + 1), made, _attempts()]
	if score > best:
		best = score
		_save_best(best)
		text += "\nNew best!"
	hud.set_banner(text + "\nPress R to go again")


func _on_player_grabbed(b: Ball) -> void:
	if round_state == RoundState.READY and b.live:
		round_state = RoundState.RUNNING
	if b.is_money and b.live:
		hud.flash("Money ball", Color(1.0, 0.85, 0.3))


func _on_player_threw(_b: Ball, speed: float) -> void:
	if speed > 16.0:
		hud.flash("YEET", Color(0.6, 0.9, 1.0))


func _on_ball_airballed(_b: Ball) -> void:
	hud.flash("AIRBALL", Color(1.0, 0.4, 0.35))


func _on_ball_scored(b: Ball) -> void:
	if not b.in_flight_shot:
		return
	b.in_flight_shot = false
	var kind := "Swish!"
	if b.touched_board:
		kind = "Bank!"
	elif b.touched_rim:
		kind = "Bucket"
	if round_state == RoundState.RUNNING and b.live:
		var points := 2 if b.is_money else 1
		score += points
		made += 1
		b.live = false
		var color := Color(1.0, 0.85, 0.3) if b.is_money else Color.WHITE
		hud.flash("%s  +%d" % [kind, points], color)
	else:
		hud.flash(kind, Color(0.8, 0.8, 0.8))


func _physics_process(_delta: float) -> void:
	# Once every ball has been shot, give the last one a moment to land.
	if round_state == RoundState.RUNNING and _end_countdown <= -1.0 and _attempts() >= balls.size():
		_end_countdown = 3.5


func _attempts() -> int:
	var n := 0
	for b in balls:
		if b.shots > 0:
			n += 1
	return n


func _rack_text() -> String:
	var left := 0
	for b in balls:
		if b.shots == 0 and not b.held:
			left += 1
	return "Balls left  %d" % left


func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 0
	return int(cfg.get_value("contest", "best", 0))


func _save_best(value: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("contest", "best", value)
	cfg.save(SAVE_PATH)


# --- Input map ---------------------------------------------------------------

func _setup_input() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("drop", [KEY_Q])
	_bind_keys("restart", [KEY_R])
	_bind_mouse("grab", MOUSE_BUTTON_LEFT)


func _bind_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _bind_mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# --- World building ------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.5, 0.8)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.75, 0.82, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)


func _build_ground_and_fence() -> void:
	var floor_body := Util.static_box(Vector3(60.0, 1.0, 60.0), null, Util.surface(0.0, 0.8))
	floor_body.add_to_group("floor")
	floor_body.position = Vector3(0.0, -0.5, 5.0)
	add_child(floor_body)

	var width := FENCE_X * 2.0
	var depth := FENCE_SOUTH - FENCE_NORTH
	var center_z := (FENCE_NORTH + FENCE_SOUTH) * 0.5
	_plane(Vector2(width, depth), Vector3(0.0, 0.0, center_z), Util.material(Color(0.22, 0.22, 0.24), 0.95))
	var court_depth := HALF_COURT_Z - BASELINE_Z
	_plane(Vector2(COURT_HALF_WIDTH * 2.0, court_depth), Vector3(0.0, 0.002, BASELINE_Z + court_depth * 0.5),
			Util.material(Color(0.16, 0.36, 0.55), 0.85))
	_plane(Vector2(4.9, 5.8), Vector3(0.0, 0.003, BASELINE_Z + 2.9), Util.material(Color(0.62, 0.2, 0.18), 0.85))

	# Chain-link fence: tall invisible walls so balls stay in play, lattice visuals.
	var fence_mat := Util.shader_material(Util.LATTICE_SHADER)
	fence_mat.set_shader_parameter("color", Color(0.55, 0.58, 0.6))
	fence_mat.set_shader_parameter("thickness", 0.06)
	var fence_h := 4.0
	var sides := [
		[Vector3(0.0, 0.0, FENCE_NORTH), Vector2(width, fence_h), 0.0],
		[Vector3(0.0, 0.0, FENCE_SOUTH), Vector2(width, fence_h), 0.0],
		[Vector3(-FENCE_X, 0.0, center_z), Vector2(depth, fence_h), PI * 0.5],
		[Vector3(FENCE_X, 0.0, center_z), Vector2(depth, fence_h), PI * 0.5],
	]
	for side in sides:
		var pos: Vector3 = side[0]
		var size: Vector2 = side[1]
		var yaw: float = side[2]
		var wall := Util.static_box(Vector3(size.x, 8.0, 0.4), null, Util.surface(0.0, 0.6))
		wall.position = pos + Vector3(0.0, 4.0, 0.0)
		wall.rotation.y = yaw
		add_child(wall)
		var quad := QuadMesh.new()
		quad.size = size
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = fence_mat.duplicate()
		(mi.material_override as ShaderMaterial).set_shader_parameter("cells", size / 0.18)
		mi.position = pos + Vector3(0.0, fence_h * 0.5, 0.0)
		mi.rotation.y = yaw
		add_child(mi)


func _plane(size: Vector2, pos: Vector3, mat: Material) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _build_court_markings() -> void:
	var line_mat := Util.material(Color(0.95, 0.95, 0.95), 0.9)
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var w := 0.05

	# Three-point line: straight in the corners, then the arc.
	var corner_z := sqrt(THREE_RADIUS * THREE_RADIUS - CORNER_X * CORNER_X)
	var phi := asin(CORNER_X / THREE_RADIUS)
	var three := PackedVector2Array([Vector2(-CORNER_X, BASELINE_Z), Vector2(-CORNER_X, corner_z)])
	three.append_array(_arc(Vector2.ZERO, THREE_RADIUS, -phi, phi, 64))
	three.append(Vector2(CORNER_X, BASELINE_Z))
	_ribbon(three, w, line_mat)

	var ft_z := BASELINE_Z + 5.8
	_ribbon(PackedVector2Array([
		Vector2(-2.45, BASELINE_Z), Vector2(-2.45, ft_z), Vector2(2.45, ft_z), Vector2(2.45, BASELINE_Z),
	]), w, line_mat)
	_ribbon(_arc(Vector2(0.0, ft_z), 1.8, 0.0, TAU, 48), w, line_mat)
	_ribbon(PackedVector2Array([
		Vector2(-COURT_HALF_WIDTH, BASELINE_Z), Vector2(COURT_HALF_WIDTH, BASELINE_Z),
		Vector2(COURT_HALF_WIDTH, HALF_COURT_Z), Vector2(-COURT_HALF_WIDTH, HALF_COURT_Z),
		Vector2(-COURT_HALF_WIDTH, BASELINE_Z),
	]), w, line_mat)


## Points on a circle in the XZ plane (x = sin, z = cos, so angle 0 faces +Z).
func _arc(center: Vector2, radius: float, from: float, to: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / steps)
		pts.append(center + Vector2(sin(a), cos(a)) * radius)
	return pts


## A flat strip following a polyline (x, z) just above the court.
func _ribbon(pts: PackedVector2Array, width: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.005
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		var s := Vector2(-d.y, d.x) * width * 0.5
		var quad := [
			Vector3(a.x - s.x, y, a.y - s.y), Vector3(a.x + s.x, y, a.y + s.y), Vector3(b.x + s.x, y, b.y + s.y),
			Vector3(a.x - s.x, y, a.y - s.y), Vector3(b.x + s.x, y, b.y + s.y), Vector3(b.x - s.x, y, b.y - s.y),
		]
		for v in quad:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_racks() -> void:
	var rack_mat := Util.material(Color(0.75, 0.75, 0.78), 0.35, 0.7)
	var cup_mat := Util.material(Color(0.15, 0.15, 0.17), 0.6)
	for r in RACKS:
		var xf := _rack_transform(r)
		var tangent := xf.basis.x
		var table := Util.static_box(Vector3(BALL_SPACING * BALLS_PER_RACK + 0.1, RACK_HEIGHT, 0.4), rack_mat)
		table.transform = Transform3D(xf.basis, xf.origin + Vector3.UP * RACK_HEIGHT * 0.5)
		add_child(table)
		for k in BALLS_PER_RACK:
			var money := k == BALLS_PER_RACK - 1
			var slot := xf.origin + tangent * (k - (BALLS_PER_RACK - 1) * 0.5) * BALL_SPACING
			var home := slot + Vector3.UP * (RACK_HEIGHT + Ball.RADIUS + 0.01)

			var cup := TorusMesh.new()
			cup.inner_radius = 0.07
			cup.outer_radius = 0.1
			var cup_mi := MeshInstance3D.new()
			cup_mi.mesh = cup
			cup_mi.material_override = cup_mat
			cup_mi.position = slot + Vector3.UP * (RACK_HEIGHT + 0.01)
			add_child(cup_mi)

			var b := Ball.new(money)
			b.hoop = hoop
			b.position = home
			add_child(b)
			b.scored.connect(_on_ball_scored)
			b.airballed.connect(_on_ball_airballed)
			balls.append(b)
			ball_homes.append(home)


## Rack placement: two corners, two wings, top of the key. The rack sits just
## outside the line and a step to the side, so you shoot from beside it.
func _rack_transform(i: int) -> Transform3D:
	var pos: Vector3
	var tangent: Vector3
	match i:
		0:
			pos = Vector3(-7.2, 0.0, 1.1)
			tangent = Vector3(0.0, 0.0, 1.0)
		4:
			pos = Vector3(7.2, 0.0, 1.1)
			tangent = Vector3(0.0, 0.0, -1.0)
		_:
			var phi := deg_to_rad([-45.0, 0.0, 45.0][i - 1] as float)
			var radial := Vector3(sin(phi), 0.0, cos(phi))
			tangent = Vector3(radial.z, 0.0, -radial.x)
			pos = radial * (THREE_RADIUS + 0.95) + tangent * 1.0
	return Transform3D(Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP)), pos)
