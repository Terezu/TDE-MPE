class_name SecretRegionManager
extends Node
## Avalia condições e controla a autorização de exploração dos segredos (spec, seção 6).
##
## Enquanto um segredo está bloqueado:
##   - nenhuma célula que encoste na região pode ser descoberta (mesmo dentro da câmera);
##   - células da região já descobertas (ex.: save antigo) continuam mascaradas no desenho;
##   - inimigos, colecionáveis e plataformas móveis dentro da região não são observados.
## Ao desbloquear, nada é revelado de uma vez: a câmera descobre as células normalmente.
##
## Só o desbloqueio completo é persistido (via MapScanner -> MapPersistenceManager).
## Condições intermediárias (entradas físicas, porta aberta etc.) NÃO são salvas:
## são reavaliadas consultando o gameplay.

signal secret_unlocked(id: StringName)

const GROUP_SECRETS := &"map_secrets"

var _definition: MapDefinition
var _level_root: Node
var _locked: Dictionary = {}        # StringName id -> SecretDefinition
var _rects: Dictionary = {}         # StringName id -> Array[Rect2] (globais)
var _blocked_cells: Dictionary = {} # Vector2i -> true (união das regiões bloqueadas)
var _entered: Dictionary = {}       # memória temporária das condições de entrada física
var _dirty: bool = true
var _last_player_pos: Vector2 = Vector2.INF


func setup(definition: MapDefinition, level_root: Node, already_unlocked: Array[StringName]) -> void:
	_definition = definition
	_level_root = level_root
	_locked.clear()
	_rects.clear()
	for s: SecretDefinition in definition.secrets:
		if s == null:
			continue
		if _rects.has(s.id):
			push_warning("SecretRegionManager: ID de segredo repetido '%s'; mantida só a primeira definição." % s.id)
			continue
		_rects[s.id] = s.regions.duplicate()
		if not already_unlocked.has(s.id):
			_locked[s.id] = s
	# Áreas desenhadas na fase (SecretArea) somam-se às regiões da definição.
	for n in get_tree().get_nodes_in_group(GROUP_SECRETS):
		var area := n as SecretArea
		if area == null:
			continue
		if not _rects.has(area.secret_id):
			push_warning("SecretRegionManager: SecretArea '%s' sem SecretDefinition '%s' em MapDefinition." % [area.name, area.secret_id])
			continue
		(_rects[area.secret_id] as Array).append(area.get_global_rect())
	_rebuild_blocked_cells()


## Pede reavaliação no próximo tick (eventos do mundo: porta, parede, mecanismo).
func request_evaluation() -> void:
	_dirty = true


## Reavalia os segredos bloqueados. Chamado no tick de detecção do MapScanner;
## só trabalha se houve evento ou se o jogador se moveu. Retorna os IDs desbloqueados.
func evaluate(player_pos: Vector2) -> Array[StringName]:
	var unlocked: Array[StringName] = []
	if _locked.is_empty():
		return unlocked
	if not _dirty and player_pos.is_equal_approx(_last_player_pos):
		return unlocked
	_dirty = false
	_last_player_pos = player_pos
	for id: StringName in _locked.keys():
		var s: SecretDefinition = _locked[id]
		if s.condition != null and s.condition.evaluate(_level_root, player_pos, _entered):
			_locked.erase(id)
			unlocked.append(id)
	if not unlocked.is_empty():
		_rebuild_blocked_cells()
		for id in unlocked:
			secret_unlocked.emit(id)
	return unlocked


func is_cell_authorized(cell: Vector2i) -> bool:
	return not _blocked_cells.has(cell)


## Ponto dentro de alguma região ainda bloqueada (para esconder entidades).
func is_point_hidden(p: Vector2) -> bool:
	for id: StringName in _locked:
		for r: Rect2 in _rects[id]:
			if r.has_point(p):
				return true
	return false


## Retângulo encosta em alguma região bloqueada (para esconder plataformas móveis).
func is_rect_hidden(rect: Rect2) -> bool:
	for id: StringName in _locked:
		for r: Rect2 in _rects[id]:
			if r.intersects(rect):
				return true
	return false


func is_unlocked(id: StringName) -> bool:
	return _rects.has(id) and not _locked.has(id)


func locked_count() -> int:
	return _locked.size()


## Volta todos os segredos ao estado bloqueado (debug/QA, tecla F9).
func reset() -> void:
	_entered.clear()
	setup(_definition, _level_root, [] as Array[StringName])
	_dirty = true


func _rebuild_blocked_cells() -> void:
	_blocked_cells.clear()
	var cs := float(_definition.cell_size)
	for id: StringName in _locked:
		for r: Rect2 in _rects[id]:
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				continue
			# Células que encostam na região (área de interseção > 0).
			for cy in range(floori(r.position.y / cs), ceili(r.end.y / cs)):
				for cx in range(floori(r.position.x / cs), ceili(r.end.x / cs)):
					_blocked_cells[Vector2i(cx, cy)] = true
