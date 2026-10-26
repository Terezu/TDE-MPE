extends CharacterBody2D

@export var velocidade_andar: float = 150.0
@export var velocidade_correr: float = 250.0
@export var forca_pulo: float = -350.0
@export var gravidade: float = 980.0
@export var max_pulos: int = 2 # 1 = pulo simples, 2 = pulo duplo
## Tempo (s) em que ainda dá para usar o pulo do chão depois de sair da beirada.
@export var tempo_coyote: float = 0.1
## Se o jogador cair abaixo deste Y (global), volta ao ponto inicial.
@export var limite_queda: float = 2000.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var atacando: bool = false
var pulos_feitos: int = 0

var _tempo_fora_do_chao: float = 0.0
var _ponto_inicial: Vector2


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	_ponto_inicial = global_position


func _physics_process(delta: float) -> void:

	if is_on_floor():
		# Ao tocar o chão, os pulos são restaurados.
		pulos_feitos = 0
		_tempo_fora_do_chao = 0.0
	else:
		# Aplica gravidade.
		velocity.y += gravidade * delta
		_tempo_fora_do_chao += delta
		# Saiu da beirada sem pular: passado o tempo de coyote, o pulo do chão
		# é perdido e só sobra o pulo no ar (senão cair da plataforma dava 2 pulos extras).
		if pulos_feitos == 0 and _tempo_fora_do_chao > tempo_coyote:
			pulos_feitos = 1

	# Executa o pulo (no chão ou no ar, até o limite de max_pulos).
	if Input.is_action_just_pressed("Pular") and pulos_feitos < max_pulos:
		velocity.y = forca_pulo
		pulos_feitos += 1

	# Captura o movimento horizontal.
	var direcao := Input.get_axis("ui_left", "ui_right")
	var correndo := Input.is_key_pressed(KEY_SHIFT)

	if direcao != 0:
		if correndo:
			velocity.x = direcao * velocidade_correr
		else:
			velocity.x = direcao * velocidade_andar

		sprite.flip_h = direcao < 0
	else:
		velocity.x = 0

	# Inicia o ataque.
	if Input.is_action_just_pressed("Atacar") and not atacando:
		atacando = true
		sprite.play("attack")

	move_and_slide()

	# Caiu para fora da fase: volta ao início.
	if global_position.y > limite_queda:
		global_position = _ponto_inicial
		velocity = Vector2.ZERO
		pulos_feitos = 0

	# Não interrompe a animação de ataque.
	if atacando:
		return

	# Animações normais.
	if not is_on_floor():
		sprite.play("jump")
	elif direcao == 0:
		sprite.play("idle")
	elif correndo:
		sprite.play("run")
	else:
		sprite.play("walk")


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		atacando = false
