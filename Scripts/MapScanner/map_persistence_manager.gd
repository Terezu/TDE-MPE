extends Node
## Autoload global: progresso permanente do MapScanner (spec, seções 7 e 8).
##
## Registrar em Projeto > Configurações do Projeto > Globais (Autoload) com o
## nome "MapPersistenceManager". Não manipula nós da fase: recebe dados e grava.
##
## Guarda por ID de fase (um único progresso, sem slots):
##   - a grade de células exploradas;
##   - os IDs dos segredos completamente descobertos (desbloqueados).
## Observações temporárias de inimigos/colecionáveis NUNCA entram aqui.
##
## Arquivo: user://map_progress.json, versionado. Gravação segura: escreve em
## .tmp, valida, move o arquivo atual para .bak e só então promove o .tmp.
## Se o arquivo principal estiver inválido na leitura, usa o .bak.

signal saved

const SAVE_PATH := "user://map_progress.json"
const TMP_PATH := "user://map_progress.json.tmp"
const BAK_PATH := "user://map_progress.json.bak"
const FORMAT_VERSION := 2 # v2 = v1 + "secrets"; arquivos v1 continuam sendo lidos

## Intervalo da gravação periódica, em segundos (30 s é só sugestão da spec).
var save_interval: float = 30.0

var _maps: Dictionary = {} # String(map_id) -> { "cell_size": int, "cells": Dictionary[Vector2i, true], "secrets": Dictionary[String, true] }
var _dirty: bool = false
var _timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # continua salvando com o jogo pausado
	_load()
	_timer = Timer.new()
	_timer.wait_time = save_interval
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


func _exit_tree() -> void:
	save_now()


func _notification(what: int) -> void:
	# Fechamento normal da janela e app indo para segundo plano (mobile).
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_now()


## Células exploradas salvas para a fase. Vazio se não há progresso ou se o
## tamanho de célula mudou (a grade antiga deixa de ser compatível).
func get_map_cells(map_id: StringName, cell_size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var key := String(map_id)
	if not _maps.has(key):
		return out
	var entry: Dictionary = _maps[key]
	if int(entry["cell_size"]) == 0 or (entry["cells"] as Dictionary).is_empty():
		return out
	if int(entry["cell_size"]) != cell_size:
		push_warning("MapPersistenceManager: cell_size de '%s' mudou (%d -> %d); progresso antigo ignorado." % [key, entry["cell_size"], cell_size])
		return out
	for cell: Vector2i in entry["cells"]:
		out.append(cell)
	return out


## Acumula células recém-descobertas em memória (a gravação é periódica/em eventos).
func add_cells(map_id: StringName, cell_size: int, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var key := String(map_id)
	if not _maps.has(key):
		_maps[key] = {"cell_size": cell_size, "cells": {}, "secrets": {}}
	elif int(_maps[key]["cell_size"]) != cell_size:
		# Grade antiga incompatível: descarta as células, mas mantém os segredos.
		_maps[key]["cell_size"] = cell_size
		_maps[key]["cells"] = {}
	var store: Dictionary = _maps[key]["cells"]
	for cell in cells:
		store[cell] = true
	_dirty = true


## IDs dos segredos completamente descobertos na fase.
func get_unlocked_secrets(map_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var key := String(map_id)
	if _maps.has(key):
		for id: String in _maps[key]["secrets"]:
			out.append(StringName(id))
	return out


## Registra um segredo completamente descoberto e grava na hora (evento raro e importante).
func add_secret(map_id: StringName, secret_id: StringName) -> void:
	var key := String(map_id)
	if not _maps.has(key):
		_maps[key] = {"cell_size": 0, "cells": {}, "secrets": {}}
	var store: Dictionary = _maps[key]["secrets"]
	if store.has(String(secret_id)):
		return
	store[String(secret_id)] = true
	_dirty = true
	save_now()


## Apaga o progresso de uma fase (uso em debug/QA).
func clear_map(map_id: StringName) -> void:
	if _maps.erase(String(map_id)):
		_dirty = true
		save_now()


## Apaga todo o progresso (uso em debug/QA).
func clear_all() -> void:
	_maps.clear()
	_dirty = true
	save_now()


## Grava se houver alterações pendentes. Retorna false se a gravação falhar
## (o último arquivo válido continua intacto).
func save_now() -> bool:
	if not _dirty:
		return true

	var out_maps := {}
	for key: String in _maps:
		var entry: Dictionary = _maps[key]
		var flat: Array = []
		for cell: Vector2i in entry["cells"]:
			flat.append(cell.x)
			flat.append(cell.y)
		out_maps[key] = {"cell_size": entry["cell_size"], "cells": flat, "secrets": (entry["secrets"] as Dictionary).keys()}
	var text := JSON.stringify({"version": FORMAT_VERSION, "maps": out_maps})

	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("MapPersistenceManager: não foi possível abrir %s (erro %d)." % [TMP_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.flush()
	file.close()

	# Só promove o .tmp se ele puder ser lido de volta.
	if _read_file(TMP_PATH).is_empty():
		push_error("MapPersistenceManager: gravação temporária inválida; arquivo anterior mantido.")
		return false

	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BAK_PATH):
			DirAccess.remove_absolute(BAK_PATH)
		DirAccess.rename_absolute(SAVE_PATH, BAK_PATH)
	var err := DirAccess.rename_absolute(TMP_PATH, SAVE_PATH)
	if err != OK:
		push_error("MapPersistenceManager: falha ao promover o arquivo (erro %d); o .bak guarda o último progresso válido." % err)
		return false

	_dirty = false
	saved.emit()
	return true


func _on_timer_timeout() -> void:
	save_now()


func _load() -> void:
	_maps.clear()
	var data := _read_file(SAVE_PATH)
	if data.is_empty():
		data = _read_file(BAK_PATH)
		if not data.is_empty():
			push_warning("MapPersistenceManager: arquivo principal inválido; progresso recuperado do backup.")
	if data.is_empty():
		return

	var maps: Variant = data.get("maps", {})
	if typeof(maps) != TYPE_DICTIONARY:
		return
	for key: Variant in maps:
		var entry: Variant = maps[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var cell_size := int(entry.get("cell_size", 0))
		var flat: Variant = entry.get("cells", [])
		var secret_list: Variant = entry.get("secrets", []) # ausente em arquivos v1
		if typeof(flat) != TYPE_ARRAY or typeof(secret_list) != TYPE_ARRAY:
			continue
		var cells := {}
		if cell_size > 0:
			var i := 0
			while i + 1 < flat.size():
				cells[Vector2i(int(flat[i]), int(flat[i + 1]))] = true
				i += 2
		var secrets := {}
		for id: Variant in secret_list:
			secrets[str(id)] = true
		_maps[String(key)] = {"cell_size": cell_size, "cells": cells, "secrets": secrets}


## Lê e valida um arquivo de progresso. Retorna {} se ausente, ilegível ou de versão desconhecida.
func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var version := int(parsed.get("version", 0))
	if version < 1 or version > FORMAT_VERSION:
		push_warning("MapPersistenceManager: versão de arquivo não suportada (%d)." % version)
		return {}
	return parsed
