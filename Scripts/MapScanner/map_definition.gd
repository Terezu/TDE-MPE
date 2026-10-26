class_name MapDefinition
extends Resource
## Configuração do MapScanner por fase (spec, seção 7).
## Todos os valores marcados como "pendente" na spec (seção 11) são exports
## aqui, para ajustar pelo Inspector durante os testes.

## ID estável da fase. Chave do progresso salvo. Não mude depois de lançado.
@export var map_id: StringName = &"fase_01"

## Limites do mundo configurados manualmente (em pixels, coordenadas globais).
## A janela do minimapa nunca sai daqui e células fora daqui nunca são descobertas.
@export var world_bounds: Rect2 = Rect2(0, 0, 4096, 1088)

## Tamanho da célula lógica de exploração, em pixels do mundo (pendente na spec).
@export_range(8, 512, 1) var cell_size: int = 64

@export_group("HUD")
## Tamanho de referência do minimapa (4:3) na resolução de referência.
@export var hud_reference_size: Vector2 = Vector2(320, 240)
@export var hud_reference_resolution: Vector2 = Vector2(1920, 1080)
## Margem em relação ao canto superior esquerdo, na escala de referência.
@export var hud_margin: float = 16.0
## Limites de escala do HUD (pendentes na spec).
@export_range(0.1, 4.0, 0.05) var hud_min_scale: float = 0.5
@export_range(0.1, 4.0, 0.05) var hud_max_scale: float = 1.5

@export_group("Atualização")
## Intervalo, em segundos, da checagem de descoberta de células (pendente na spec).
@export_range(0.01, 1.0, 0.01) var detection_interval: float = 0.1
## Suavização vertical da janela do minimapa. 0 = sem suavização; maior = mais rápido.
@export_range(0.0, 60.0, 0.5) var vertical_smoothing: float = 8.0

@export_group("Segredos")
## Regiões secretas da fase (ID estável + região + condições de desbloqueio).
@export var secrets: Array[SecretDefinition] = []
