class_name CameraDoctor
extends Node

## POR QUE A CÂMERA NÃO APARECE — os quatro casos, separados.
##
## Quando a webcam não entra no jogo, a causa é quase sempre uma destas:
##
##   1. falta a extensão nativa ao lado do jogo  -> o Godot não tem
##      backend de câmera no Windows; tudo passa pela DLL, e o
##      o executável foi separado do PCK para evitar corrupção do cabeçalho.
##      Copiar só o executável deixa para trás o jogo e as DLLs;
##   2. o Windows também não vê a câmera         -> cabo, porta USB ou
##                                                  driver;
##   3. o Windows vê, mas a PRIVACIDADE está     -> é um interruptor, e o
##      fechada para aplicativos de área de         jogo nem chega a
##      trabalho                                    tentar;
##   4. está tudo liberado e outro programa      -> só um programa por vez
##      segura a câmera                             abre uma webcam.
##
## ------------------------------------------------------------------
## ESTE DIAGNÓSTICO NÃO USA MAIS POWERSHELL.
##
## Ele usava, e o custo era desproporcional ao serviço: para ler um valor
## do registro, o jogo precisava desembrulhar um `.ps1` do pacote para o
## AppData (porque `res://` não é um arquivo que um programa de fora
## consiga abrir quando o PCK está embutido), gravá-lo em disco, e
## chamar `powershell.exe -ExecutionPolicy Bypass` em cima dele. Isso é:
##
##   • um arquivo a mais para o antivírus examinar — e um `.ps1`
##     recém-gravado no AppData é exatamente o padrão que o Defender
##     inspeciona com mais cuidado;
##   • uma política de execução a mais para uma máquina corporativa
##     barrar, justamente na tela em que o operador foi pedir socorro;
##   • quase um segundo só para o PowerShell subir.
##
## `reg.exe`, `tasklist.exe` e `pnputil.exe` respondem as mesmas
## perguntas, existem em todo Windows desde sempre, sobem em
## milissegundos, não têm política de execução e não precisam que nada
## seja gravado em disco.

signal terminou

## O interruptor "permitir que aplicativos de área de trabalho acessem sua
## câmera". `NonPackaged` é justamente o ramo dos programas que não vieram
## da Loja — que é o caso do jogo.
const RAMO_USUARIO := "HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\webcam"
const RAMO_MAQUINA := "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\webcam"

## Programas que costumam segurar a webcam. Não dá para saber com certeza
## quem está com o dispositivo aberto sem um driver de filtro; dá para
## dizer quais dos suspeitos de sempre estão rodando agora, que é o que o
## operador precisa saber para fechar e tentar de novo.
const SUSPEITOS := [
	"WindowsCamera.exe", "Teams.exe", "ms-teams.exe", "Zoom.exe",
	"obs64.exe", "obs32.exe", "Skype.exe", "Discord.exe",
	"chrome.exe", "msedge.exe", "firefox.exe",
]

var linhas: Array[String] = []
var rodando := false
var indices: Array[int] = []
var backend := ""
var cameras_do_windows := -1
var privacidade := ""
var ocupantes := ""

var _thread: Thread = null
var _mutex := Mutex.new()
var _fila: Array[String] = []
var _fim := false
var _resolver := false
var _feeds_do_jogo := 0
var _tem_extensao := false

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	_mutex.lock()
	var novas := _fila.duplicate()
	_fila.clear()
	var acabou := _fim
	_fim = false
	_mutex.unlock()
	if not novas.is_empty():
		linhas.append_array(novas)
		while linhas.size() > 12:
			linhas.remove_at(0)
	if acabou:
		rodando = false
		if _thread != null:
			_thread.wait_to_finish()
			_thread = null
		terminou.emit()

## `resolver` libera a privacidade em vez de só relatá-la. Os dois
## argumentos seguintes existiam para apontar o caminho do `.ps1` que o
## diagnóstico desembrulhava; não há mais `.ps1`, e eles ficam só para não
## quebrar quem chama.
func diagnosticar(resolver: bool, _caminho_antigo := "", _caminho_inspetor := "") -> void:
	if rodando:
		return
	rodando = true
	linhas.clear()
	indices.clear()
	backend = ""
	cameras_do_windows = -1
	privacidade = ""
	ocupantes = ""
	_resolver = resolver
	# O QUE O JOGO VÊ TEM DE SER LIDO NA THREAD PRINCIPAL. `CameraServer`
	# é do motor, e perguntar a ele de dentro de uma thread é pedir uma
	# corrida de dados no pior lugar possível.
	_feeds_do_jogo = CameraServer.feeds().size()
	_tem_extensao = ClassDB.class_exists(&"CameraServerExtension")
	_thread = Thread.new()
	_thread.start(_trabalhar)

