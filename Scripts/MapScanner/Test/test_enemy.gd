extends Node2D
## Inimigo de TESTE (só para a cena experimental do MapScanner).
## Patrulha entre dois pontos; não tem colisão nem causa dano.
## Precisa estar no grupo "map_enemies" para aparecer no minimapa.
## Morre com um ataque ("Atacar") do jogador a até `alcance` pixels.

@export var distancia: float = 200.0
@export var velocidade: float = 60.0
@export var alcance: float = 60.0

var _origem: Vector2
var _dir: float = 1.0


func _ready() -> void:
	_origem = position


func _physics_process(delta: float) -> void:
	position.x += _dir * velocidade * delta
	if absf(position.x - _origem.x) >= distancia:
		position.x = _origem.x + signf(position.x - _origem.x) * distancia
		_dir = -_dir

	if Input.is_action_just_pressed("Atacar"):
		var player := get_tree().get_first_node_in_group(&"map_player") as Node2D
		if player != null and player.global_position.distance_to(global_position) <= alcance:
			morrer()


func morrer() -> void:
	queue_free()
