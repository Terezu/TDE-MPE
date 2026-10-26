class_name MinimapRenderer
extends Control
## Componente visual do HUD (spec, seções 2 e 7).
## Só desenha: não decide exploração e não salva nada.

const COLOR_OUTSIDE := Color(0.10, 0.10, 0.12, 0.85)  # fundo neutro fora do mapa
const COLOR_UNKNOWN := Color(0.04, 0.04, 0.05, 0.90)  # dentro do mapa, não descoberto
const COLOR_EXPLORED := Color(0.16, 0.20, 0.28, 0.95) # célula descoberta
const COLOR_TERRAIN := Color(0.78, 0.84, 0.92, 1.0)
const COLOR_DYNAMIC := Color(0.95, 0.65, 0.30, 1.0)     # portas, paredes destrutíveis
const COLOR_PLATFORM := Color(0.35, 0.85, 1.0, 1.0)     # plataformas móveis (só contorno)
const COLOR_ENEMY := Color(0.95, 0.25, 0.25, 1.0)
const ENEMY_STALE_ALPHA := 0.35                          # inimigo fora da câmera (última posição)
const COLOR_COLLECTIBLE := Color(0.30, 0.90, 0.60, 1.0)
const COLOR_CAMERA := Color(1.0, 1.0, 1.0, 0.35)
const COLOR_PLAYER := Color(1.0, 0.85, 0.2, 1.0)
const COLOR_BORDER := Color(1.0, 1.0, 1.0, 0.6)

var _definition: MapDefinition
var _tracker: ExplorationTracker
var _terrain: TerrainScanner
var _entities: EntityTracker
var _secrets: SecretRegionManager

var _player_pos: Vector2 = Vector2.ZERO
var _camera_rect: Rect2 = Rect2()
var _smooth_y: float = 0.0
var _has_smooth: bool = false
var _window: Rect2 = Rect2() # região do mundo mostrada agora


func setup(definition: MapDefinition, tracker: ExplorationTracker, terrain: TerrainScanner, entities: EntityTracker = null, secrets: SecretRegionManager = null) -> void:
	_definition = definition
	_tracker = tracker
	_terrain = terrain
	_entities = entities
	_secrets = secrets
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()


## Chamado a cada frame pelo MapScanner.
func update_view(player_pos: Vector2, camera_rect: Rect2, delta: float) -> void:
	_player_pos = player_pos
	_camera_rect = camera_rect
	if not _has_smooth or _definition.vertical_smoothing <= 0.0:
		_smooth_y = player_pos.y
		_has_smooth = true
	else:
		_smooth_y = lerpf(_smooth_y, player_pos.y, 1.0 - exp(-_definition.vertical_smoothing * delta))
	_window = _compute_window(camera_rect.size)
	queue_redraw()


## Posiciona e escala o HUD: canto superior esquerdo, 4:3, escala uniforme
## limitada entre hud_min_scale e hud_max_scale.
func _update_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var ref := _definition.hud_reference_resolution
	var s := clampf(minf(vp.x / ref.x, vp.y / ref.y), _definition.hud_min_scale, _definition.hud_max_scale)
	size = _definition.hud_reference_size * s
	position = Vector2.ONE * _definition.hud_margin * s
	queue_redraw()


## Janela do mundo coberta pelo minimapa: >= 2x a largura E 2x a altura da câmera,
## mantendo a proporção 4:3 (amplia o eixo necessário, sem distorcer).
func _compute_window(camera_size: Vector2) -> Rect2:
	var aspect := _definition.hud_reference_size.x / _definition.hud_reference_size.y
	var w := maxf(camera_size.x * 2.0, camera_size.y * 2.0 * aspect)
	var h := w / aspect
	var bounds := _definition.world_bounds
	var cx := _center_on_axis(_player_pos.x, w, bounds.position.x, bounds.size.x)
	var cy := _center_on_axis(_smooth_y, h, bounds.position.y, bounds.size.y)
	return Rect2(Vector2(cx - w * 0.5, cy - h * 0.5), Vector2(w, h))


