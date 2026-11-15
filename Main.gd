extends Node3D

const PLAYER_SCRIPT = preload("res://Player.gd")
const ENEMY_SCRIPT = preload("res://Enemy.gd")
const PROJECTILE_SCRIPT = preload("res://Projectile.gd")

@export var arena_half_size := 14.0
@export var run_length := 300.0

var player
var camera: Camera3D
var hud: CanvasLayer
var health_fill: ColorRect
var hud_stats: Label
var hint_label: Label
var end_panel: PanelContainer
var end_text: Label
var crosshair: Label
var music_player: AudioStreamPlayer
var cue_player: AudioStreamPlayer
var game_ended := false
var ui_fire_held := false
var elapsed := 0.0
var defeated_count := 0
var wave_timer := 2.0
var pack_timer := 18.0
var _ui_flash := 0.0
var _enemies: Array = []
var _pickups: Array[Area3D] = []

func _ready() -> void:
	randomize()
	_build_arena()
	_build_player()
	_build_camera()
	_build_hud()
	_build_audio()
	_spawn_wave(3)

func _process(delta: float) -> void:
	if game_ended:
		return
	elapsed += delta
	wave_timer -= delta
	pack_timer -= delta
	if wave_timer <= 0.0:
		var wave_size := mini(2 + int(elapsed / 45.0), 5)
		_spawn_wave(wave_size)
		wave_timer = maxf(14.0, 21.0 - elapsed / 30.0)
	if pack_timer <= 0.0:
		if _pickups.size() < 2:
			_spawn_health_pack()
		pack_timer = 24.0
	if elapsed >= run_length:
		_end_game(true)
		return
	_update_aim()
	_update_hud()
	if _ui_flash > 0.0:
		_ui_flash -= delta
		if _ui_flash <= 0.0:
			hint_label.text = ""
	_update_pickups(delta)

func _build_arena() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.008, 0.015, 0.07)
	sky_material.sky_horizon_color = Color(0.06, 0.12, 0.24)
	sky_material.ground_bottom_color = Color(0.01, 0.015, 0.04)
	sky_material.ground_horizon_color = Color(0.06, 0.12, 0.24)
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.48, 0.75)
	env.ambient_light_energy = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env_node.environment = env
	add_child(env_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -26, 0)
	light.light_energy = 1.15
	add_child(light)
	_make_box(self, "ArenaFloor", Vector3(arena_half_size * 2.0, 0.5, arena_half_size * 2.0), Vector3(0, -0.3, 0), Color(0.055, 0.09, 0.17), false)
	for x in range(-13, 14, 2):
		_make_box(self, "FloorGridX", Vector3(0.025, 0.015, arena_half_size * 2.0), Vector3(x, -0.035, 0), Color(0.1, 0.22, 0.34), true)
	for z in range(-13, 14, 2):
		_make_box(self, "FloorGridZ", Vector3(arena_half_size * 2.0, 0.015, 0.025), Vector3(0, -0.034, z), Color(0.1, 0.22, 0.34), true)
	for x in [-arena_half_size, arena_half_size]:
		_make_box(self, "ArenaWall", Vector3(0.65, 1.5, arena_half_size * 2.0), Vector3(x, 0.5, 0), Color(0.1, 0.22, 0.4), true)
	for z in [-arena_half_size, arena_half_size]:
		_make_box(self, "ArenaWall", Vector3(arena_half_size * 2.0, 1.5, 0.65), Vector3(0, 0.5, z), Color(0.1, 0.22, 0.4), true)
	for pos in [Vector3(-6, 0, -6), Vector3(6, 0, -6), Vector3(-6, 0, 6), Vector3(6, 0, 6)]:
		_make_cylinder(self, "CoverPillar", 0.65, 2.0, pos + Vector3.UP, Color(0.14, 0.24, 0.42), true)
	for i in range(4):
		var angle := TAU * float(i) / 4.0
		_make_cylinder(self, "ReactorColumn", 0.22, 4.0, Vector3(cos(angle) * 11.0, 2.0, sin(angle) * 11.0), Color(0.12, 0.5, 0.85), true)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "ShinchanPlayer"
	player.position = Vector3(0, 0.05, 0)
	player.script = PLAYER_SCRIPT
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.52
	capsule.height = 1.75
	collision.shape = capsule
	collision.position.y = 0.88
	player.add_child(collision)
	player.visual = _build_shinchan(player)
	player.game = self
	player.fire_requested.connect(_on_player_fire)
	player.hit_taken.connect(_on_player_hit)
	player.dash_started.connect(func(): _play_tone(250.0, 0.12, 0.28))
	player.defeated.connect(func(): _end_game(false))
	player.stats_changed.connect(_update_hud)
	add_child(player)

