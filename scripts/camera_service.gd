class_name CameraService
extends Node

## Webcam nativa. No Windows, CameraServerExtension usa Media Foundation e
## entrega os quadros diretamente ao Godot: sem Python, OpenCV, processo
## auxiliar ou JPEG intermediário.
##
## ------------------------------------------------------------------
## POR QUE A CÂMERA "NÃO FUNCIONA EM OUTRAS MÁQUINAS"
##
## O FATO QUE EXPLICA TUDO: **o Godot não tem suporte de câmera no
## Windows.** Não é um detalhe de configuração — o `CameraServer` do motor
## só é implementado em Linux, macOS, Android e iOS. No Windows,
## `CameraServer.feeds()` devolve uma lista VAZIA para sempre, haja webcam
## ou não.
##
## Ou seja: no Windows a câmera deste jogo depende INTEIRAMENTE da
## extensão nativa `CameraServerExtension` (a DLL em `addons/`). Com ela,
## funciona; sem ela, não existe câmera nenhuma — nem a embutida do
## notebook, que é exatamente o caso relatado.
##
## E A DLL SE PERDE COM FACILIDADE, por três motivos, nesta ordem:
##
##   1. COPIARAM SÓ O .EXE. O `.pck` e as bibliotecas nativas são arquivos
##      separados no pacote Windows. Copiar só o EXE deixa o jogo e a DLL
##      para trás; a unidade de distribuição é sempre o ZIP completo.
##   2. FALTA O VC++ REDISTRIBUTABLE. A DLL é compilada com MSVC. Numa
##      máquina sem o *Visual C++ 2015-2022 x64*, o `LoadLibrary` falha
##      silenciosamente e o resultado é idêntico ao item 1.
##   3. WINDOWS ARM64. A extensão só traz `x86_64`. Num notebook Snapdragon
##      a DLL não carrega.
##
## O DEFEITO DE VERDADE ERA A MENSAGEM. Em todos os três casos a tela
## dizia "CONECTE UMA CÂMERA USB — BUSCANDO…", que é uma acusação falsa:
## manda procurar hardware quando o problema é software, e some com a
## única pista que resolveria em um minuto. `_diagnostico_da_plataforma`
## existe para isso — dizer qual dos três aconteceu.

const PHOTO_DIR := "user://ranking_photos"
const THUMB_SIZE := 320
const VIDA_MAXIMA_MS := 10000
const INTERVALO_AMOSTRA_MS := 500
const INTERVALO_OBTURADOR_MS := 66
const INTERVALO_NOVA_BUSCA_MS := 2500
const CONTRASTE_MINIMO := 0.04

enum Estado { DESLIGADA, SUBINDO, ACESA, EXAME, PARADA }

var enabled := true
var mirrored := true
var selected_index := 0
var estado := Estado.DESLIGADA
var status := "PROCURANDO CÂMERA"
var ultima_foto: Image = null

# Não tipar como CameraFeed: o addon documenta que o upcast desabilita
# get_formats/set_format no CameraFeedExtension.
var _feed = null
var _texture: CameraTexture = null
var _camera_extension = null
var _extension_iniciada := false
var _proxima_amostra_ms := 0
var _proxima_busca_ms := 0
var _last_frame_ms := 0
var _last_image: Image = null
var _sessao_aprovada := false
var _assinatura_do_quadro := 0
var _ultima_mudanca_ms := 0
var _ultima_quantidade_feeds := -1

var _melhor_imagem: Image = null
var _melhor_nota := -1.0
var _obturador_ate_ms := 0
var _obturador_teve_vida := false
var _obturador_foi_aberto := false

func _ready() -> void:
	_acordar_servidor()
	if not CameraServer.camera_feed_added.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feed_added.connect(_on_camera_feeds_updated)
	if not CameraServer.camera_feed_removed.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feed_removed.connect(_on_camera_feeds_updated)
	if enabled:
		iniciar_captura()
	else:
		estado = Estado.DESLIGADA
		status = "CÂMERA DESATIVADA"
	set_process(true)

