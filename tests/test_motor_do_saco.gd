extends SceneTree

## O MOTOR DO SACO SOB TESTE.
##
## Este arquivo existe porque um motor não é um LED. Um LED aceso por
## engano é um LED aceso; um motor ligado por engano é uma correia
## arrebentada, um saco no chão ou um fim de curso destruído — e
## acontece longe de quem programou, numa festa, às onze da noite.
##
## O que ele guarda são as quatro promessas do projeto:
##
##   1. o jogo diz ONDE o saco deve estar, nunca "liga o motor". Pedir a
##      mesma coisa mil vezes não liga nada mil vezes;
##   2. nada bloqueia: o passo do motor devolve vazio na esmagadora
##      maioria dos quadros;
##   3. quando a placa não responde, o jogo DESISTE e admite que não sabe
##      onde o saco está — insistir para sempre é o laço infinito com
##      outro nome;
##   4. sem motor ligado, o jogo é exatamente o mesmo.
##
## E o firmware tem o seu próprio verificador: `sh tools/conferir_firmware.sh`
## compila o sketch e falha se alguém reintroduzir um laço infinito.

var falhas := 0

func _ok(condicao: bool, o_que: String) -> void:
	if not condicao:
		falhas += 1
		print("FALHOU: %s" % o_que)

func _initialize() -> void:
	_test_desligado_nao_manda_nada()
	_test_a_intencao_nao_vira_comando_repetido()
	_test_pedir_o_lugar_onde_ja_esta_nao_manda_nada()
	_test_sem_resposta_o_jogo_desiste()
	_test_o_curso_longo_nao_vira_desistencia()
	_test_parar_apaga_a_intencao()
	_test_o_protocolo_do_motor_ida_e_volta()
	_test_os_limites_sao_os_mesmos_dos_dois_lados()
	_test_o_firmware_nunca_liga_os_dois_sentidos()
	if falhas == 0:
		print("MOTOR_OK")
	quit(1 if falhas > 0 else 0)

func _motor(ligado := true) -> SacoMotor:
	var m := SacoMotor.new()
	m.ligado = ligado
	m.curso_ms = 3500
	# Nasce em cima e parado, que é o estado depois de uma subida.
	m.receber({"estado": ArduinoProtocol.MOTOR_PARADO,
		"posicao": ArduinoProtocol.POS_EM_CIMA, "resta_ms": 0})
	return m

## 1) SEM MOTOR LIGADO, O JOGO É O MESMO. Esta é a diferença entre um
## recurso e uma dependência: um gabinete sem motor joga igual.
func _test_desligado_nao_manda_nada() -> void:
	var m := _motor(false)
	m.quero(SacoMotor.Onde.EM_BAIXO)
	for i in range(200):
		_ok(m.passo().is_empty(), "desligado, o motor não pode mandar nada")

## 2) INTENÇÃO REPETIDA NÃO É COMANDO REPETIDO.
##
## O jogo chama `passo()` a cada quadro — sessenta vezes por segundo. Se
## cada chamada virasse um comando, a placa receberia sessenta ordens de
## descida por segundo e o cabo viraria o gargalo. Um pedido por segundo
## basta para cobrir o caso de a placa reiniciar e perder o comando.
func _test_a_intencao_nao_vira_comando_repetido() -> void:
	var m := _motor()
	m.quero(SacoMotor.Onde.EM_BAIXO)
	var mandou := 0
	for i in range(120):
		if not m.passo().is_empty():
			mandou += 1
	_ok(mandou == 1, "em dois segundos de quadros, um comando só (mandou %d)" % mandou)
	# E o primeiro é o certo.
	var m2 := _motor()
	m2.quero(SacoMotor.Onde.EM_BAIXO)
	_ok(m2.passo() == "MOTOR,DESCE", "descer tem de mandar DESCE")