func _build_shinchan(parent: Node3D) -> Node3D:
	var visual := Node3D.new()
	visual.name = "ShinchanVisual"
	parent.add_child(visual)
	_add_sphere(visual, "Torso", Vector3(0, 0.0, 0), Vector3(0.72, 0.64, 0.48), Color(0.9, 0.12, 0.11))
	_add_box_visual(visual, "Shorts", Vector3(0, -0.4, 0), Vector3(0.67, 0.33, 0.48), Color(1.0, 0.78, 0.1))
	_add_sphere(visual, "Head", Vector3(0, 0.78, 0), Vector3(0.58, 0.58, 0.53), Color(1.0, 0.75, 0.57))
	_add_sphere(visual, "Hair", Vector3(0, 1.1, -0.015), Vector3(0.61, 0.29, 0.55), Color(0.025, 0.022, 0.035))
	for eye_x in [-0.19, 0.19]:
		_add_sphere(visual, "Eye", Vector3(eye_x, 0.82, 0.47), Vector3(0.09, 0.13, 0.065), Color(0.02, 0.025, 0.035))
		_add_box_visual(visual, "Brow", Vector3(eye_x, 1.02, 0.48), Vector3(0.2, 0.055, 0.06), Color(0.025, 0.02, 0.03))
	_add_box_visual(visual, "Smile", Vector3(0, 0.58, 0.51), Vector3(0.19, 0.035, 0.025), Color(0.28, 0.035, 0.035))
	for side in [-1.0, 1.0]:
		_add_sphere(visual, "Ear", Vector3(side * 0.56, 0.75, 0), Vector3(0.15, 0.19, 0.15), Color(1.0, 0.69, 0.51))
		_add_capsule_visual(visual, "Arm", Vector3(side * 0.48, 0.0, 0), Vector3(0.19, 0.45, 0.19), Color(1.0, 0.73, 0.54))
		_add_capsule_visual(visual, "Leg", Vector3(side * 0.2, -0.67, 0.02), Vector3(0.18, 0.4, 0.18), Color(1.0, 0.72, 0.54))
		_add_sphere(visual, "Shoe", Vector3(side * 0.2, -0.88, 0.12), Vector3(0.23, 0.12, 0.32), Color(0.08, 0.045, 0.06))
	var gun := Node3D.new()
	gun.name = "EnergyBlaster"
	gun.position = Vector3(0.48, 0.04, 0.45)
	visual.add_child(gun)
	_add_box_visual(gun, "BlasterBody", Vector3.ZERO, Vector3(0.25, 0.16, 0.48), Color(0.11, 0.2, 0.31), true)
	_add_box_visual(gun, "BlasterBarrel", Vector3(0, 0.015, 0.3), Vector3(0.13, 0.13, 0.28), Color(0.22, 0.82, 1.0), true)
	_add_box_visual(gun, "BlasterGrip", Vector3(0, -0.13, 0.03), Vector3(0.13, 0.22, 0.15), Color(0.08, 0.11, 0.18))
	var muzzle := _add_sphere(gun, "MuzzleFlash", Vector3(0, 0.015, 0.48), Vector3(0.17, 0.17, 0.18), Color(0.25, 0.85, 1.0), true)
	muzzle.visible = false
	player.muzzle_flash = muzzle
	return visual

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 25, 21)
	camera.fov = 60.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var top_panel := ColorRect.new()
	top_panel.color = Color(0.015, 0.025, 0.07, 0.84)
	top_panel.position = Vector2(20, 18)
	top_panel.size = Vector2(565, 100)
	hud.add_child(top_panel)
	_label(hud, "REBOUND ARENA", Vector2(38, 22), 27, Color(0.45, 0.88, 1.0))
	_label(hud, "SHINCHAN  |  SURVIVE THE FIVE MINUTE RUN", Vector2(40, 56), 15, Color(0.78, 0.86, 1.0))
	var health_bg := ColorRect.new()
	health_bg.position = Vector2(40, 82)
	health_bg.size = Vector2(240, 18)
	health_bg.color = Color(0.12, 0.08, 0.14, 1)
	hud.add_child(health_bg)
	health_fill = ColorRect.new()
	health_fill.position = health_bg.position
	health_fill.size = Vector2(240, 18)
	health_fill.color = Color(0.18, 0.9, 0.54)
	hud.add_child(health_fill)
	hud_stats = _label(hud, "", Vector2(315, 80), 16, Color.WHITE)
	hint_label = _label(hud, "", Vector2(0, 125), 23, Color(1.0, 0.78, 0.25))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label(hud, "WASD move  |  Mouse aim + left click fire  |  SPACE dash  |  R restart", Vector2(22, 680), 17, Color(0.76, 0.85, 1.0))
	var fire_button := Button.new()
	fire_button.text = "FIRE"
	fire_button.position = Vector2(1125, 590)
	fire_button.size = Vector2(125, 78)
	fire_button.add_theme_font_size_override("font_size", 24)
	fire_button.button_down.connect(_on_fire_button_down)
	fire_button.button_up.connect(_on_fire_button_up)
	hud.add_child(fire_button)
	crosshair = _label(hud, "+", Vector2.ZERO, 25, Color(0.55, 0.96, 1.0))
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_build_end_panel()
	_update_hud()

