class_name TerrainScanner
extends Node
## Interpreta geometria estática e mudanças dinâmicas (spec, seções 4 e 7).
##
## Terreno ESTÁTICO — grupo "map_static_terrain", lido uma vez na entrada:
##   - TileMapLayer: um retângulo por tile usado;
##   - qualquer outro nó (ex.: StaticBody2D): seus CollisionShape2D / CollisionPolygon2D.
## O resultado é uma geometria simplificada (retângulos) indexada por célula
## de exploração, para o MinimapRenderer desenhar sem varrer a fase.
##
## Terreno DINÂMICO — grupo "map_dynamic_terrain" (portas, paredes destrutíveis,
## mecanismos). Atualização ORIENTADA A EVENTOS, sem reconstrução a cada frame:
##   - registro: varredura inicial + register_dynamic() quando um nó entra na árvore;
##   - nó removido da árvore (parede destruída)  -> unregister_dynamic();
##   - mudança de estado (porta abriu/fechou)   -> o nó emite o sinal `map_changed`
##     e só ele é relido no próximo frame (quando set_deferred já foi aplicado).
## O MapScanner não altera portas/paredes: só consulta as colisões ativas delas.
## O estado desenhado é o atual, só nas células já descobertas, e nunca é salvo.
## Plataformas móveis NÃO entram aqui: são observadas pelo EntityTracker.

const GROUP_STATIC_TERRAIN := &"map_static_terrain"
const GROUP_DYNAMIC_TERRAIN := &"map_dynamic_terrain"
const GROUP_MOVING_PLATFORMS := &"map_moving_platforms"
## Sinal que objetos dinâmicos devem declarar e emitir ao mudar de forma/estado.
const CHANGE_SIGNAL := &"map_changed"

signal dynamic_changed

var _definition: MapDefinition
var _cell_rects: Dictionary = {} # Vector2i -> Array[Rect2], já recortados por célula
var _empty: Array = []
var _dynamic: Dictionary = {}    # instance_id -> { "ref": WeakRef, "rects": Array[Rect2] }
var _dirty: Dictionary = {}      # instance_id -> true (aguardando releitura)
var _dynamic_rects: Array[Rect2] = [] # cache da união, refeito só quando algo muda
var _rebuild_count: int = 0      # quantas vezes o cache foi refeito (QA/testes)


func setup(definition: MapDefinition) -> void:
	_definition = definition


## Varredura completa inicial do estático. Retorna quantos retângulos foram registrados.
func scan_static() -> int:
	_cell_rects.clear()
	var count := 0
	for node in get_tree().get_nodes_in_group(GROUP_STATIC_TERRAIN):
		if node.is_in_group(GROUP_DYNAMIC_TERRAIN) or node.is_in_group(GROUP_MOVING_PLATFORMS):
			push_warning("TerrainScanner: '%s' está em map_static_terrain e num grupo dinâmico; ignorado como estático." % node.name)
			continue
		if node is TileMapLayer:
			count += _register_tilemap(node as TileMapLayer)
		else:
			count += _register_collision_nodes(node)
	return count


## Retângulos de terreno estático (coordenadas globais) que caem dentro da célula.
func get_cell_rects(cell: Vector2i) -> Array:
	return _cell_rects.get(cell, _empty)


## Registra um objeto de terreno dinâmico (sem duplicar). Retorna true se registrou.
func register_dynamic(node: Node) -> bool:
	if not node.is_in_group(GROUP_DYNAMIC_TERRAIN):
		return false
	var id := node.get_instance_id()
	if _dynamic.has(id):
		return false
	var cb := _on_dynamic_changed.bind(id)
	_dynamic[id] = {"ref": weakref(node), "rects": _dynamic_rects_of(node), "cb": cb}
	if node.has_signal(CHANGE_SIGNAL):
		node.connect(CHANGE_SIGNAL, cb)
	_rebuild_cache()
	return true


## Remove um objeto dinâmico (destruído ou retirado da fase).
func unregister_dynamic(node: Node) -> void:
	var id := node.get_instance_id()
	if not _dynamic.has(id):
		return
	var cb: Callable = _dynamic[id]["cb"]
	if node.has_signal(CHANGE_SIGNAL) and node.is_connected(CHANGE_SIGNAL, cb):
		node.disconnect(CHANGE_SIGNAL, cb)
	_dynamic.erase(id)
	_dirty.erase(id)
	_rebuild_cache()


func _on_dynamic_changed(id: int) -> void:
	_dirty[id] = true


## Relê apenas os objetos que avisaram mudança. Barato quando não há eventos.
## Retorna quantos objetos foram relidos.
func flush_dynamic() -> int:
	if _dirty.is_empty():
		return 0
	var n := 0
	for id: int in _dirty:
		if not _dynamic.has(id):
			continue
		var node := (_dynamic[id]["ref"] as WeakRef).get_ref() as Node
		if node == null:
			_dynamic.erase(id)
			continue
		_dynamic[id]["rects"] = _dynamic_rects_of(node)
		n += 1
	_dirty.clear()
	_rebuild_cache()
	return n


