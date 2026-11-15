extends CharacterBody3D

signal fire_requested(origin: Vector3, direction: Vector3, damage: float)
var target: CharacterBody3D
var game
var health := 45.0
var speed := 3.4
var preferred_range := 6.5
var _fire_timer := 1.2
var _phase := 0.0
var _flash_timer := 0.0
var _dead := false
var visual: Node3D

func configure(player: CharacterBody3D, owner_game: Node3D, tough: bool) -> void:
	target = player
	game = owner_game
	if tough:
		health = 90.0
		speed = 2.5
		preferred_range = 5.0

func _ready() -> void:
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or game.game_ended:
		return
	_phase += delta
	_fire_timer -= delta
	_flash_timer = maxf(0.0, _flash_timer - delta)
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	var dir := offset.normalized() if distance > 0.01 else Vector3.ZERO
	var desired := Vector3.ZERO
	if distance > preferred_range:
		desired = dir * speed
	elif distance < preferred_range * 0.62:
		desired = -dir * speed * 0.7
	velocity.x = move_toward(velocity.x, desired.x, 12.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 12.0 * delta)
	velocity.y = 0.0
	move_and_slide()
	if dir.length_squared() > 0.01:
		rotation.y = atan2(dir.x, dir.z)
	if _fire_timer <= 0.0 and distance < 15.0:
		fire_requested.emit(global_position + Vector3.UP * 0.9 + dir * 0.6, dir, 12.0)
		_fire_timer = randf_range(1.6, 2.6)
	if is_instance_valid(visual):
		visual.position.y = 0.85 + sin(_phase * 4.0) * 0.06
		visual.scale = Vector3.ONE * (1.12 if _flash_timer > 0.0 else 1.0)

func take_damage(amount: float) -> void:
	if _dead:
		return
	health -= amount
	_flash_timer = 0.16
	if health <= 0.0:
		_dead = true
		game.enemy_defeated(self)