func _build_end_panel() -> void:
	end_panel = PanelContainer.new()
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	end_panel.position = Vector2(-250, -205)
	end_panel.size = Vector2(500, 410)
	end_panel.visible = false
	hud.add_child(end_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	end_panel.add_child(box)
	end_text = Label.new()
	end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_text.add_theme_font_size_override("font_size", 23)
	box.add_child(end_text)
	var button := Button.new()
	button.text = "PLAY AGAIN"
	button.custom_minimum_size = Vector2(220, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_restart_game)
	box.add_child(button)

func _build_audio() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -20.0
	music_player.stream = _make_drone()
	add_child(music_player)
	music_player.play()
	cue_player = AudioStreamPlayer.new()
	cue_player.volume_db = -7.0
	add_child(cue_player)

func _update_aim() -> void:
	if ui_fire_held:
		var nearest: Node3D = null
		var nearest_distance := INF
		for enemy in _enemies:
			if is_instance_valid(enemy):
				var distance: float = player.global_position.distance_squared_to(enemy.global_position)
				if distance < nearest_distance:
					nearest = enemy
					nearest_distance = distance
		if is_instance_valid(nearest):
			player.aim_point = nearest.global_position
		return
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse)
	var ray_direction := camera.project_ray_normal(mouse)
	var aim: Variant = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)
	if aim != null:
		player.aim_point = aim
	crosshair.position = mouse - Vector2(16, 18)

func _on_fire_button_down() -> void:
	ui_fire_held = true
	Input.action_press("fire")

func _on_fire_button_up() -> void:
	ui_fire_held = false
	Input.action_release("fire")

func _update_hud() -> void:
	if not is_instance_valid(player):
		return
	var ratio := clampf(player.health / player.max_health, 0.0, 1.0)
	health_fill.size.x = 240.0 * ratio
	health_fill.color = Color(0.18, 0.9, 0.54).lerp(Color(1.0, 0.15, 0.22), 1.0 - ratio)
	var remaining := maxi(0, int(ceil(run_length - elapsed)))
	hud_stats.text = "HP %d%%\nTIME %02d:%02d\nHITS %d  UPGRADES %d\nDASH %s  KOs %d" % [roundi(ratio * 100.0), int(remaining / 60), remaining % 60, player.hits_taken, player.upgrades_earned, "READY" if player._dash_cooldown <= 0.0 else "CHARGING", defeated_count]

func _update_pickups(delta: float) -> void:
	for pack in _pickups.duplicate():
		if is_instance_valid(pack):
			pack.rotate_y(delta * 1.5)
			var bag := pack.get_node_or_null("Bag") as Node3D
			if bag:
				bag.position.y = 0.8 + sin(elapsed * 3.0 + pack.position.x) * 0.12
			var distance := Vector2(player.global_position.x - pack.global_position.x, player.global_position.z - pack.global_position.z).length()
			if distance <= 1.4:
				_collect_health_pack(pack)