func _process(_delta: float) -> void:
	if not enabled or estado in [Estado.DESLIGADA, Estado.EXAME]:
		return
	var agora := Time.get_ticks_msec()
	# Mesmo com uma câmera aberta, continua observando a lista. Assim uma
	# webcam USB conectada depois substitui automaticamente a integrada.
	var hora_de_buscar := agora >= _proxima_busca_ms
	if hora_de_buscar:
		_proxima_busca_ms = agora + INTERVALO_NOVA_BUSCA_MS
		var quantidade := CameraServer.feeds().size()
		if quantidade != _ultima_quantidade_feeds:
			_ultima_quantidade_feeds = quantidade
			_adotar_camera_usb_preferida()
	if _feed == null:
		# Só repete a descoberta enquanto não há câmera. Uma câmera aberta
		# nunca é derrubada por relógio, evitando CONECTANDO/CONECTADA.
		if hora_de_buscar:
			_descobrir_cameras(true)
		return
	if agora < _proxima_amostra_ms:
		return
	var obturador_aberto := agora <= _obturador_ate_ms
	_proxima_amostra_ms = agora + (INTERVALO_OBTURADOR_MS if obturador_aberto else INTERVALO_AMOSTRA_MS)
	_amostrar_quadro()

func iniciar_captura() -> void:
	enabled = true
	estado = Estado.SUBINDO
	status = "PROCURANDO CÂMERA USB…"
	_descobrir_cameras(false)

func _descobrir_cameras(recriar_extensao: bool) -> void:
	_acordar_servidor()
	# Primeiro aproveita qualquer feed já publicado. Isso cobre backends do
	# próprio sistema e evita recriar a extensão quando a câmera já está viva.
	if not CameraServer.feeds().is_empty():
		_abrir_feed_disponivel()
		return
	if OS.get_name() == "Windows" and ClassDB.class_exists(&"CameraServerExtension"):
		if recriar_extensao:
			_parar_feed()
			_camera_extension = null
			_extension_iniciada = false
		if not _extension_iniciada:
			_camera_extension = ClassDB.instantiate(&"CameraServerExtension")
			_extension_iniciada = _camera_extension != null
			if _camera_extension != null and _camera_extension.has_signal("permission_result"):
				var callback := Callable(self, "_on_permission_result")
				if not _camera_extension.is_connected("permission_result", callback):
					_camera_extension.connect("permission_result", callback)
			if _camera_extension != null and _camera_extension.has_method("permission_granted"):
				if not bool(_camera_extension.call("permission_granted")):
					status = "WINDOWS BLOQUEOU A CÂMERA — USE RESOLVER ACESSO"
					if _camera_extension.has_method("request_permission"):
						_camera_extension.call("request_permission")
					return
	_abrir_feed_disponivel()

## A EXTENSÃO NATIVA ESTÁ CARREGADA?
##
## `ClassDB` só conhece a classe se a DLL foi carregada de verdade — é a
## prova mais direta que existe, e não depende de procurar arquivo em
## disco nem de adivinhar caminho de instalação.
func extensao_nativa_presente() -> bool:
	return ClassDB.class_exists(&"CameraServerExtension")

## SEM CÂMERA: POR QUÊ, EM UMA FRASE QUE RESOLVE.
##
## Vazio quer dizer "é mesmo falta de câmera, procure uma". Qualquer outra
## coisa é a máquina apontando o próprio defeito.
func _diagnostico_da_plataforma() -> String:
	if OS.get_name() != "Windows":
		return ""
	if extensao_nativa_presente():
		return ""
	# Aqui está a resposta para "funciona na minha máquina e em nenhuma
	# outra": sem a extensão, o Windows não tem câmera nenhuma para o
	# Godot, nem a embutida do notebook.
	return "CÂMERA INDISPONÍVEL — RECONECTE O CABO USB"

