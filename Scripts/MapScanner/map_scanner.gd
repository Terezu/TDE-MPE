class_name MapScanner
extends Node2D
## Nó coordenador local à cena de cada fase (spec, seção 7).
##
## Cria os componentes como nós filhos independentes, aguarda Camera2D e
## jogador válidos e só então ativa a observação. Não altera o gameplay.
##
## Grupos (spec, seção 7):
##   map_player            -> o jogador (obrigatório)
##   map_static_terrain    -> TileMapLayer / StaticBody2D do terreno estático
##   map_dynamic_terrain   -> portas, paredes destrutíveis, mecanismos (sinal opcional `map_changed`)
##   map_moving_platforms  -> plataformas móveis
##   map_enemies           -> inimigos
##   map_collectibles      -> colecionáveis
##   map_secrets           -> nós SecretArea (área desenhada de um segredo)
##
## Registro híbrido: varredura inicial dos grupos + sinais node_added/node_removed
## da SceneTree para objetos criados/removidos depois (sem duplicar). Nós que
## entram num grupo só depois de estarem na árvore podem ser avisados com
## register_object().
##
## Política de atualização (spec, seção 9):
##   todo frame      -> marcador do jogador, janela do minimapa, posição dos
##                      inimigos/plataformas observados;
##   periódico       -> descoberta de células, quais entidades estão observadas,
##                      avaliação de segredos (só se houve evento ou movimento);
##   por eventos     -> portas/paredes (map_changed, remoção), coleta, morte,
##                      criação/remoção de objetos, desbloqueio de segredos.

const GROUP_PLAYER := &"map_player"

@export var definition: MapDefinition
@export var hud_layer: int = 10
## Restaura e grava o progresso via autoload MapPersistenceManager.
@export var use_persistence: bool = true
## Só para testes/QA: F9 apaga o progresso salvo, as células descobertas e re-bloqueia segredos.
@export var debug_keys: bool = false
@export var show_minimap: bool = true:
	set(value):
		show_minimap = value
		if _canvas != null:
			_canvas.visible = value

var tracker: ExplorationTracker
var terrain: TerrainScanner
var entities: EntityTracker
var secrets: SecretRegionManager
var renderer: MinimapRenderer

var _canvas: CanvasLayer
var _persistence: Node
var _level_root: Node
var _player: Node2D
var _active: bool = false
var _detect_timer: float = 0.0


func _ready() -> void:
	# 1) Ler a MapDefinition.
	if definition == null:
		push_warning("MapScanner: nenhuma MapDefinition atribuída; usando valores padrão.")
		definition = MapDefinition.new()
	_level_root = owner if owner != null else get_parent()

	tracker = ExplorationTracker.new()
	tracker.name = "ExplorationTracker"
	add_child(tracker)
	tracker.setup(definition)

	# 2) Restaurar progresso (células e segredos completos).
	var unlocked: Array[StringName] = []
	if use_persistence:
		_persistence = get_node_or_null("/root/MapPersistenceManager")
		if _persistence == null:
			push_warning("MapScanner: autoload 'MapPersistenceManager' não registrado; o progresso não será salvo.")
		else:
			tracker.restore_cells(_persistence.get_map_cells(definition.map_id, definition.cell_size))
			unlocked = _persistence.get_unlocked_secrets(definition.map_id)
			tracker.cells_discovered.connect(_on_cells_discovered)

	secrets = SecretRegionManager.new()
	secrets.name = "SecretRegionManager"
	add_child(secrets)
	secrets.setup(definition, _level_root, unlocked)
	secrets.secret_unlocked.connect(_on_secret_unlocked)
	tracker.authorizer = secrets.is_cell_authorized

	# 3) Registrar objetos e 4) preparar geometria.
	terrain = TerrainScanner.new()
	terrain.name = "TerrainScanner"
	add_child(terrain)
	terrain.setup(definition)
	terrain.scan_static()
	terrain.dynamic_changed.connect(secrets.request_evaluation)

	entities = EntityTracker.new() # observações temporárias: morrem com a cena
	entities.name = "EntityTracker"
	add_child(entities)
	entities.setup(definition, secrets, terrain)

	for group in [TerrainScanner.GROUP_DYNAMIC_TERRAIN, EntityTracker.GROUP_ENEMIES,
			EntityTracker.GROUP_COLLECTIBLES, EntityTracker.GROUP_MOVING_PLATFORMS]:
		for node in get_tree().get_nodes_in_group(group):
			register_object(node)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)

	_canvas = CanvasLayer.new()
	_canvas.name = "MinimapLayer"
	_canvas.layer = hud_layer
	_canvas.visible = show_minimap
	add_child(_canvas)

	renderer = MinimapRenderer.new()
	renderer.name = "MinimapRenderer"
	_canvas.add_child(renderer)
	renderer.setup(definition, tracker, terrain, entities, secrets)
	# 5) A observação só é ativada em _process, quando câmera e limites forem válidos.