func _trabalhar() -> void:
	if OS.get_name() != "Windows":
		_dizer("Captura nativa ativa neste sistema.")
		_dizer("O jogo enxerga %d câmera(s)." % _feeds_do_jogo)
		_dizer("Use PROCURAR DE NOVO após conectar a câmera.")
		_terminar()
		return

	# 1) A DLL. É a primeira pergunta porque, sem ela, todo o resto é
	#    irrelevante: o Godot não tem backend de câmera no Windows.
	if not _tem_extensao:
		_dizer("PACOTE DO JOGO INCOMPLETO: BACKEND DA CÂMERA AUSENTE.")
		_dizer("Reinstale o ZIP oficial; não mova o executável sozinho.")
		_terminar()
		return

	if _resolver:
		_liberar_privacidade()

	# 2) O que o Windows enxerga.
	var achadas := _enumerar_cameras()
	cameras_do_windows = achadas
	for i in range(maxi(_feeds_do_jogo, 0)):
		indices.append(i)

	# 3) A privacidade.
	var usuario := _ler_registro(RAMO_USUARIO)
	privacidade = _ler_registro(RAMO_USUARIO + "\\NonPackaged")
	var maquina := _ler_registro(RAMO_MAQUINA)
	_dizer("Privacidade: usuário %s • programas %s • máquina %s" % [usuario, privacidade, maquina])

	# 4) Quem mais pode estar com a câmera aberta.
	ocupantes = _listar_ocupantes()
	if ocupantes != "nenhum":
		_dizer("Programas que podem estar usando a câmera: %s" % ocupantes)

	if _feeds_do_jogo > 0:
		backend = "MEDIA FOUNDATION"
		_dizer("MEDIA FOUNDATION PRONTA — o jogo enxerga %d câmera(s)." % _feeds_do_jogo)
	elif cameras_do_windows == 0:
		_dizer("WINDOWS NÃO ENCONTROU CÂMERA — CONFIRA CABO E PORTA USB.")
	else:
		_dizer("O WINDOWS VÊ A CÂMERA E O JOGO NÃO — veja privacidade e ocupantes.")
	_terminar()

## Lê um valor do registro com `reg.exe`. A saída vem em colunas
## separadas por espaços; o valor é o último campo da linha que contém
## `Value`.
func _ler_registro(caminho: String) -> String:
	var saida: Array = []
	var codigo := OS.execute("reg.exe", PackedStringArray(["query", caminho, "/v", "Value"]), saida, true)
	if codigo != 0:
		return "?"
	for bloco in saida:
		for bruta in str(bloco).split("\n"):
			var linha := str(bruta).strip_edges()
			if not linha.begins_with("Value"):
				continue
			var campos := linha.split(" ", false)
			if campos.size() >= 3:
				return str(campos[campos.size() - 1])
	return "?"

## SÓ O RAMO DO USUÁRIO. `HKLM` exigiria administrador, e um jogo que pede
## elevação para abrir a webcam é um jogo que o operador desiste de usar.
## O ramo do usuário é exatamente o mesmo valor que o aplicativo
## Configurações grava quando alguém move o interruptor à mão — nada aqui
## é escondido nem irreversível.
func _liberar_privacidade() -> void:
	for caminho in [RAMO_USUARIO, RAMO_USUARIO + "\\NonPackaged"]:
		var antes := _ler_registro(str(caminho))
		var saida: Array = []
		var codigo := OS.execute("reg.exe", PackedStringArray(
			["add", str(caminho), "/v", "Value", "/t", "REG_SZ", "/d", "Allow", "/f"]
		), saida, true)
		var ramo: String = str(caminho).get_slice("\\", str(caminho).get_slice_count("\\") - 1)
		if codigo == 0:
			_dizer("LIBEROU %s: %s → %s" % [ramo, antes, _ler_registro(str(caminho))])
		else:
			_dizer("NÃO CONSEGUI LIBERAR %s (código %d)." % [ramo, codigo])

## Quantas câmeras o WINDOWS enxerga, independentemente do jogo. É esta
## diferença — Windows vê, jogo não vê — que separa um problema de driver
## de um problema de privacidade ou de ocupante.
func _enumerar_cameras() -> int:
	var saida: Array = []
	var codigo := OS.execute("pnputil.exe", PackedStringArray(
		["/enum-devices", "/class", "Camera", "/connected"]
	), saida, true)
	if codigo != 0:
		# `pnputil /enum-devices` só existe do Windows 10 1903 em diante.
		# Sem ele, o que o jogo vê é a melhor resposta disponível — e é a
		# que importa na prática.
		_dizer("Este Windows não enumera câmeras; contando pelo próprio jogo.")
		return _feeds_do_jogo
	var achadas := 0
	for bloco in saida:
		for bruta in str(bloco).split("\n"):
			var linha := str(bruta).strip_edges()
			if linha.begins_with("Instance ID:") or linha.begins_with("ID da Inst"):
				achadas += 1
			elif linha.begins_with("Device Description:") or linha.begins_with("Descri"):
				_dizer(linha.get_slice(":", 1).strip_edges())
	return achadas

func _listar_ocupantes() -> String:
	var saida: Array = []
	if OS.execute("tasklist.exe", PackedStringArray(["/fo", "csv", "/nh"]), saida, true) != 0:
		return "nenhum"
	var texto := ""
	for bloco in saida:
		texto += str(bloco)
	var baixo := texto.to_lower()
	var abertos := PackedStringArray()
	for nome in SUSPEITOS:
		if str(nome).to_lower() in baixo:
			abertos.append(str(nome).trim_suffix(".exe"))
	return ", ".join(abertos) if not abertos.is_empty() else "nenhum"

func _veredito() -> String:
	if not _tem_extensao and OS.get_name() == "Windows":
		return "Falta a DLL da câmera: copie a pasta inteira da exportação."
	if cameras_do_windows == 0:
		return "Windows não encontrou câmera: confira cabo e porta USB."
	if privacidade.to_lower() == "deny":
		return "PRIVACIDADE bloqueada: use RESOLVER ACESSO."
	if not ocupantes.is_empty() and ocupantes != "nenhum":
		return "Feche antes: %s" % ocupantes
	if cameras_do_windows > 0:
		return "Media Foundation pronta para captura nativa."
	return "Conecte a câmera e use PROCURAR DE NOVO."

func _dizer(texto: String) -> void:
	_mutex.lock()
	_fila.append(texto)
	_mutex.unlock()

func _terminar() -> void:
	_mutex.lock()
	_fim = true
	_mutex.unlock()

func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