## ESCOLHE A WEBCAM EXTERNA, NÃO A CÂMERA DO NOTEBOOK.
## Media Foundation fornece o nome amigável, mas não expõe o barramento ao
## GDScript. Os nomes abaixo cobrem as denominações usadas pelos notebooks;
## USB, marcas de webcam e dispositivos conectados depois recebem prioridade.
func _indice_camera_usb(feeds: Array) -> int:
	if feeds.is_empty():
		return -1
	var melhor := -1
	var melhor_nota := -100000
	for i in range(feeds.size()):
		var feed = feeds[i]
		var nome := str(feed.get_name()).to_lower() if feed != null and feed.has_method("get_name") else ""
		var nota := i * 10 # em empate, a conectada por último normalmente é a USB
		for termo in ["usb", "logitech", "webcam", "external", "externa", "capture"]:
			if str(termo) in nome:
				nota += 1000
		for termo in ["integrated", "integrada", "built-in", "builtin", "user facing", "front", "facetime", "ir camera"]:
			if str(termo) in nome:
				nota -= 5000
		if nota > melhor_nota:
			melhor_nota = nota
			melhor = i
	return melhor

func _adotar_camera_usb_preferida() -> void:
	if not enabled:
		return
	var feeds: Array = CameraServer.feeds()
	var preferida := _indice_camera_usb(feeds)
	if preferida < 0:
		return
	if _feed != null and selected_index == preferida:
		return
	_parar_feed()
	selected_index = preferida
	_abrir_feed_disponivel()

func _abrir_feed_disponivel() -> void:
	if not enabled or _feed != null:
		return
	var feeds: Array = CameraServer.feeds()
	if feeds.is_empty():
		estado = Estado.SUBINDO
		var motivo := _diagnostico_da_plataforma()
		status = motivo if not motivo.is_empty() else "CONECTE UMA CÂMERA USB — BUSCANDO…"
		return
	selected_index = _indice_camera_usb(feeds)
	if selected_index < 0:
		return
	_feed = feeds[selected_index]
	_selecionar_formato_estavel()
	_feed.set_active(true)
	_texture = CameraTexture.new()
	_texture.camera_feed_id = _feed.get_id()
	_texture.which_feed = CameraServer.FEED_RGBA_IMAGE
	_proxima_amostra_ms = 0
	estado = Estado.SUBINDO
	status = "ABRINDO CÂMERA USB…"

## Prefere 1280x720/30. Evitar 4K reduz USB e conversão sem sacrificar a
## miniatura quadrada de 320 px usada no ranking.
func _selecionar_formato_estavel() -> void:
	if _feed == null or not _feed.has_method("get_formats") or not _feed.has_method("set_format"):
		return
	var formatos: Array = _feed.get_formats()
	if formatos.is_empty():
		return
	var melhor := -1
	var melhor_nota := -1.0e30
	for i in range(formatos.size()):
		var formato: Dictionary = formatos[i]
		var largura := int(formato.get("width", 0))
		var altura := int(formato.get("height", 0))
		var numerador := float(formato.get("framerate_numerator", 0))
		var denominador := maxf(float(formato.get("framerate_denominator", 1)), 1.0)
		var fps := numerador / denominador
		# A EXIGÊNCIA DE 20 fps DESCARTAVA CÂMERA DE NOTEBOOK.
		#
		# Muita câmera integrada não declara taxa de quadros: devolve
		# numerador 0 e o cálculo dá zero. Com o `continue`, TODOS os
		# formatos dela eram pulados e a escolha caía no formato 0 — que
		# em várias delas é o modo mais alto e mais lento que existe.
		# Taxa desconhecida não é taxa ruim; só não é informação.
		if largura <= 0 or altura <= 0:
			continue
		if fps > 0.0 and fps < 20.0:
			continue
		var distancia := absf(float(largura - 1280)) + absf(float(altura - 720)) * 1.5
		var nota := -distancia + minf(fps, 30.0) * 20.0
		if largura > 1920 or altura > 1080:
			nota -= 10000.0
		if str(formato.get("format", "")) == "MJPG":
			nota += 250.0
		if nota > melhor_nota:
			melhor_nota = nota
			melhor = i
	_feed.set_format(0 if melhor < 0 else melhor, {})

func _amostrar_quadro() -> void:
	if _texture == null:
		return
	var imagem := _texture.get_image()
	if imagem == null or imagem.is_empty():
		return
	_registrar_quadro(imagem, Time.get_ticks_msec())
	if estado != Estado.ACESA:
		estado = Estado.ACESA
		status = "CÂMERA CONECTADA — VÍDEO AO VIVO"

