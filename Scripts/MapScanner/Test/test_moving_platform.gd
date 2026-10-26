extends AnimatableBody2D
## Plataforma móvel de TESTE: vai e volta na horizontal.
## Precisa estar no grupo "map_moving_platforms".

@export var distancia: float = 320.0
@export var duracao: float = 3.0 # segundos para ir de um lado ao outro

var _origem: Vector2
var _t: float = 0.0


func _ready() -> void:
	_origem = position
	sync_to_physics = true


func _physics_process(delta: float) -> void:
	_t += delta
	var f := (1.0 - cos(_t * PI / duracao)) * 0.5 # 0 -> 1 -> 0, suave
	position = _origem + Vector2(distancia * f, 0.0)
