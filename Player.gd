extends CharacterBody3D

signal fire_requested(origin: Vector3, direction: Vector3, damage: float, explosive: bool)
signal stats_changed
signal hit_taken
signal defeated
signal dash_started

@export var move_speed := 8.0
@export var dash_speed := 19.0
@export var max_health := 100.0
var health := 100.0
var hits_taken := 0
var upgrades_earned := 0
var damage := 20.0
var fire_interval := 0.28
var explosive_bullets := false
var invulnerable := false
var game
var aim_point := Vector3.ZERO
var visual: Node3D
var muzzle_flash: MeshInstance3D
var _shot_timer := 0.0
var _dash_timer := 0.0
var _dash_cooldown := 0.0
var _muzzle_timer := 0.0
var _invulnerability_timer := 0.0
var _dash_direction := Vector3.FORWARD
var _anim_time := 0.0

func _ready() -> void:
	_register_inputs()
	health = max_health
	add_to_group("player")

func _register_inputs() -> void:
	var bindings := {"move_forward": KEY_W, "move_backward": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "dash": KEY_SPACE, "restart": KEY_R}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var key := InputEventKey.new()
			key.physical_keycode = bindings[action]
			InputMap.action_add_event(action, key)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
	if InputMap.action_get_events("fire").is_empty():
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", click)

func _physics_process(delta: float) -> void:
	_shot_timer = maxf(0.0, _shot_timer - delta)
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	_invulnerability_timer = maxf(0.0, _invulnerability_timer - delta)
	_muzzle_timer = maxf(0.0, _muzzle_timer - delta)
	if _muzzle_timer <= 0.0 and is_instance_valid(muzzle_flash):
		muzzle_flash.visible = false
	invulnerable = _invulnerability_timer > 0.0
	var move_dir := Vector3.ZERO
	move_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	move_dir.z = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	move_dir = move_dir.normalized()
	if move_dir.length_squared() > 0.01:
		_dash_direction = move_dir
	if Input.is_action_just_pressed("dash") and _dash_cooldown <= 0.0:
		_dash_timer = 0.18
		_dash_cooldown = 1.2
		dash_started.emit()
		if move_dir.length_squared() > 0.01:
			_dash_direction = move_dir
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity.x = _dash_direction.x * dash_speed
		velocity.z = _dash_direction.z * dash_speed
	else:
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
	velocity.y = 0.0
	move_and_slide()
	if is_instance_valid(game):
		var limit: float = game.arena_half_size - 1.0
		global_position.x = clampf(global_position.x, -limit, limit)
		global_position.z = clampf(global_position.z, -limit, limit)
	var aim_dir := aim_point - global_position
	aim_dir.y = 0.0
	if aim_dir.length_squared() > 0.01:
		rotation.y = atan2(aim_dir.x, aim_dir.z)
	if Input.is_action_pressed("fire") and _shot_timer <= 0.0 and not game.game_ended:
		_shoot(aim_dir.normalized())
		_shot_timer = fire_interval
	_animate(delta, move_dir)

func _shoot(direction: Vector3) -> void:
	if direction.length_squared() < 0.01:
		direction = Vector3.FORWARD
	var origin := global_position + Vector3(0, 1.05, 0) + direction * 0.75
	fire_requested.emit(origin, direction, damage, explosive_bullets)
	if is_instance_valid(muzzle_flash):
		muzzle_flash.visible = true
		_muzzle_timer = 0.07

func _animate(delta: float, move_dir: Vector3) -> void:
	_anim_time += delta
	if is_instance_valid(visual):
		var moving := move_dir.length() > 0.1 or _dash_timer > 0.0
		visual.position.y = 0.85 + (sin(_anim_time * (13.0 if moving else 2.0)) * (0.07 if moving else 0.025))
		visual.rotation.z = sin(_anim_time * 13.0) * 0.05 if moving else 0.0
		visual.scale = Vector3.ONE * (1.1 if _dash_timer > 0.0 else (1.04 if invulnerable else 1.0))
		var head := visual.get_node_or_null("Head") as MeshInstance3D
		if head and head.material_override is StandardMaterial3D:
			var mat := head.material_override as StandardMaterial3D
			mat.albedo_color = Color(1.0, 0.38, 0.36) if invulnerable and int(_anim_time * 14.0) % 2 == 0 else Color(1.0, 0.75, 0.57)

func take_damage(amount: float) -> void:
	if invulnerable or game.game_ended:
		return
	health = maxf(0.0, health - amount)
	hits_taken += 1
	_invulnerability_timer = 0.8
	_apply_hit_upgrade()
	hit_taken.emit()
	stats_changed.emit()
	if health <= 0.0:
		defeated.emit()

func _apply_hit_upgrade() -> void:
	var earned := true
	match hits_taken:
		1: fire_interval /= 1.05
		2: move_speed *= 1.1
		3: damage *= 1.15
		4: fire_interval /= 1.2
		5: explosive_bullets = true
		_:
			if hits_taken > 5 and hits_taken % 3 == 0:
				damage *= 1.05
			else:
				earned = false
	if earned:
		upgrades_earned += 1

func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	stats_changed.emit()

func restart_run() -> void:
	health = max_health
	hits_taken = 0
	upgrades_earned = 0
	damage = 20.0
	move_speed = 8.0
	fire_interval = 0.28
	explosive_bullets = false
	_invulnerability_timer = 0.0
	_dash_cooldown = 0.0
	global_position = Vector3.ZERO
	stats_changed.emit()