func _on_permission_result(granted: bool) -> void:
	if granted:
		status = "ACESSO LIBERADO — PROCURANDO CÂMERA…"
		procurar_de_novo()
	else:
		estado = Estado.PARADA
		status = "ACESSO À CÂMERA NEGADO PELO WINDOWS"

func _on_camera_feeds_updated(_id: int = 0) -> void:
	if enabled:
		call_deferred("_adotar_camera_usb_preferida")

func _acordar_servidor() -> void:
	if CameraServer.has_method("set_monitoring_feeds"):
		CameraServer.call("set_monitoring_feeds", true)

func set_enabled(value: bool) -> void:
	if value:
		if enabled and _feed != null:
			return
		iniciar_captura()
	else:
		enabled = false
		_parar_feed()
		_sessao_aprovada = false
		estado = Estado.DESLIGADA
		status = "CÂMERA DESATIVADA"

func cycle_camera() -> void:
	var total := CameraServer.feeds().size()
	selected_index = (selected_index + 1) % maxi(total, 1)
	_parar_feed()
	_sessao_aprovada = false
	estado = Estado.SUBINDO
	_abrir_feed_disponivel()

func procurar_de_novo() -> void:
	_parar_feed()
	_sessao_aprovada = false
	estado = Estado.SUBINDO
	status = "PROCURANDO CÂMERA USB…"
	_descobrir_cameras(true)

func entregar_ao_exame() -> void:
	# O PowerShell consulta PnP/privacidade; não abre o vídeo.
	pass

func terminar_exame() -> void:
	if enabled and _feed == null:
		procurar_de_novo()

func pedir_abertura() -> void:
	set_enabled(true)

func pedir_fechamento() -> void:
	set_enabled(false)

func pedir_exame() -> void:
	entregar_ao_exame()

func pronta() -> bool:
	return enabled and _sessao_aprovada and estado == Estado.ACESA and ao_vivo()

func estado_curto() -> String:
	return status

func preview_texture() -> Texture2D:
	return _texture

func available() -> bool:
	return pronta() and ao_vivo()

func tem_imagem() -> bool:
	return enabled and _texture != null and _sessao_aprovada

func ao_vivo() -> bool:
	return enabled and _last_frame_ms > 0 and Time.get_ticks_msec() - _last_frame_ms <= VIDA_MAXIMA_MS

func motivo_curto() -> String:
	if not enabled:
		return "CÂMERA DESLIGADA NA CENTRAL"
	if estado == Estado.PARADA:
		return status
	if _feed == null:
		return "NENHUMA CÂMERA USB ENCONTRADA"
	if not _sessao_aprovada:
		return "AGUARDANDO O PRIMEIRO QUADRO"
	return status

func ficha_da_ponte() -> String:
	if _feed == null:
		return "CAPTURA NATIVA — AGUARDANDO DISPOSITIVO"
	var nome := str(_feed.get_name()) if _feed.has_method("get_name") else "CÂMERA USB"
	return "%s • MEDIA FOUNDATION" % nome if OS.get_name() == "Windows" else "%s • CAPTURA NATIVA" % nome

## NÃO HÁ MAIS INSPETOR PARA DESEMBRULHAR.
##
## O diagnóstico da câmera desembrulhava um `.ps1` do pacote para o
## AppData só para poder chamar o PowerShell em cima dele. Hoje ele
## pergunta a mesma coisa ao `reg.exe`, ao `tasklist.exe` e ao
## `pnputil.exe`, que já estão no Windows e não precisam de arquivo
## nenhum (ver `CameraDoctor`). Esta função continua existindo, devolvendo
## vazio, porque quem chama o diagnóstico ainda a passa adiante.
func caminho_do_inspetor() -> String:
	return ""

func idade_do_quadro() -> int:
	return 999999 if _last_frame_ms <= 0 else Time.get_ticks_msec() - _last_frame_ms

func parada_ha() -> int:
	return 999999 if _ultima_mudanca_ms <= 0 else Time.get_ticks_msec() - _ultima_mudanca_ms

func abrir_obturador(janela_ms := 3200) -> void:
	_melhor_imagem = null
	_melhor_nota = -1.0
	_obturador_teve_vida = false
	_obturador_foi_aberto = true
	_obturador_ate_ms = Time.get_ticks_msec() + janela_ms
	_proxima_amostra_ms = 0

