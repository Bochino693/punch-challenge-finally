extends SceneTree

## Ferramenta de desenvolvimento: abre a cena principal, força cada
## momento do jogo e salva um PNG de cada um em user://telas/.
## Uso: godot --path . --script tools/capturar_telas.gd

const TELA := Vector2i(1080, 1920)
var jogo: Control
var passos: Array = []
var indice := 0
var espera := 0
var destino := ""

func _initialize() -> void:
	destino = OS.get_environment("PUNCH_SHOTS")
	if destino.is_empty():
		destino = "res://.telas"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destino))
	DisplayServer.window_set_size(TELA)
	get_root().content_scale_size = TELA
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var cena: PackedScene = load("res://scenes/main.tscn")
	jogo = cena.instantiate()
	get_root().add_child(jogo)
	passos = [
		{"nome": "01_abertura", "fn": _abertura},
		{"nome": "01b_recordes", "fn": _abertura_recordes},
		{"nome": "01c_como_jogar", "fn": _abertura_como_jogar},
		{"nome": "02_contagem", "fn": _contagem},
		{"nome": "03_espera", "fn": _espera},
		{"nome": "04_carga", "fn": _carga},
		{"nome": "05_impacto", "fn": _impacto},
		{"nome": "05b_nocaute", "fn": _nocaute},
		{"nome": "06_contando", "fn": _contando},
		{"nome": "07_lendario", "fn": _lendario},
		{"nome": "08_forte", "fn": _forte},
		{"nome": "09_leve", "fn": _leve},
		{"nome": "10_central_operacao", "fn": _central.bind(0)},
		{"nome": "11_central_golpe", "fn": _central.bind(1)},
		{"nome": "12_central_camera", "fn": _central.bind(2)},
		{"nome": "13_central_dados", "fn": _central.bind(3)},
		{"nome": "13b_central_saco", "fn": _central.bind(4)},
		{"nome": "14_calibracao_repouso", "fn": _calibracao.bind(0)},
		{"nome": "15_calibracao_golpes", "fn": _calibracao.bind(1)},
		{"nome": "16_calibracao_sugestao", "fn": _calibracao.bind(3)},
	]

func _process(_delta: float) -> bool:
	if indice >= passos.size():
		return true
	if espera == 0:
		passos[indice]["fn"].call()
		espera = 8
		return false
	espera -= 1
	if espera > 0:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png("%s/%s.png" % [destino, passos[indice]["nome"]])
	indice += 1
	espera = 0
	return false

# --------------------------------------------------------------- momentos
func _preparar(estado: int) -> void:
	# A cutscene de entrada roda uma vez ao ligar a máquina e engole a
	# abertura enquanto está no ar. Sem desligá-la aqui, TODA captura de
	# IDLE fotografava a entrada e não a tela que se quer conferir.
	jogo.intro_active = false
	jogo.central_aberta = false
	jogo.state = estado
	jogo.state_time = 1.4
	jogo.animation_time = 3.0

func _abertura() -> void:
	jogo.ranking = RankingStore.migrate([8720, 7050, 6400, 5120, 3880])
	jogo.plays = 431
	jogo.credits = 3
	_preparar(GameDef.State.IDLE)
	jogo.state_time = 2.0

## O rodízio da abertura é por tempo, então cada página é capturada
## colocando o relógio dentro da janela dela.
func _abertura_recordes() -> void:
	_abertura()
	jogo.state_time = jogo.ABERTURA_DURACAO + 2.0

func _abertura_como_jogar() -> void:
	_abertura()
	jogo.state_time = jogo.ABERTURA_DURACAO * 2.0 + 2.0

func _contagem() -> void:
	_preparar(GameDef.State.COUNTDOWN)
	jogo.countdown_left = 2.4
	jogo.moldura.set_estado(LedFrame.CONTAGEM)

func _espera() -> void:
	_preparar(GameDef.State.ARMED)
	jogo.espera_left = 60.0
	jogo.moldura.set_estado(LedFrame.ARMADA)
	_arena_intacta()
	if jogo.arena != null:
		jogo.arena.guardar(true)

