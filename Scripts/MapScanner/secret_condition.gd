class_name SecretCondition
extends Resource
## Condição de desbloqueio de uma região secreta (spec, seção 6).
##
## Tipos:
##   ENTRADA_FISICA   -> o jogador entrou em `area` (retângulo global) nesta visita.
##   NO_REMOVIDO      -> o nó em `node_path` não existe mais (ex.: parede destruída).
##   PROPRIEDADE      -> o nó em `node_path` tem `property` == `expected` (ex.: porta.aberta == true).
##   TODAS (AND)      -> todas as `children` verdadeiras.
##   QUALQUER (OR)    -> pelo menos uma das `children` verdadeira.
##
## O MapScanner NÃO guarda o estado de portas/paredes: NO_REMOVIDO e PROPRIEDADE
## consultam o nó de gameplay toda vez que são avaliadas. Caminhos são relativos
## à raiz da cena da fase (o "owner" do MapScanner).

enum Type { ENTRADA_FISICA, NO_REMOVIDO, PROPRIEDADE, TODAS, QUALQUER }

@export var type: Type = Type.ENTRADA_FISICA
## ENTRADA_FISICA: retângulo global em pixels.
@export var area: Rect2 = Rect2()
## NO_REMOVIDO / PROPRIEDADE: nó de gameplay consultado.
@export var node_path: NodePath
## PROPRIEDADE: nome da propriedade e valor esperado.
@export var property: StringName
@export var expected: bool = true
## TODAS / QUALQUER: subcondições (SecretCondition). Tipado como Resource porque
## um Array[SecretCondition] dentro da própria classe cria referência cíclica
## no script e vaza memória ao fechar o jogo.
@export var children: Array[Resource] = []


## Avalia a condição. `level_root` resolve os caminhos; `entered` guarda quais
## condições de entrada física já foram cumpridas nesta visita (memória temporária).
func evaluate(level_root: Node, player_pos: Vector2, entered: Dictionary) -> bool:
	match type:
		Type.ENTRADA_FISICA:
			var key := get_instance_id()
			if not entered.has(key) and area.has_point(player_pos):
				entered[key] = true
			return entered.has(key)
		Type.NO_REMOVIDO:
			return level_root != null and not level_root.has_node(node_path)
		Type.PROPRIEDADE:
			if level_root == null or not level_root.has_node(node_path):
				return false
			return level_root.get_node(node_path).get(property) == expected
		Type.TODAS:
			var all_ok := not children.is_empty()
			for c: Resource in children:
				# avalia todas para que as entradas físicas sejam registradas
				all_ok = c.call(&"evaluate", level_root, player_pos, entered) and all_ok
			return all_ok
		Type.QUALQUER:
			var any_ok := false
			for c: Resource in children:
				any_ok = c.call(&"evaluate", level_root, player_pos, entered) or any_ok
			return any_ok
	return false