func _spawn_wave(count: int) -> void:
	var available := maxi(0, 12 - _live_enemy_count())

	for i in range(mini(count, available)):
		var angle := randf() * TAU
		var spawn_radius := randf_range(10.0, 12.0)

		var enemy = CharacterBody3D.new()
		enemy.name = "ArenaEnemy"
		enemy.position = Vector3(cos(angle) * spawn_radius, 0.0, sin(angle) * spawn_radius)
		enemy.set_script(ENEMY_SCRIPT)

		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.48
		shape.height = 1.65
		collision.shape = shape
		collision.position.y = 0.83
		enemy.add_child(collision)

		var visual := Node3D.new()
		visual.name = "Visual"
		visual.position.y = 0.85
		enemy.add_child(visual)

		var heavy := randf() < minf(0.14 + elapsed / 500.0, 0.45)

		_add_sphere(visual, "EnemyBody", Vector3.ZERO,
			Vector3(0.55, 0.65, 0.48),
			Color(0.82, 0.12, 0.3) if heavy else Color(0.48, 0.17, 0.92), true)

		_add_sphere(visual, "EnemyEye", Vector3(0, 0.05, 0.42),
			Vector3(0.26, 0.15, 0.08), Color(1.0, 0.45, 0.72), true)

		enemy.visual = visual
		enemy.configure(player, self, heavy)
		enemy.fire_requested.connect(_on_enemy_fire)

		add_child(enemy)
		_enemies.append(enemy)

func _live_enemy_count() -> int:
	var count := 0
	for enemy in _enemies:
		if is_instance_valid(enemy):
			count += 1
	return count

func _on_player_fire(origin: Vector3, direction: Vector3, amount: float, explosive: bool) -> void:
	_spawn_projectile(origin, direction, amount, true, explosive)
	_play_tone(640.0, 0.07, 0.12)

func _on_enemy_fire(origin: Vector3, direction: Vector3, amount: float) -> void:
	_spawn_projectile(origin, direction, amount, false)

func _spawn_projectile(origin: Vector3, direction: Vector3, amount: float, from_player: bool, explosive := false) -> void:
	var bullet = Area3D.new()
	bullet.name = "PlayerShot" if from_player else "EnemyShot"
	bullet.script = PROJECTILE_SCRIPT
	bullet.collision_layer = 0
	bullet.collision_mask = 1
	bullet.monitoring = true
	var shape_node := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.2 if from_player else 0.25
	shape_node.shape = shape
	bullet.add_child(shape_node)
	_add_sphere(bullet, "Glow", Vector3.ZERO, Vector3(0.22, 0.22, 0.36), Color(0.22, 0.9, 1.0) if from_player else Color(1.0, 0.18, 0.28), true)
	bullet.setup(self, direction, amount, from_player, explosive)
	bullet.global_position = origin
	add_child(bullet)

func _on_player_hit() -> void:
	_ui_flash = 1.0
	if player.hits_taken <= 5 or player.hits_taken % 3 == 0:
		hint_label.text = "HIT TAKEN! UPGRADE %d EARNED" % player.upgrades_earned
	else:
		hint_label.text = "HIT TAKEN - BONUS UPGRADE AT HIT %d" % (player.hits_taken + (3 - player.hits_taken % 3))
	_play_tone(155.0, 0.24, 0.5)

func _spawn_health_pack() -> void:
	var pack := Area3D.new()
	pack.name = "GoroGoroChipsHealthPack"
	pack.collision_layer = 0
	pack.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.0
	collision.shape = shape
	pack.add_child(collision)
	var bag := Node3D.new()
	bag.name = "Bag"
	pack.add_child(bag)
	_add_box_visual(bag, "ChipsBag", Vector3(0, 0, 0), Vector3(0.9, 1.15, 0.3), Color(0.98, 0.71, 0.08), true)
	_add_box_visual(bag, "TopSeal", Vector3(0, 0.58, 0), Vector3(0.92, 0.12, 0.34), Color(0.9, 0.13, 0.16), true)
	var brand := Label3D.new()
	brand.text = "GORO GORO\nCHIPS"
	brand.position = Vector3(0, 0.02, 0.17)
	brand.font_size = 36
	brand.pixel_size = 0.005
	brand.modulate = Color(0.55, 0.04, 0.08)
	brand.outline_size = 7
	brand.outline_modulate = Color(1.0, 0.94, 0.7)
	bag.add_child(brand)
	_add_sphere(bag, "PackGlint", Vector3(0.2, -0.2, 0.2), Vector3(0.12, 0.15, 0.08), Color(0.95, 0.25, 0.1), true)
	pack.body_entered.connect(func(body: Node3D):
		if body == player:
			_collect_health_pack(pack)
	)
	pack.position = Vector3(randf_range(-9.0, 9.0), 0.9, randf_range(-9.0, 9.0))
	add_child(pack)
	_pickups.append(pack)

