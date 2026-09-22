extends SceneTree

## A ARTE E O CÓDIGO CONTINUAM CONCORDANDO?
##
## A QUEIXA QUE ORIGINOU ESTE TESTE: "o pé dele está cortado". Estava, e
## de duas maneiras diferentes ao mesmo tempo:
##
##   1. A ESCALA ERA UM CHUTE. `lutador.gd` dizia que a figura ocupava
##      "cerca de 86%" dos 426 px da célula. Medindo, ocupa 97,9%. Com a
##      conta antiga o lutador saía com 2,03 m em vez de 1,80 e
##      estourava o enquadramento — e a câmera foi afastada três vezes
##      para compensar, cada vez com um parágrafo explicando o porquê.
##   2. A FOLHA ESTÁ MESMO CORTADA. Em seis das nove poses o desenho
##      encosta na borda de baixo da célula: a perna de trás termina na
##      última linha, sem pé. Isso é defeito de ARTE — nenhuma conta
##      conserta — e por isso está DECLARADO aqui embaixo, com nome e
##      sobrenome, em vez de virar surpresa.
##
## O que este teste garante: as constantes de `lutador.gd` batem com o
## que a folha do disco realmente tem, e nenhuma pose NOVA passou a ser
## cortada sem alguém ficar sabendo.
##
## Uso:
##     godot --headless --path . --script tests/test_folha_lutador.gd

## AS POSES QUE JÁ CHEGAM CORTADAS NA BORDA DE BAIXO. Não é uma lista de
## permissões: é a dívida de arte, escrita por extenso. Quando a folha
## for reexportada com a figura inteira dentro da célula, o teste avisa
## que a lista pode encolher.
const POSES_COM_PE_CORTADO := [
	"guarda", "idle", "preparado", "jab", "direto", "impacto_corpo",
]

## Quanta diferença se aceita entre o medido e o declarado, em pixels.
## Dois: o limiar de alfa pode mexer uma linha para cada lado quando a
## arte é reexportada com outro antisserrilhado.
const TOLERANCIA_PX := 2

var _falhas := 0

func _init() -> void:
	var medidas := FolhaDoLutador.medir(Lutador3D.FOLHA)
	_ok(not medidas.is_empty(),
		"a folha %s precisa ser legível — abra o projeto no editor uma vez para importar" % Lutador3D.FOLHA)
	if medidas.is_empty():
		_terminar()
		return

	_test_todas_as_poses_tem_desenho(medidas)
	_test_a_escala_declarada_bate_com_a_folha(medidas)
	_test_o_lutador_mede_o_que_promete()
	_test_nenhuma_pose_nova_ficou_cortada(medidas)
	_terminar()

## Uma pose em branco na folha vira um lutador que some no meio de uma
## reação — e some sem erro nenhum no console.
func _test_todas_as_poses_tem_desenho(medidas: Dictionary) -> void:
	for nome in medidas:
		_ok(not bool(medidas[nome]["vazia"]),
			"a pose %s não tem desenho nenhum na folha" % nome)

## O CONTRATO PRINCIPAL: o topo da cabeça e a sola do pé da frente que
## `lutador.gd` declara são os que a folha tem. É deste par que sai o
## tamanho do pixel no mundo e a altura em que o sprite é pendurado.
func _test_a_escala_declarada_bate_com_a_folha(medidas: Dictionary) -> void:
	var topo := 1 << 30
	var sola := -1
	for nome in FolhaDoLutador.POSES_EM_PE:
		_ok(medidas.has(nome), "a folha precisa da pose em pé %s" % nome)
		if not medidas.has(nome):
			continue
		topo = mini(topo, int(medidas[nome]["topo"]))
		sola = maxi(sola, int(medidas[nome]["sola"]))
	if topo == 1 << 30 or sola < 0:
		return
	_perto(float(topo), Lutador3D.TOPO_DA_CABECA_PX, TOLERANCIA_PX,
		"TOPO_DA_CABECA_PX diz %d e a folha tem %d — rode tools/medir_folha.gd"
			% [int(Lutador3D.TOPO_DA_CABECA_PX), topo])
	_perto(float(sola), Lutador3D.SOLA_DO_PE_PX, TOLERANCIA_PX,
		"SOLA_DO_PE_PX diz %d e a folha tem %d — rode tools/medir_folha.gd"
			% [int(Lutador3D.SOLA_DO_PE_PX), sola])

