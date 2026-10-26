class_name EntityTracker
extends Node
## Registro e observação de inimigos, colecionáveis e plataformas móveis
## (spec, seções 4, 5 e 9). Tudo aqui é TEMPORÁRIO: nunca vai para o arquivo
## de progresso e some quando a fase é reiniciada (este nó morre com a cena).
##
## Registro híbrido: o MapScanner faz a varredura inicial dos grupos e depois
## avisa register()/unregister() quando nós entram ou saem da árvore.
##   map_enemies           -> inimigos (Node2D)
##   map_collectibles      -> colecionáveis (Node2D)
##   map_moving_platforms  -> plataformas móveis (nó com CollisionShape2D)
##
## Regras:
##   Inimigo: aparece só depois de observado. Visível -> marcador na posição real
##     (atualizada todo frame). Fora da câmera -> fica na última posição conhecida,
##     translúcido. Morreu (saiu da árvore/grupo) -> some. Se a câmera revisita a
##     última posição e ele não está lá -> registro invalidado.
##   Colecionável: aparece quando observado e fica marcado durante a sessão;
##     coletado (liberado/escondido) -> some; se reaparecer, pode ser redescoberto.
##   Plataforma móvel: só aparece enquanto observada; ao sair da câmera é ocultada;
##     não deixa trajetória.
## Entidades dentro de regiões secretas bloqueadas nunca são observadas.

const GROUP_ENEMIES := &"map_enemies"
const GROUP_COLLECTIBLES := &"map_collectibles"
const GROUP_MOVING_PLATFORMS := &"map_moving_platforms"

enum Kind { ENEMY, COLLECTIBLE, PLATFORM }

var _definition: MapDefinition
var _secrets: SecretRegionManager
var _terrain: TerrainScanner

var _registered: Dictionary = {} # instance_id -> { "ref": WeakRef, "kind": Kind }
var _observed: Dictionary = {}   # instance_id -> { "kind", "pos": Vector2, "visible": bool, "rects": Array }


func setup(definition: MapDefinition, secrets: SecretRegionManager, terrain: TerrainScanner) -> void:
	_definition = definition
	_secrets = secrets
	_terrain = terrain


## Retorna o Kind de um nó pelos grupos, ou -1 se não for entidade do minimapa.
static func kind_of(node: Node) -> int:
	if node.is_in_group(GROUP_ENEMIES):
		return Kind.ENEMY
	if node.is_in_group(GROUP_COLLECTIBLES):
		return Kind.COLLECTIBLE
	if node.is_in_group(GROUP_MOVING_PLATFORMS):
		return Kind.PLATFORM
	return -1


## Registra um nó (sem duplicar). Retorna true se foi registrado agora.
func register(node: Node) -> bool:
	var kind := kind_of(node)
	if kind < 0 or not node is Node2D:
		return false
	var id := node.get_instance_id()
	if _registered.has(id):
		return false
	_registered[id] = {"ref": weakref(node), "kind": kind}
	return true


## Remove registro e marcador (morte, coleta com queue_free, remoção da fase).
func unregister(node: Node) -> void:
	var id := node.get_instance_id()
	_registered.erase(id)
	_observed.erase(id)


func registered_count() -> int:
	return _registered.size()


## Detecção periódica (tick do MapScanner): quem está sendo observado agora.
func detect(view_rect: Rect2) -> void:
	var view := view_rect.intersection(_definition.world_bounds)
	for id: int in _registered.keys():
		var reg: Dictionary = _registered[id]
		var node := (reg["ref"] as WeakRef).get_ref() as Node2D
		if node == null:
			_registered.erase(id)
			_observed.erase(id)
			continue
		var kind: int = reg["kind"]
		var seen := _is_observed(node, kind, view)

		if seen:
			_observed[id] = {"kind": kind, "pos": node.global_position, "visible": true,
				"rects": _platform_rects(node) if kind == Kind.PLATFORM else []}
			continue
		if not _observed.has(id):
			continue

		var obs: Dictionary = _observed[id]
		match kind:
			Kind.PLATFORM:
				_observed.erase(id) # ocultada ao sair da câmera, sem trajetória
			Kind.COLLECTIBLE:
				if not node.is_visible_in_tree():
					_observed.erase(id) # coletado (escondido)
				else:
					obs["visible"] = false
			Kind.ENEMY:
				if not node.is_visible_in_tree():
					_observed.erase(id)
				elif view.has_point(obs["pos"]):
					_observed.erase(id) # revisitou a última posição e ele não estava lá
				else:
					obs["visible"] = false


## Atualização visual contínua (todo frame): posição dos inimigos e plataformas
## que estão sendo observados agora. Não decide quem é observado.
func update_visuals() -> void:
	for id: int in _observed.keys():
		var obs: Dictionary = _observed[id]
		if not obs["visible"] or obs["kind"] == Kind.COLLECTIBLE:
			continue
		var reg: Dictionary = _registered.get(id, {})
		var node: Node2D = (reg["ref"] as WeakRef).get_ref() as Node2D if not reg.is_empty() else null
		if node == null:
			_observed.erase(id)
			continue
		obs["pos"] = node.global_position
		if obs["kind"] == Kind.PLATFORM:
			obs["rects"] = _platform_rects(node)


func _is_observed(node: Node2D, kind: int, view: Rect2) -> bool:
	if view.size.x <= 0.0 or view.size.y <= 0.0 or not node.is_visible_in_tree():
		return false
	if not node.is_in_group(_group_of(kind)):
		return false
	if kind == Kind.PLATFORM:
		var rects := _platform_rects(node)
		for r: Rect2 in rects:
			if r.intersects(view) and not (_secrets != null and _secrets.is_rect_hidden(r)):
				return true
		return false
	var p := node.global_position
	return view.has_point(p) and not (_secrets != null and _secrets.is_point_hidden(p))


func _platform_rects(node: Node) -> Array[Rect2]:
	return _terrain.collision_rects(node)


static func _group_of(kind: int) -> StringName:
	match kind:
		Kind.ENEMY:
			return GROUP_ENEMIES
		Kind.COLLECTIBLE:
			return GROUP_COLLECTIBLES
	return GROUP_MOVING_PLATFORMS


## Para o MinimapRenderer: Array de { "kind", "pos", "visible", "rects" }.
func get_markers() -> Array:
	return _observed.values()


func count(kind: Kind, only_visible: bool = false) -> int:
	var n := 0
	for obs: Dictionary in _observed.values():
		if obs["kind"] == kind and (not only_visible or obs["visible"]):
			n += 1
	return n


## Esquece as observações (reinício de fase, F9). Mantém os registros.
func clear() -> void:
	_observed.clear()