func _exit_tree() -> void:
	# Saída da fase: interrompe observação, desconecta eventos e pede gravação.
	_active = false
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if get_tree().node_removed.is_connected(_on_node_removed):
		get_tree().node_removed.disconnect(_on_node_removed)
	if tracker != null and tracker.cells_discovered.is_connected(_on_cells_discovered):
		tracker.cells_discovered.disconnect(_on_cells_discovered)
	if entities != null:
		entities.clear()
	if is_instance_valid(_persistence):
		_persistence.save_now()


## Registra manualmente um objeto (útil se ele entrou no grupo depois de entrar na árvore).
func register_object(node: Node) -> void:
	entities.register(node)
	terrain.register_dynamic(node)


## Gameplay pode chamar isto quando um mecanismo muda (alavanca, interruptor...)
## para que os segredos sejam reavaliados no próximo tick.
func notify_world_event() -> void:
	secrets.request_evaluation()


func _on_node_added(node: Node) -> void:
	if EntityTracker.kind_of(node) >= 0 or node.is_in_group(TerrainScanner.GROUP_DYNAMIC_TERRAIN):
		register_object(node)


func _on_node_removed(node: Node) -> void:
	if node.is_in_group(TerrainScanner.GROUP_DYNAMIC_TERRAIN):
		terrain.unregister_dynamic(node)
	if EntityTracker.kind_of(node) >= 0:
		entities.unregister(node) # morte / coleta / remoção
	secrets.request_evaluation()


func _unhandled_key_input(event: InputEvent) -> void:
	if not debug_keys:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F9:
		tracker.clear()
		entities.clear()
		secrets.reset()
		if is_instance_valid(_persistence):
			_persistence.clear_map(definition.map_id)
		print("MapScanner: progresso de '%s' apagado e segredos bloqueados de novo (F9)." % definition.map_id)


func _on_cells_discovered(cells: Array[Vector2i]) -> void:
	if is_instance_valid(_persistence):
		_persistence.add_cells(definition.map_id, definition.cell_size, cells)


func _on_secret_unlocked(id: StringName) -> void:
	# Persistir só a descoberta completa; as células da sala serão descobertas
	# normalmente pela câmera (nada é revelado de uma vez).
	if is_instance_valid(_persistence):
		_persistence.add_secret(definition.map_id, id)
	tracker.invalidate_view()
	print("MapScanner: segredo '%s' desbloqueado." % id)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()

	# Observação só fica ativa com jogador, Camera2D e limites válidos.
	if _active and (not is_instance_valid(_player) or camera == null):
		_active = false
	if not _active:
		_try_activate(camera)
		return

	var camera_rect := _camera_rect(camera)

	# Periódico: descoberta de células, entidades observadas, segredos.
	_detect_timer -= delta
	if _detect_timer <= 0.0:
		_detect_timer = definition.detection_interval
		secrets.evaluate(_player.global_position)
		tracker.observe(camera_rect)
		entities.detect(camera_rect)

	# Todo frame: só o que é barato e visual.
	terrain.flush_dynamic() # não faz nada se nenhum objeto avisou mudança
	entities.update_visuals()
	renderer.update_view(_player.global_position, camera_rect, delta)


func _try_activate(camera: Camera2D) -> void:
	if camera == null:
		return
	if definition.world_bounds.size.x <= 0.0 or definition.world_bounds.size.y <= 0.0:
		return
	var candidate := get_tree().get_first_node_in_group(GROUP_PLAYER) as Node2D
	if candidate == null:
		return
	_player = candidate
	_active = true
	_detect_timer = 0.0


## Retângulo visível da câmera em coordenadas globais (rotação da câmera ignorada).
func _camera_rect(camera: Camera2D) -> Rect2:
	var view_size := get_viewport().get_visible_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - view_size * 0.5, view_size)