func _imagem_util(imagem: Image) -> bool:
	return _nota_da_imagem(imagem) >= CONTRASTE_MINIMO

func _nota_da_imagem(imagem: Image) -> float:
	return float(_medir_quadro(imagem)["nota"])

func _medir_quadro(imagem: Image) -> Dictionary:
	if imagem == null or imagem.is_empty() or imagem.get_width() < 8 or imagem.get_height() < 8:
		return {"nota": -1.0, "assinatura": 0}
	var claro := 0.0
	var escuro := 1.0
	var assinatura := 0
	for gx in range(8):
		for gy in range(6):
			var x := int((float(gx) + 0.5) / 8.0 * float(imagem.get_width()))
			var y := int((float(gy) + 0.5) / 6.0 * float(imagem.get_height()))
			var v := imagem.get_pixel(x, y).get_luminance()
			claro = maxf(claro, v)
			escuro = minf(escuro, v)
			assinatura = (assinatura * 31 + int(v * 255.0)) & 0x3FFFFFFF
	return {"nota": claro - escuro, "assinatura": assinatura}

func _registrar_quadro(imagem: Image, agora: int) -> void:
	if imagem == null or imagem.is_empty():
		return
	var medida := _medir_quadro(imagem)
	var assinatura := int(medida["assinatura"])
	if assinatura != _assinatura_do_quadro:
		_assinatura_do_quadro = assinatura
		_ultima_mudanca_ms = agora
		if agora <= _obturador_ate_ms:
			_obturador_teve_vida = true
	_last_image = imagem
	_last_frame_ms = agora
	_sessao_aprovada = true
	_oferecer_ao_obturador(imagem, float(medida["nota"]))

func _oferecer_ao_obturador(imagem: Image, nota_pronta := NAN) -> void:
	if imagem == null or Time.get_ticks_msec() > _obturador_ate_ms:
		return
	var nota := nota_pronta if not is_nan(nota_pronta) else _nota_da_imagem(imagem)
	if nota > _melhor_nota:
		_melhor_nota = nota
		_melhor_imagem = imagem.duplicate()

func capture_photo() -> String:
	var image: Image = null
	var captura_da_pose := _obturador_foi_aberto
	_obturador_foi_aberto = false
	_obturador_ate_ms = 0
	if _melhor_imagem != null and _obturador_teve_vida and _melhor_nota > 0.0:
		image = _melhor_imagem
	elif not captura_da_pose and _texture != null:
		image = _texture.get_image()
	_melhor_imagem = null
	_melhor_nota = -1.0
	_obturador_teve_vida = false
	if image == null or image.is_empty():
		status = "CÂMERA SEM IMAGEM — %s" % motivo_curto()
		return ""
	if _nota_da_imagem(image) <= 0.0:
		status = "IMAGEM CHAPADA — TAMPA NA LENTE"
		return ""
	ultima_foto = image
	var path := "%s/player_%d.jpg" % [PHOTO_DIR, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PHOTO_DIR))
	# A opcao de espelho vale somente para a PREVIA, como um espelho de
	# academia. A foto salva preserva a orientacao real da camera; aplicar
	# flip_x aqui fazia a imagem mudar de lado depois do clique.
	WorkerThreadPool.add_task(_gravar_thumb_em_segundo_plano.bind(image.duplicate(), path))
	status = "FOTO OK — VÍDEO CONTINUA AO VIVO"
	return path

func _gravar_thumb_em_segundo_plano(imagem: Image, path: String) -> void:
	var side := mini(imagem.get_width(), imagem.get_height())
	if side <= 0:
		return
	var origin := Vector2i((imagem.get_width() - side) / 2, (imagem.get_height() - side) / 2)
	var recorte := imagem.get_region(Rect2i(origin, Vector2i(side, side)))
	recorte.resize(THUMB_SIZE, THUMB_SIZE, Image.INTERPOLATE_LANCZOS)
	recorte.save_jpg(path, 0.86)

func _parar_feed() -> void:
	if _feed != null:
		_feed.set_active(false)
	_feed = null
	_texture = null
	_last_image = null
	_last_frame_ms = 0

func _exit_tree() -> void:
	_parar_feed()
	_camera_extension = null