## 3) PEDIR O LUGAR ONDE ELE JÁ ESTÁ NÃO LIGA NADA.
func _test_pedir_o_lugar_onde_ja_esta_nao_manda_nada() -> void:
	var m := _motor()
	m.quero(SacoMotor.Onde.EM_CIMA)
	for i in range(60):
		_ok(m.passo().is_empty(), "já em cima, subir não pode ligar o motor")

## 4) SEM RESPOSTA, O JOGO DESISTE — e admite que não sabe.
##
## Continuar pedindo para sempre seria um laço infinito distribuído entre
## dois aparelhos: o jogo mandando, a placa muda, e ninguém percebendo.
func _test_sem_resposta_o_jogo_desiste() -> void:
	var m := _motor()
	m.quero(SacoMotor.Onde.EM_BAIXO)
	_ok(not m.passo().is_empty(), "o primeiro pedido sai")
	# Seis segundos de silêncio: mais que o curso inteiro e a folga.
	var comeco := Time.get_ticks_msec()
	while Time.get_ticks_msec() - comeco < 100:
		pass
	m._pedido_em_ms -= (m.curso_ms + SacoMotor.FOLGA_DA_CONFIRMACAO_MS + 200)
	_ok(m.passo().is_empty(), "passado o prazo, ele para de pedir")
	_ok(m.desistiu(), "e assume que desistiu")
	_ok(m.posicao == ArduinoProtocol.POS_DESCONHECIDA,
		"e admite que não sabe onde o saco está")
	_ok("NÃO RESPONDEU" in m.ficha(), "e a tela diz isso: %s" % m.ficha())
	# E destravar volta a tentar — a desistência não é permanente.
	m.destravar()
	_ok(not m.passo().is_empty(), "destravar tem de voltar a pedir")

## 5) UM CURSO LONGO NÃO PODE VIRAR DESISTÊNCIA.
##
## Se o operador configurar oito segundos de curso, esperar oito segundos
## é o certo — e enquanto a placa estiver relatando movimento, o relógio
## da desistência anda junto.
func _test_o_curso_longo_nao_vira_desistencia() -> void:
	var m := _motor()
	m.curso_ms = 9000
	m.quero(SacoMotor.Onde.EM_BAIXO)
	m.passo()
	m._pedido_em_ms -= 8000
	m.receber({"estado": ArduinoProtocol.MOTOR_DESCENDO,
		"posicao": ArduinoProtocol.POS_DESCONHECIDA, "resta_ms": 1000})
	_ok(not m.desistiu(), "enquanto a placa relata movimento, não se desiste")
	_ok(m.andando(), "e o jogo sabe que ele está andando")
	_ok(m.progresso() > 0.8, "e quanto falta vira barra: %.2f" % m.progresso())

## 6) PARAR É ORDEM, NÃO INTENÇÃO.
##
## A parada de emergência apaga o que o jogo queria. Sem isso, o quadro
## seguinte religaria o motor que o operador acabou de mandar parar — que
## é o pior defeito possível num botão de emergência.
func _test_parar_apaga_a_intencao() -> void:
	var m := _motor()
	m.quero(SacoMotor.Onde.EM_BAIXO)
	m.passo()
	_ok(m.parar() == "MOTOR,PARA", "parar manda PARA")
	for i in range(120):
		_ok(m.passo().is_empty(), "depois de parar, nada mais sai sozinho")

