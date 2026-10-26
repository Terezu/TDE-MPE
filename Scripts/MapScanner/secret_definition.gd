class_name SecretDefinition
extends Resource
## Uma região secreta da fase (spec, seções 6 e 7). Fica em MapDefinition.secrets.
##
## A área da região é a união de `regions` (retângulos globais) com os
## CollisionShape2D de nós SecretArea (grupo "map_secrets") que tenham o mesmo `id`.
## Dica: alinhe a região à grade de células do mapa; qualquer célula que encoste
## na região fica bloqueada enquanto o segredo não for desbloqueado.

## ID estável (chave no arquivo de progresso). Não mude depois de lançado.
@export var id: StringName = &"segredo_01"
@export var regions: Array[Rect2] = []
## Condição de desbloqueio. Sem condição = nunca desbloqueia sozinho.
@export var condition: SecretCondition
