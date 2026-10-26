class_name ExplorationTracker
extends Node
## Determina e registra as células descobertas (spec, seções 3 e 7).
##
## A descoberta vem apenas do retângulo visível da Camera2D principal, sem
## oclusão. Células já conhecidas nunca são reprocessadas.

signal cells_discovered(cells: Array[Vector2i])

## Autorização de células (segredos): Callable(cell: Vector2i) -> bool,
## ligado ao SecretRegionManager pelo MapScanner.
## Se inválido, toda célula é autorizada. Ao mudar a autorização, chame
## invalidate_view() para forçar uma nova checagem.
var authorizer: Callable = Callable()

var _definition: MapDefinition
var _discovered: Dictionary = {}
var _last_range: Rect2i = Rect2i()
var _has_last_range: bool = false


func setup(definition: MapDefinition) -> void:
	_definition = definition
	_has_last_range = false


## Marca como descobertas as células autorizadas que tocam o retângulo visível.
## Retorna quantas células novas foram descobertas.
func observe(view_rect: Rect2) -> int:
	var visible := view_rect.intersection(_definition.world_bounds)
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return 0

	var cs := float(_definition.cell_size)
	var first := Vector2i(floori(visible.position.x / cs), floori(visible.position.y / cs))
	var last := Vector2i(ceili(visible.end.x / cs) - 1, ceili(visible.end.y / cs) - 1)
	var cell_range := Rect2i(first, last - first + Vector2i.ONE)

	# Enquadramento não mudou de célula: nada a recalcular.
	if _has_last_range and cell_range == _last_range:
		return 0
	_last_range = cell_range
	_has_last_range = true

	var found: Array[Vector2i] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if _discovered.has(cell):
				continue
			if authorizer.is_valid() and not authorizer.call(cell):
				continue
			_discovered[cell] = true
			found.append(cell)

	if not found.is_empty():
		cells_discovered.emit(found)
	return found.size()


## Força a próxima chamada de observe() a reavaliar o enquadramento atual.
func invalidate_view() -> void:
	_has_last_range = false


func is_discovered(cell: Vector2i) -> bool:
	return _discovered.has(cell)


func discovered_count() -> int:
	return _discovered.size()


## Usado pela persistência (etapa 2).
func get_discovered_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in _discovered:
		out.append(cell)
	return out


## Restaura progresso salvo. Não emite cells_discovered (não é descoberta nova).
func restore_cells(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_discovered[cell] = true
	invalidate_view()


## Esquece todas as células (uso em debug/QA).
func clear() -> void:
	_discovered.clear()
	invalidate_view()
