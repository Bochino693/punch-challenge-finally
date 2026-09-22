extends SceneTree

## O QUADRO TEM DE FICAR LISO ENQUANTO A MÁQUINA PROCURA O ARDUINO.
##
## Este arquivo existe por causa de um defeito que TODOS os outros testes
## deixavam passar, porque nenhum deles olhava para o RELÓGIO.
##
## Medido no jogo rodando: enquanto a placa não respondia, o quadro ia a
## 124 ms e a mediana subia de 6,9 para 9,1 ms. A máquina rodava a dez
## quadros por segundo e a tela dizia, calmamente, "procurando Arduino".
## E isso não é um caso raro: é o estado de TODA máquina nos primeiros
## segundos, e o estado da noite inteira naquela em que o cabo está
## solto.
##
## Eram três causas, e este arquivo guarda as três — duas por estrutura,
## uma por tempo:
##
##   1. a leitura da porta esperava 100 ms por um byte, e `poll_events`
##      precisa da mesma tranca que a thread leitora segura enquanto
##      espera. Porta aberta e calada travava o jogo junto;
##   2. a enumeração das seriais, que custa até 105 ms, rodava no laço
##      do jogo;
##   3. a busca insistia no meio do golpe, que é o único momento em que
##      um quadro perdido é visível para quem está jogando.
##
## As duas primeiras são conferidas pela estrutura, que é o que não
## depende da máquina onde o teste roda. A terceira é conferida pelo
## tempo, com folga larga de propósito: o número não precisa ser preciso
## para pegar um quadro de 100 ms voltando.

## Folga larguíssima. Um quadro de 60 Hz tem 16,7 ms; a máquina que roda
## o teste pode ser muito mais lenta que a do salão, e não faz mal. O que
## este número precisa pegar é a ORDEM DE GRANDEZA do defeito antigo —
## quadros de 100 ms e mais.
const TETO_DO_PIOR_QUADRO := 60.0

var falhas := 0

func _ok(condicao: bool, o_que: String) -> void:
	if not condicao:
		falhas += 1
		print("FALHOU: %s" % o_que)

func _initialize() -> void:
	_test_a_leitura_da_porta_nao_segura_o_quadro()
	_test_a_enumeracao_nao_roda_no_laco_do_jogo()
	_test_a_extensao_nativa_nao_e_enumerada_em_thread()
	_test_a_busca_espera_o_golpe_terminar()
	call_deferred("_test_o_quadro_fica_liso_com_a_placa_muda")

## 1) O TETO DA ESPERA DE LEITURA.
##
## Cem milissegundos foi o que estava escrito, e foi o que fez a máquina
## rodar a dez quadros por segundo. Oito é meio quadro no pior caso e
## continua folgado: a 115.200 bauds, a linha mais longa que a placa
## manda atravessa o cabo em cerca de um milissegundo.
func _test_a_leitura_da_porta_nao_segura_o_quadro() -> void:
	_ok(GdSerialLink.ESPERA_DA_LEITURA_MS <= 16,
		"a espera da leitura não pode passar de um quadro (é %d ms)"
			% GdSerialLink.ESPERA_DA_LEITURA_MS)
	_ok(GdSerialLink.ESPERA_DA_LEITURA_MS >= 2,
		"nem pode ser tão curta que a thread leitora só faça girar")

## 2) A ENUMERAÇÃO SAI DO LAÇO.
##
## A prova de que ela é assíncrona é haver uma thread para ela e o laço
## não esperar por essa thread. `_recolher_a_lista` só recolhe quando a
## thread já terminou; se algum dia alguém trocar isso por um
## `wait_to_finish` incondicional, o defeito volta inteiro e em silêncio.
func _test_a_enumeracao_nao_roda_no_laco_do_jogo() -> void:
	var fonte := FileAccess.get_file_as_string("res://scripts/main.gd")
	_ok("_listar_no_fundo" in fonte, "a enumeração precisa acontecer numa thread")
	var recolhe := _corpo_da_funcao(fonte, "_recolher_a_lista")
	_ok(not recolhe.is_empty(), "precisa existir quem recolha o que a thread achou")
	if not recolhe.is_empty():
		_ok("is_alive()" in recolhe,
			"recolher tem de desistir quando a thread ainda está correndo")

