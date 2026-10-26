extends StaticBody2D
## Parede destrutível de TESTE: quebra com F7 ou com um ataque ("Atacar")
## do jogador a até `alcance` pixels. Precisa estar no grupo "map_dynamic_terrain".

@export var alcance: float = 70.0


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F7:
		quebrar()


func _physics_process(_delta: float) -> void:
	if not Input.is_action_just_pressed("Atacar"):
		return
	var player := get_tree().get_first_node_in_group(&"map_player") as Node2D
	if player != null and absf(player.global_position.x - global_position.x) <= alcance \
			and absf(player.global_position.y - global_position.y) <= 120.0:
		quebrar()


func quebrar() -> void:
	queue_free()