## 7) O PROTOCOLO FECHA NOS DOIS SENTIDOS.
func _test_o_protocolo_do_motor_ida_e_volta() -> void:
	var m := ArduinoProtocol.parse("MOTOR,1,2,1400")
	_ok(str(m.get("type", "")) == "MOTOR", "a linha do motor tem de ser entendida")
	_ok(int(m.get("estado", -1)) == ArduinoProtocol.MOTOR_DESCENDO, "estado descendo")
	_ok(int(m.get("posicao", -1)) == ArduinoProtocol.POS_EM_BAIXO, "posição em baixo")
	_ok(int(m.get("resta_ms", -1)) == 1400, "quanto falta")
	# E LIXO NÃO PASSA. Uma linha truncada ou com letra no lugar de número
	# não pode virar um estado de motor.
	for ruim in ["MOTOR", "MOTOR,1", "MOTOR,1,2", "MOTOR,a,2,10", "MOTOR,1,2,3,4"]:
		_ok(str(ArduinoProtocol.parse(ruim).get("type", "")) == "",
			"a linha inválida %s não pode passar" % ruim)
	_ok(ArduinoProtocol.build_motor("desce") == "MOTOR,DESCE", "montar DESCE")
	# E UM SENTIDO DESCONHECIDO VIRA PARA. Num comando que liga um motor,
	# o padrão seguro é desligar.
	_ok(ArduinoProtocol.build_motor("qualquer coisa") == "MOTOR,PARA",
		"sentido desconhecido tem de virar PARA")

## 8) OS LIMITES SÃO OS MESMOS DOS DOIS LADOS DO CABO.
##
## Um valor que o jogo aceita e a placa recusa vira uma configuração que
## parece ter sido gravada e não foi — e o operador passa a noite mexendo
## num número que não muda nada.
func _test_os_limites_sao_os_mesmos_dos_dois_lados() -> void:
	_ok(ArduinoProtocol.build_motor_config(99999, 99999, true) == "MOTOR,CONFIG,15000,2000,1",
		"o jogo tem de aparar no mesmo teto do firmware")
	_ok(ArduinoProtocol.build_motor_config(0, 0, false) == "MOTOR,CONFIG,200,50,0",
		"e no mesmo piso")
	var firmware := FileAccess.get_file_as_string(
		"res://ARDUINO_SENSOR_DE_FEIXE_LM393/ARDUINO_SENSOR_DE_FEIXE_LM393.ino"
	)
	_ok("MOTOR_CURSO_MAX_MS = 15000" in firmware,
		"o teto do curso no firmware tem de ser o mesmo 15000")
	_ok("constrain(atol(p), 200L" in firmware, "e o piso, o mesmo 200")

## 9) O FIRMWARE NUNCA LIGA OS DOIS SENTIDOS AO MESMO TEMPO.
##
## Numa ponte H isso é condução cruzada — o componente queima. Num par de
## relés é um curto entre as duas polaridades. Não é um defeito visual:
## é fumaça.
func _test_o_firmware_nunca_liga_os_dois_sentidos() -> void:
	var firmware := FileAccess.get_file_as_string(
		"res://ARDUINO_SENSOR_DE_FEIXE_LM393/ARDUINO_SENSOR_DE_FEIXE_LM393.ino"
	)
	_ok("void motorParar" in firmware, "tem de existir um lugar só que desliga tudo")
	# Só existe UM trecho que escreve HIGH nos dois pinos, e ele escreve
	# um HIGH e um LOW conforme o sentido — nunca dois HIGH.
	_ok(not ("digitalWrite(PIN_MOTOR_DESCE, HIGH);" in firmware
		and "digitalWrite(PIN_MOTOR_SOBE, HIGH);" in firmware),
		"não pode haver duas escritas HIGH incondicionais nos dois sentidos")
	_ok("motorAtualizar" in firmware, "o curso tem de avançar sem bloquear")
	# O LAÇO INFINITO É PROCURADO NO CÓDIGO SEM COMENTÁRIO, e quem faz
	# isso é `tools/conferir_firmware.sh` — ele passa o sketch pelo
	# pré-processador antes de olhar. Aqui a conferência é a grosseira, e
	# de propósito: procurar a palavra `while` no texto cru reclamaria do
	# próprio comentário que explica por que não há laço nenhum.
	for infinito in ["while (true)", "while(true)", "while (1)", "while(1)"]:
		_ok(not (infinito in firmware), "não pode haver %s no firmware" % infinito)