## A ARENA NÃO ENTRA SOZINHA NAS CAPTURAS.
##
## Estas telas são montadas à mão, colocando o jogo direto no estado que
## se quer fotografar — elas não passam por `_registrar_impacto`, que é
## quem manda o soco para o lutador. Sem os dois auxiliares abaixo, todas
## as capturas de resultado sairiam com o adversário intacto e de pé, o
## que esconderia justamente o que há de novo para conferir.
func _arena_intacta() -> void:
	jogo.arena_frase = ""
	jogo.arena_nocaute = false
	if jogo.arena != null:
		jogo.arena.preparar()

func _arena_levou(pontos: int) -> void:
	_arena_intacta()
	var nivel := ScoreTier.de(pontos)
	jogo.arena_frase = ArenaFrases.de_golpe(str(nivel["id"]), 2)
	if jogo.arena != null:
		jogo.arena.guardar(false)
		var reacao: Dictionary = jogo.arena.golpe(
			float(pontos) / float(GameDef.SCORE_MAX), float(nivel["hitstop"]) > 0.0
		)
		if bool(reacao["nocaute"]):
			jogo.arena_frase = ArenaFrases.de_nocaute(2)

func _carga() -> void:
	_preparar(GameDef.State.ARMED)
	jogo.espera_left = 55.0
	jogo.espera_left = 55.0

func _impacto() -> void:
	_preparar(GameDef.State.MEASURING)
	jogo.state_time = 0.25
	jogo.result_score = 9034
	_arena_levou(9034)

## O NOCAUTE PRECISA DE DOIS SOCOS, como no jogo: um golpe só nunca
## enche o medidor de dano. Esta captura existe para provar que a queda
## acontece, e que as barras chegam ao fim.
func _nocaute() -> void:
	_resultado(9820, 1.6)
	_arena_levou(9820)
	_arena_levou(9820)
	for i in range(28):
		jogo.arena.avancar(1.0 / 60.0)

func _resultado(pontos: int, veredito: float) -> void:
	_preparar(GameDef.State.RESULT)
	jogo.fx.limpar()
	jogo.result_score = pontos
	jogo.result_speed = 9.4
	jogo.result_simulado = false
	jogo.posicao_no_ranking = 1 if pontos > 900 else (3 if pontos > 600 else 0)
	jogo.displayed_score = float(pontos) if veredito >= 0.0 else float(pontos) * 0.55
	jogo.verdict_time = veredito
	jogo.result_time = 1.9 if veredito >= 0.0 else 1.0
	if veredito >= 0.0:
		jogo.moldura.set_estado(LedFrame.RESULTADO, GameDef.classificar(pontos)["cor_faixa"])
	_arena_levou(pontos)

func _contando() -> void:
	_resultado(9030, -1.0)

func _lendario() -> void:
	_resultado(9610, 1.6)

func _forte() -> void:
	_resultado(6450, 1.6)

func _leve() -> void:
	_resultado(1480, 1.6)

func _central(pagina: int) -> void:
	_preparar(GameDef.State.IDLE)
	jogo.central_aberta = true
	jogo.central_pagina = pagina

## O assistente de calibração, com amostras plantadas para as telas
## saírem cheias — vazias elas não mostram o que se quer conferir.
func _calibracao(passo: int) -> void:
	_central(1)
	jogo._abrir_calibracao()
	jogo.calib_passo = passo
	jogo.calib_repouso_left = 2.4
	jogo.calib_ruido = 0.6
	if passo >= 1:
		jogo.calib_fracos.assign([2.4, 2.0, 3.1])
		jogo.calib_picos.assign([4.0, 5.2, 9.8])
	if passo >= 3:
		jogo.calib_fracos.assign([2.4, 2.0, 3.1, 2.2, 2.6])
		jogo.calib_fortes.assign([11.0, 12.5, 13.9, 12.1, 11.6])
		jogo.calib_picos.assign([4.0, 5.2, 9.8, 4.6, 10.4, 11.0, 9.1, 12.3, 10.0, 9.4])
		jogo.calib_sugestao = Calibracao.sugerir(
			jogo.calib_fracos, jogo.calib_fortes, jogo.calib_picos, jogo.calib_ruido
		)
