extends Area3D

var direction := Vector3.FORWARD
var speed := 23.0
var damage := 20.0
var player_owned := true
var explosive := false
var game
var _life := 2.2

func setup(owner_game: Node3D, travel: Vector3, amount: float, from_player: bool, is_explosive: bool = false) -> void:
	game = owner_game
	direction = travel.normalized()
	damage = amount
	player_owned = from_player
	explosive = is_explosive
	speed = 23.0 if from_player else 11.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if player_owned and body.is_in_group("enemies"):
		body.call("take_damage", damage)
		if explosive:
			game.explode_at(global_position, 3.0, damage * 0.65)
		game.spawn_impact(global_position, Color(1.0, 0.55, 0.16) if explosive else Color(0.28, 0.88, 1.0))
		queue_free()
	elif not player_owned and body.is_in_group("player"):
		body.call("take_damage", damage)
		game.spawn_impact(global_position, Color(1.0, 0.2, 0.3))
		queue_free()
	else:
		queue_free()
