extends StaticBody2D
## Porta de TESTE: F6 abre/fecha (desativa a colisão e esconde o visual).
## Precisa estar no grupo "map_dynamic_terrain".
## Avisa o minimapa pelo sinal `map_changed` (atualização por evento).

signal map_changed

@export var aberta: bool = false:
	set(value):
		aberta = value
		_aplicar()


func _ready() -> void:
	_aplicar()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F6:
		aberta = not aberta


func _aplicar() -> void:
	if not is_node_ready():
		return
	for c in find_children("*", "CollisionShape2D", true, false):
		(c as CollisionShape2D).set_deferred("disabled", aberta)
	for v in find_children("*", "CanvasItem", false, false):
		if not v is CollisionShape2D:
			(v as CanvasItem).visible = not aberta
	# Emitido depois do set_deferred, para o minimapa ler a colisão já atualizada.
	map_changed.emit.call_deferred()