## O CORPO DE UMA FUNÇÃO INTEIRO, e não os primeiros N caracteres.
##
## As duas conferências acima liam uma janela de tamanho fixo a partir do
## nome da função, e as duas quebraram pelo mesmo motivo: alguém
## documentou melhor o que a função faz, o comentário empurrou o código
## para fora da janela e o teste passou a procurar uma linha que ele
## mesmo tinha cortado. Falhava sem que nada estivesse errado — o pior
## tipo de teste, porque ensina a ignorá-lo.
func _corpo_da_funcao(fonte: String, nome: String) -> String:
	var i := fonte.find("func %s" % nome)
	if i < 0:
		return ""
	var fim := fonte.find("\nfunc ", i + 1)
	return fonte.substr(i, (fim - i) if fim > i else -1)

## A extensão GdSerial é consultada pela thread principal em `poll_events`.
## Entregar o mesmo objeto nativo à thread de enumeração cria uma corrida que,
## no Windows sem Arduino conectado, pode abortar o processo inteiro.
func _test_a_extensao_nativa_nao_e_enumerada_em_thread() -> void:
	var fonte := FileAccess.get_file_as_string("res://scripts/main.gd")
	var corpo := _corpo_da_funcao(fonte, "_pedir_a_lista")
	_ok(not corpo.is_empty(), "precisa existir quem agenda a enumeração das portas")
	if not corpo.is_empty():
		_ok("SerialLink.CAMINHO_NATIVO" in corpo,
			"a enumeração em thread precisa excluir a extensão nativa")
		_ok(corpo.find("SerialLink.CAMINHO_NATIVO") < corpo.find("_thread_portas.start"),
			"a proteção da extensão nativa precisa vir antes de iniciar a thread")

## 3) A BUSCA ESPERA O GOLPE TERMINAR — e não para sempre.
func _test_a_busca_espera_o_golpe_terminar() -> void:
	var jogo := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(jogo)
	jogo.animation_time = 100.0
	for estado in [GameDef.State.COUNTDOWN, GameDef.State.ARMED,
			GameDef.State.MEASURING, GameDef.State.RESULT]:
		jogo.state = estado
		jogo._busca_adiada_desde = -1.0
		_ok(not jogo._hora_de_procurar(), "no meio do golpe (estado %d) a busca espera" % estado)
	# E o teto: uma rodada atrás da outra não pode virar desistência.
	jogo.state = GameDef.State.ARMED
	jogo._busca_adiada_desde = -1.0
	jogo._hora_de_procurar()
	jogo.animation_time += jogo.TETO_DA_ESPERA_DO_SOCO + 0.1
	_ok(jogo._hora_de_procurar(), "passado o teto, a busca volta mesmo no meio do golpe")
	# Fora do golpe, sempre.
	jogo.state = GameDef.State.IDLE
	_ok(jogo._hora_de_procurar(), "parada, a máquina procura à vontade")
	jogo.queue_free()

## 4) E O RELÓGIO CONFIRMA.
##
## O jogo roda de verdade, com a busca serial ligada e nenhuma placa do
## outro lado, que é a condição exata do defeito. Nenhum quadro pode
## passar do teto.
var _jogo: Control
var _quadro := 0
var _pior := 0.0

func _test_o_quadro_fica_liso_com_a_placa_muda() -> void:
	_jogo = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_jogo)

func _process(delta: float) -> bool:
	if _jogo == null:
		return false
	_quadro += 1
	match _quadro:
		30:
			_jogo.credits = 9
			_jogo.game_mode = "credit"
		60:
			_jogo._pressionou_start()
		240:
			_jogo._registrar_impacto(9999, 16.5, true)
	# Os primeiros quadros carregam fonte, som e cena: não são o que este
	# teste mede, e medi-los só produziria uma falha por motivo errado.
	if _quadro > 90:
		_pior = maxf(_pior, delta * 1000.0)
	if _quadro < 420:
		return false
	_ok(_pior <= TETO_DO_PIOR_QUADRO,
		"nenhum quadro pode passar de %.0f ms com a placa muda (o pior foi %.1f)"
			% [TETO_DO_PIOR_QUADRO, _pior])
	print("pior quadro: %.1f ms" % _pior)
	if falhas == 0:
		print("QUADRO_LISO_OK")
	quit(1 if falhas > 0 else 0)
	return true