## Retângulos dinâmicos atuais (coordenadas globais).
func get_dynamic_rects() -> Array[Rect2]:
	return _dynamic_rects


func dynamic_object_count() -> int:
	return _dynamic.size()


func rebuild_count() -> int:
	return _rebuild_count


func _rebuild_cache() -> void:
	var rects: Array[Rect2] = []
	for id: int in _dynamic:
		rects.append_array(_dynamic[id]["rects"])
	_rebuild_count += 1
	if rects != _dynamic_rects:
		_dynamic_rects = rects
		dynamic_changed.emit()


func _dynamic_rects_of(node: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		if layer.enabled and layer.collision_enabled and layer.tile_set != null:
			var tile_size := Vector2(layer.tile_set.tile_size)
			for cell: Vector2i in layer.get_used_cells():
				var top_left := layer.map_to_local(cell) - tile_size * 0.5
				_append_clipped(out, _transform_rect(layer.global_transform, Rect2(top_left, tile_size)))
	else:
		for r in collision_rects(node):
			_append_clipped(out, r)
	return out


func _append_clipped(out: Array[Rect2], rect: Rect2) -> void:
	var clipped := rect.intersection(_definition.world_bounds)
	if clipped.size.x > 0.0 and clipped.size.y > 0.0:
		out.append(clipped)


func _register_tilemap(layer: TileMapLayer) -> int:
	if layer.tile_set == null:
		return 0
	var tile_size := Vector2(layer.tile_set.tile_size)
	var xf := layer.global_transform
	var n := 0
	for cell: Vector2i in layer.get_used_cells():
		var top_left := layer.map_to_local(cell) - tile_size * 0.5
		var rect := _transform_rect(xf, Rect2(top_left, tile_size))
		_add_rect(rect)
		n += 1
	return n


func _register_collision_nodes(root: Node) -> int:
	var rects := collision_rects(root)
	for rect in rects:
		_add_rect(rect)
	return rects.size()


## Retângulos globais das colisões ATIVAS do nó (inclui o próprio nó e filhos).
func collision_rects(root: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var shapes: Array[Node] = root.find_children("*", "CollisionShape2D", true, false)
	var polys: Array[Node] = root.find_children("*", "CollisionPolygon2D", true, false)
	if root is CollisionShape2D:
		shapes.append(root)
	elif root is CollisionPolygon2D:
		polys.append(root)
	for child in shapes:
		var rect := _shape_rect(child as CollisionShape2D)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			out.append(rect)
	for child in polys:
		var rect := _polygon_rect(child as CollisionPolygon2D)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			out.append(rect)
	return out


func _shape_rect(cs: CollisionShape2D) -> Rect2:
	if cs.shape == null or cs.disabled:
		return Rect2()
	var local_rect := Rect2()
	var rect_shape := cs.shape as RectangleShape2D
	var circle_shape := cs.shape as CircleShape2D
	var capsule_shape := cs.shape as CapsuleShape2D
	if rect_shape != null:
		local_rect = Rect2(-rect_shape.size * 0.5, rect_shape.size)
	elif circle_shape != null:
		var r := circle_shape.radius
		local_rect = Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0)
	elif capsule_shape != null:
		var cr := capsule_shape.radius
		var h := capsule_shape.height
		local_rect = Rect2(Vector2(-cr, -h * 0.5), Vector2(cr * 2.0, h))
	else:
		return Rect2() # formato não suportado nesta etapa
	return _transform_rect(cs.global_transform, local_rect)


func _polygon_rect(cp: CollisionPolygon2D) -> Rect2:
	if cp.disabled or cp.polygon.size() < 3:
		return Rect2()
	var xf := cp.global_transform
	var rect := Rect2(xf * cp.polygon[0], Vector2.ZERO)
	for p in cp.polygon:
		rect = rect.expand(xf * p)
	return rect


## Retângulo local -> retângulo global (envolvente, caso haja rotação).
func _transform_rect(xf: Transform2D, r: Rect2) -> Rect2:
	var out := Rect2(xf * r.position, Vector2.ZERO)
	out = out.expand(xf * Vector2(r.end.x, r.position.y))
	out = out.expand(xf * Vector2(r.position.x, r.end.y))
	out = out.expand(xf * r.end)
	return out


## Recorta o retângulo pelos limites do mapa e distribui os pedaços por célula.
func _add_rect(rect: Rect2) -> void:
	var clipped := rect.intersection(_definition.world_bounds)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
		return
	var cs := float(_definition.cell_size)
	var x0 := floori(clipped.position.x / cs)
	var y0 := floori(clipped.position.y / cs)
	var x1 := ceili(clipped.end.x / cs) - 1
	var y1 := ceili(clipped.end.y / cs) - 1
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var cell_rect := Rect2(Vector2(cx, cy) * cs, Vector2(cs, cs))
			var piece := clipped.intersection(cell_rect)
			if piece.size.x <= 0.0 or piece.size.y <= 0.0:
				continue
			var cell := Vector2i(cx, cy)
			if not _cell_rects.has(cell):
				_cell_rects[cell] = []
			(_cell_rects[cell] as Array).append(piece)