## Segue o jogador, sem sair dos limites. Se o mapa é menor que a janela,
## centraliza (a escala não muda; o exterior fica com fundo neutro).
static func _center_on_axis(target: float, extent: float, bounds_start: float, bounds_len: float) -> float:
	if bounds_len <= extent:
		return bounds_start + bounds_len * 0.5
	return clampf(target, bounds_start + extent * 0.5, bounds_start + bounds_len - extent * 0.5)


func _draw() -> void:
	if _definition == null or _window.size.x <= 0.0:
		return

	var k := size.x / _window.size.x # pixels de HUD por unidade de mundo
	var ui_scale := size.x / _definition.hud_reference_size.x
	var bounds := _definition.world_bounds

	draw_rect(Rect2(Vector2.ZERO, size), COLOR_OUTSIDE)

	var shown := bounds.intersection(_window)
	if shown.size.x > 0.0 and shown.size.y > 0.0:
		draw_rect(_to_hud(shown, k), COLOR_UNKNOWN)

		var cs := float(_definition.cell_size)
		var x0 := floori(shown.position.x / cs)
		var y0 := floori(shown.position.y / cs)
		var x1 := ceili(shown.end.x / cs) - 1
		var y1 := ceili(shown.end.y / cs) - 1
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var cell := Vector2i(cx, cy)
				if not _is_known(cell):
					continue
				var cell_rect := Rect2(Vector2(cx, cy) * cs, Vector2(cs, cs)).intersection(bounds)
				draw_rect(_to_hud(cell_rect, k), COLOR_EXPLORED)
				for r: Rect2 in _terrain.get_cell_rects(cell):
					draw_rect(_to_hud(r, k), COLOR_TERRAIN)

		# Terreno dinâmico: estado atual, recortado só nas células descobertas.
		for r: Rect2 in _terrain.get_dynamic_rects():
			var part := r.intersection(shown)
			if part.size.x <= 0.0 or part.size.y <= 0.0:
				continue
			for dcy in range(floori(part.position.y / cs), ceili(part.end.y / cs)):
				for dcx in range(floori(part.position.x / cs), ceili(part.end.x / cs)):
					if not _is_known(Vector2i(dcx, dcy)):
						continue
					var piece := part.intersection(Rect2(Vector2(dcx, dcy) * cs, Vector2(cs, cs)))
					if piece.size.x > 0.0 and piece.size.y > 0.0:
						draw_rect(_to_hud(piece, k), COLOR_DYNAMIC)

	# Entidades observadas (temporárias).
	if _entities != null:
		for m: Dictionary in _entities.get_markers():
			match m["kind"]:
				EntityTracker.Kind.PLATFORM:
					for r: Rect2 in m["rects"]:
						var hr := _to_hud(r, k)
						draw_rect(hr, COLOR_PLATFORM, false, maxf(1.0, 1.5 * ui_scale))
				EntityTracker.Kind.ENEMY:
					var p: Vector2 = m["pos"]
					if not _window.has_point(p):
						continue
					var c := COLOR_ENEMY
					if not m["visible"]:
						c.a = ENEMY_STALE_ALPHA # última posição conhecida
					draw_circle((p - _window.position) * k, 3.0 * ui_scale, c)
				EntityTracker.Kind.COLLECTIBLE:
					var p: Vector2 = m["pos"]
					if not _window.has_point(p):
						continue
					var hp := (p - _window.position) * k
					var d := 3.0 * ui_scale
					draw_colored_polygon(PackedVector2Array([hp + Vector2(0, -d), hp + Vector2(d, 0), hp + Vector2(0, d), hp + Vector2(-d, 0)]), COLOR_COLLECTIBLE)

	# Enquadramento atual da câmera e marcador do jogador (posição verdadeira).
	draw_rect(_to_hud(_camera_rect, k), COLOR_CAMERA, false, maxf(1.0, ui_scale))
	draw_circle((_player_pos - _window.position) * k, 4.0 * ui_scale, COLOR_PLAYER)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDER, false, 2.0 * ui_scale)


func _to_hud(world_rect: Rect2, k: float) -> Rect2:
	return Rect2((world_rect.position - _window.position) * k, world_rect.size * k)


## Célula descoberta e não protegida por segredo bloqueado.
func _is_known(cell: Vector2i) -> bool:
	return _tracker.is_discovered(cell) and (_secrets == null or _secrets.is_cell_authorized(cell))
