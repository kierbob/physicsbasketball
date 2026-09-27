extends Node3D
## Builds the archery range and keeps score.
##
## Ten arrows per round. Targets score their ring (10 for the bullseye) times
## a distance multiplier; balloons and melons are worth a bonus, and the crates
## are just there to be knocked over. R reloads the whole range.

const SAVE_PATH := "user://archery.cfg"
const PLAYER_SPAWN := Vector3(0.0, 0.1, 2.0)
const BALLOON_POINTS := 15
const MELON_POINTS := 10
const BALLOONS := 8

var player: Player
var hud: Hud
var bow: Bow

var score := 0
var best := 0
var _in_flight := 0
var _round_over := false


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_ground()
	_build_targets()
	_build_props()

	bow = Bow.new()
	bow.position = Vector3(0.8, 0.86, -0.8)
	bow.rotation = Vector3(0.0, 0.0, PI * 0.5) # lying flat on the table
	add_child(bow)

	player = Player.new()
	player.position = PLAYER_SPAWN
	add_child(player)
	player.bow = bow
	hud = Hud.new()
	add_child(hud)
	player.hud = hud
	player.arrow_loosed.connect(_on_arrow_loosed)
	player.dry_fired.connect(func() -> void: hud.flash("*twang*  (out of arrows)", Color(0.8, 0.8, 0.8)))
	player.bow_dropped.connect(func() -> void: hud.flash("dropped the bow lol", Color(1.0, 0.7, 0.4)))

	best = _load_best()
	hud.set_banner("Click to play\nWalk to the table and hold RMB on the bow to pick it up")
	player.bow_grabbed.connect(func() -> void: hud.set_banner(""), CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	hud.set_stats(score, player.arrows_left, best)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


# --- Arrows and scoring ------------------------------------------------------

func _on_arrow_loosed(tip: Vector3, vel: Vector3, draw: float, accidental: bool) -> void:
	var arrow := Arrow.new()
	arrow.velocity = vel
	arrow.position = tip
	add_child(arrow)
	arrow.hit.connect(_on_arrow_hit)
	arrow.finished.connect(_on_arrow_finished)
	_in_flight += 1
	if accidental:
		hud.flash("Oops", Color(1.0, 0.7, 0.4))
	elif draw < 0.25:
		hud.flash("pfft", Color(0.8, 0.8, 0.8))


func _on_arrow_hit(_arrow: Arrow, body: Node, point: Vector3) -> void:
	if body is ArcheryTarget:
		var target := body as ArcheryTarget
		var ring := target.ring_at(point)
		if ring == 0:
			return
		var points := ring * target.multiplier
		score += points
		if ring == 10:
			hud.flash("BULLSEYE!  +%d" % points, Color(1.0, 0.85, 0.2))
		elif target.multiplier > 1:
			hud.flash("%d × %d  +%d" % [ring, target.multiplier, points])
		else:
			hud.flash("%d  +%d" % [ring, points])
	elif body is Balloon:
		(body as Balloon).pop()
		score += BALLOON_POINTS
		hud.flash("POP!  +%d" % BALLOON_POINTS, Color(0.6, 0.9, 1.0))
	elif body.is_in_group("melon") and not body.has_meta("scored"):
		body.set_meta("scored", true)
		score += MELON_POINTS
		hud.flash("Melon!  +%d" % MELON_POINTS, Color(0.5, 1.0, 0.4))
	elif body.is_in_group("player"):
		hud.flash("OW. You shot yourself.", Color(1.0, 0.4, 0.35))


func _on_arrow_finished(_arrow: Arrow) -> void:
	_in_flight -= 1
	if player.arrows_left == 0 and _in_flight <= 0 and not _round_over:
		_round_over = true
		var text := "Final score: %d" % score
		if score > best:
			best = score
			_save_best(best)
			text += "\nNew best!"
		hud.set_banner(text + "\nPress R to go again")


func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 0
	return int(cfg.get_value("range", "best", 0))


func _save_best(value: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("range", "best", value)
	cfg.save(SAVE_PATH)


# --- Input map ---------------------------------------------------------------

func _setup_input() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("restart", [KEY_R])
	_bind_mouse("draw", MOUSE_BUTTON_LEFT)
	_bind_mouse("bow", MOUSE_BUTTON_RIGHT)


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
	sky_mat.ground_horizon_color = Color(0.45, 0.55, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.82, 0.9)
	env.fog_density = 0.004
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _build_ground() -> void:
	var ground := Util.static_box(Vector3(400.0, 1.0, 400.0), null, Util.surface(0.0, 0.9))
	ground.add_to_group("ground")
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child(ground)
	_plane(Vector2(400.0, 400.0), Vector3(0.0, 0.0, 0.0), Util.material(Color(0.3, 0.5, 0.22), 1.0))
	# Mowed stripes down the range.
	for i in 8:
		var z := -2.0 - 7.0 * i
		var shade := Color(0.34, 0.56, 0.25) if i % 2 == 0 else Color(0.29, 0.49, 0.21)
		_plane(Vector2(24.0, 7.0), Vector3(0.0, 0.003, z - 3.5), Util.material(shade, 1.0))
	# Shooting line.
	_plane(Vector2(24.0, 0.08), Vector3(0.0, 0.006, 0.4), Util.material(Color(0.95, 0.95, 0.95), 0.9))

	var table := Util.static_box(Vector3(1.4, 0.8, 0.6), Util.material(Color(0.45, 0.3, 0.18), 0.8))
	table.position = Vector3(0.8, 0.4, -0.8)
	add_child(table)

	var hay := Util.material(Color(0.8, 0.68, 0.35), 1.0)
	var backstop := Util.static_box(Vector3(32.0, 4.0, 1.5), hay)
	backstop.position = Vector3(0.0, 2.0, -54.0)
	add_child(backstop)


func _plane(size: Vector2, pos: Vector3, mat: Material) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _build_targets() -> void:
	# [x, distance, multiplier]
	var layout := [[-3.0, 10.0, 1], [2.5, 20.0, 2], [-2.0, 30.0, 3], [3.0, 45.0, 4]]
	var wood := Util.material(Color(0.4, 0.28, 0.16), 0.8)
	for entry in layout:
		var x: float = entry[0]
		var dist: float = entry[1]
		var mult: int = entry[2]
		var center := Vector3(x, 1.3, -dist)
		var target := ArcheryTarget.new()
		target.multiplier = mult
		target.position = center
		# Face (+Y) toward the shooter, leaning back a little.
		target.rotation = Vector3(deg_to_rad(75.0), 0.0, 0.0)
		add_child(target)
		for side in [-1.0, 1.0]:
			var leg := Util.static_box(Vector3(0.08, 1.9, 0.08), wood)
			leg.position = center + Vector3(0.45 * side, -0.4, -0.35)
			leg.rotation = Vector3(deg_to_rad(-12.0), 0.0, 0.0)
			add_child(leg)
		var label := Label3D.new()
		label.text = "%d m   ×%d" % [int(dist), mult]
		label.font_size = 96
		label.pixel_size = 0.004 * (1.0 + dist / 25.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 16
		label.position = center + Vector3(0.0, 1.0 + dist / 60.0, 0.0)
		add_child(label)


func _build_props() -> void:
	# A crate pyramid to knock over.
	var crate_mat := Util.material(Color(0.6, 0.42, 0.22), 0.8)
	var size := 0.5
	for row in 3:
		for i in 3 - row:
			var crate := _rigid_box(Vector3.ONE * size, crate_mat, 3.0)
			var x := 7.0 + (i - (2 - row) * 0.5) * (size + 0.02)
			crate.position = Vector3(x, size * (row + 0.5) + 0.01, -14.0)
			add_child(crate)

	# Melons on posts.
	var post_mat := Util.material(Color(0.5, 0.36, 0.2), 0.8)
	var melon_mat := Util.material(Color(0.25, 0.55, 0.2), 0.5)
	for pos in [Vector3(-7.0, 0.0, -12.0), Vector3(-6.0, 0.0, -24.0), Vector3(7.5, 0.0, -28.0)]:
		var post := Util.static_box(Vector3(0.1, 1.2, 0.1), post_mat)
		post.position = pos + Vector3(0.0, 0.6, 0.0)
		add_child(post)
		var melon := RigidBody3D.new()
		melon.add_to_group("melon")
		melon.mass = 2.0
		melon.collision_layer = Util.LAYER_PROP
		melon.collision_mask = _prop_mask()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.14
		var col := CollisionShape3D.new()
		col.shape = sphere
		melon.add_child(col)
		var mesh := SphereMesh.new()
		mesh.radius = 0.14
		mesh.height = 0.26
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = melon_mat
		melon.add_child(mi)
		melon.position = pos + Vector3(0.0, 1.2 + 0.14, 0.0)
		melon.sleeping = true
		add_child(melon)

	# Balloons drifting over the range.
	for i in BALLOONS:
		var balloon := Balloon.new()
		balloon.position = Vector3(randf_range(-12.0, 12.0), randf_range(3.0, 7.0), randf_range(-15.0, -42.0))
		add_child(balloon)


func _prop_mask() -> int:
	return Util.LAYER_WORLD | Util.LAYER_PROP | Util.LAYER_HAND | Util.LAYER_PLAYER | Util.LAYER_BOW


func _rigid_box(size: Vector3, mat: Material, box_mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.add_to_group("crate")
	body.mass = box_mass
	body.collision_layer = Util.LAYER_PROP
	body.collision_mask = _prop_mask()
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.add_child(Util.mesh_box(size, mat))
	return body