## E O LUTADOR MONTADO MEDE MESMO 1,80 m.
##
## Este é o teste que faltava quando o erro de escala passou: as
## constantes podiam estar erradas juntas e nada reclamava. Aqui a
## medida vai do topo da cabeça à sola, em metros, pelo caminho que o
## jogo de fato usa — `pixel_size` vezes os pixels da figura.
func _test_o_lutador_mede_o_que_promete() -> void:
	var l := Lutador3D.new()
	l.montar()
	var figura := l.get_node_or_null("Corpo/Figura") as AnimatedSprite3D
	_ok(figura != null, "o desenho tem de estar montado")
	if figura == null:
		l.free()
		return
	# TUDO DAQUI PARA BAIXO SAI DO NÓ MONTADO, e não das constantes: é a
	# única forma de o teste pegar um `montar` que pendure o sprite na
	# altura errada apesar de as constantes estarem certas.
	var meio := Lutador3D.ALTURA_DA_FOLHA * 0.5
	# UMA LINHA DA FOLHA OCUPA UM INTERVALO, E NÃO UM PONTO.
	#
	# Num sprite centrado, a linha `r` vai de `v = r` (borda de cima) a
	# `v = r + 1` (borda de baixo). Este teste já mediu a "altura da
	# linha 418" e passou enquanto a borda de baixo dessa mesma linha
	# ficava meio pixel dentro do tapete — que era o corte reto no meio
	# da bota. Agora as duas bordas têm nome.
	var topo_da_linha := func(px: float) -> float:
		return figura.position.y + figura.pixel_size * (meio - px)
	var base_da_linha := func(px: float) -> float:
		return figura.position.y + figura.pixel_size * (meio - px - 1.0)

	_perto(
		topo_da_linha.call(Lutador3D.TOPO_DA_CABECA_PX)
			- base_da_linha.call(Lutador3D.SOLA_DO_PE_PX),
		Lutador3D.ALTURA_DA_FIGURA, 0.002,
		"do topo da cabeça à sola o lutador tem de medir ALTURA_DA_FIGURA")
	_perto(base_da_linha.call(Lutador3D.SOLA_DO_PE_PX), 0.0, 0.0005,
		"a BORDA DE BAIXO da última linha da bota tem de pousar em y = 0")
	# E nenhuma tinta pode sobrar abaixo disso: se a última linha com
	# tinta ficasse a cavaleiro do zero, o tapete a cortaria ao meio.
	_ok(topo_da_linha.call(Lutador3D.SOLA_DO_PE_PX) > 0.0,
		"a última linha com tinta tem de ficar inteira acima do chão")
	# E a borda de baixo do quadro — onde a perna cortada termina — tem
	# de ficar ABAIXO do chão, senão o corte aparece no ar em vez de
	# sumir dentro do tapete.
	_ok(base_da_linha.call(Lutador3D.ALTURA_DA_FOLHA - 1.0) < 0.0,
		"a borda de baixo do quadro tem de afundar na lona para o corte não aparecer")
	l.free()

## NINGUÉM MAIS FICOU CORTADO SEM AVISAR.
##
## Uma pose cortada que NÃO está na lista é regressão e reprova. Uma
## pose da lista que deixou de estar cortada é boa notícia: o teste
## passa e pede que a lista encolha.
func _test_nenhuma_pose_nova_ficou_cortada(medidas: Dictionary) -> void:
	var cortadas := PackedStringArray()
	for nome in medidas:
		if "BAIXO" in (medidas[nome]["bordas"] as PackedStringArray):
			cortadas.append(str(nome))
	for nome in cortadas:
		_ok(nome in POSES_COM_PE_CORTADO,
			"a pose %s passou a encostar na borda de baixo: o pé dela foi cortado" % nome)
	for nome in POSES_COM_PE_CORTADO:
		if not (str(nome) in cortadas):
			print("BOA NOTÍCIA: %s não está mais cortada — tire-a de POSES_COM_PE_CORTADO." % nome)

# -------------------------------------------------------------- utilidades
func _ok(condicao: bool, mensagem: String) -> void:
	if condicao:
		return
	_falhas += 1
	push_error("FALHA: " + mensagem)
	printerr("FALHA: " + mensagem)

func _perto(valor: float, alvo: float, folga: float, mensagem: String) -> void:
	_ok(absf(valor - alvo) <= folga,
		"%s (medido %.4f, esperado %.4f ± %.4f)" % [mensagem, valor, alvo, folga])

func _terminar() -> void:
	if _falhas > 0:
		printerr("FOLHA_COM_DEFEITO: %d falha(s)" % _falhas)
		quit(1)
		return
	print("FOLHA_OK: a arte e as constantes de lutador.gd concordam")
	quit(0)