func _collect_health_pack(pack: Area3D) -> void:
	if not is_instance_valid(pack) or pack.is_queued_for_deletion() or game_ended:
		return
	var recovered := minf(35.0, player.max_health - player.health)
	player.heal(35.0)
	if recovered > 0.0:
		hint_label.text = "GORO GORO CHIPS! +%d HEALTH" % roundi(recovered)
	else:
		hint_label.text = "GORO GORO CHIPS COLLECTED"
	_ui_flash = 2.0
	_play_tone(880.0, 0.18, 0.3)
	_pickups.erase(pack)
	pack.queue_free()

func enemy_defeated(enemy: Node3D) -> void:
	if not is_instance_valid(enemy):
		return
	defeated_count += 1
	spawn_impact(enemy.global_position + Vector3.UP, Color(0.6, 0.28, 1.0))
	_enemies.erase(enemy)
	enemy.queue_free()

func explode_at(center: Vector3, radius: float, amount: float) -> void:
	for enemy in _enemies.duplicate():
		if is_instance_valid(enemy) and Vector2(enemy.global_position.x - center.x, enemy.global_position.z - center.z).length() <= radius:
			enemy.take_damage(amount)
	spawn_impact(center, Color(1.0, 0.48, 0.12), radius)

func spawn_impact(at: Vector3, tint: Color, radius := 1.0) -> void:
	var burst := _add_sphere(self, "ImpactBurst", at, Vector3.ONE * 0.2, tint, true)
	var tween := create_tween()
	tween.tween_property(burst, "scale", Vector3.ONE * radius, 0.16)
	tween.parallel().tween_property(burst, "transparency", 1.0, 0.18)
	tween.tween_callback(burst.queue_free)

func _end_game(won: bool) -> void:
	if game_ended:
		return
	game_ended = true
	player.set_physics_process(false)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
	music_player.stop()
	_play_tone(110.0 if not won else 990.0, 0.75, 0.5)
	var title := "ARENA CLEARED" if won else "SYSTEM FAILURE"
	var survived := int(elapsed)
	end_text.text = "%s\n\nTime survived: %02d:%02d\nHits taken: %d\nUpgrades earned: %d\nEnemies defeated: %d" % [title, int(survived / 60), survived % 60, player.hits_taken, player.upgrades_earned, defeated_count]
	end_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _restart_game() -> void:
	get_tree().reload_current_scene()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_restart_game()

func _play_tone(frequency: float, duration: float, volume: float) -> void:
	if not is_instance_valid(cue_player):
		return
	cue_player.stream = _make_tone(frequency, duration, volume)
	cue_player.play()

func _make_tone(frequency: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / rate
		var envelope := minf(t * 35.0, 1.0) * pow(1.0 - t / duration, 2.0)
		var sample := sin(TAU * frequency * t) * envelope * volume
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

func _make_drone() -> AudioStreamWAV:
	var rate := 22050
	var frames := rate * 6
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / rate
		var pulse := 0.78 + 0.22 * sin(TAU * 0.5 * t)
		var sample := pulse * (0.15 * sin(TAU * 55.0 * t) + 0.08 * sin(TAU * 82.5 * t) + 0.04 * sin(TAU * 110.0 * t))
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = frames
	return stream

func _make_box(parent: Node3D, label: String, size: Vector3, pos: Vector3, tint: Color, glow: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material(tint, glow)
	body.add_child(visual)
	parent.add_child(body)
	return body

func _make_cylinder(parent: Node3D, label: String, radius: float, height: float, pos: Vector3, tint: Color, glow: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	shape_node.shape = shape
	body.add_child(shape_node)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material(tint, glow)
	body.add_child(visual)
	parent.add_child(body)
	return body

func _add_box_visual(parent: Node3D, label: String, pos: Vector3, size: Vector3, tint: Color, glow := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.position = pos
	instance.mesh = mesh
	instance.material_override = _material(tint, glow)
	parent.add_child(instance)
	return instance

func _add_sphere(parent: Node3D, label: String, pos: Vector3, size: Vector3, tint: Color, glow := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.position = pos
	instance.scale = size
	instance.mesh = mesh
	instance.material_override = _material(tint, glow)
	parent.add_child(instance)
	return instance

func _add_capsule_visual(parent: Node3D, label: String, pos: Vector3, size: Vector3, tint: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = size.x
	mesh.height = size.y * 2.0
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.position = pos
	instance.mesh = mesh
	instance.material_override = _material(tint, false)
	parent.add_child(instance)
	return instance

func _material(tint: Color, glow: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = 0.22
	material.roughness = 0.38
	if glow:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = 0.8
	return material

func _label(parent: Node, text: String, pos: Vector2, size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	parent.add_child(label)
	return label
