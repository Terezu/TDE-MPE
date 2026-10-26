extends Area2D
## Colecionável de TESTE: some quando o jogador (grupo "map_player") encosta.
## Precisa estar no grupo "map_collectibles" para aparecer no minimapa.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"map_player"):
		queue_free()
