@tool
class_name SecretArea
extends Node2D
## Área de uma região secreta desenhada na fase (grupo "map_secrets").
## O retângulo começa na posição do nó (canto superior esquerdo) e tem `size`.
## As condições ficam na SecretDefinition de mesmo `secret_id` em MapDefinition.
## Só aparece no editor; não tem colisão e não altera o gameplay.

@export var secret_id: StringName = &"segredo_01"
@export var size: Vector2 = Vector2(256, 128):
	set(value):
		size = value
		queue_redraw()


func _enter_tree() -> void:
	add_to_group(&"map_secrets")


func get_global_rect() -> Rect2:
	return Rect2(global_position, size * global_scale.abs())


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.3, 1.0, 0.15))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.3, 1.0, 0.8), false, 2.0)
