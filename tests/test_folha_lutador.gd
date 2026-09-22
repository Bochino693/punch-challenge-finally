extends SceneTree

## A ARTE E O CÓDIGO CONTINUAM CONCORDANDO?
##
## A QUEIXA QUE ORIGINOU ESTE TESTE: "o pé dele está cortado". Estava, e
## de duas maneiras diferentes ao mesmo tempo:
##
##   1. A ESCALA ERA UM CHUTE. `lutador.gd` dizia que a figura ocupava
##      "cerca de 86%" dos 426 px da célula. Medindo, ocupa 99,5%. Com a
##      conta antiga o lutador saía com mais de 2 m em vez de 1,80 e
##      estourava o enquadramento — e a câmera foi afastada três vezes
##      para compensar, cada vez com um parágrafo explicando o porquê.
##   2. A RÉGUA DO CHÃO ESTAVA ERRADA, e este teste ajudou a mantê-la
##      errada. O lutador está em guarda, um pé à frente do outro; no
##      desenho o pé DE TRÁS aparece mais ALTO, por perspectiva. A
##      medida procurava a sola na METADE ESQUERDA da célula, achava o
##      pé de trás (linha 418) e chamava aquilo de chão. A bota da
##      FRENTE, oito pixels mais baixa, ficava enterrada no tapete e
##      aparecia decepada — e o teste aprovava, porque estava medindo a
##      mesma coisa errada que o código.
##
##      A régua certa: a figura encosta no chão pelo PONTO MAIS BAIXO
##      dela. As duas botas estão inteiras na arte.
##
## O que este teste garante: as constantes de `lutador.gd` batem com o
## que a folha do disco realmente tem, e nenhuma pose de pé flutua.
##
## Uso:
##     godot --headless --path . --script tests/test_folha_lutador.gd

## POSES EM QUE O LUTADOR ESTÁ DE PÉ E TEM DE ALCANÇAR A LINHA DO CHÃO.
##
## Esta lista já se chamou `POSES_COM_PE_CORTADO` e queria dizer o
## contrário: eu tinha lido "o desenho encosta na borda de baixo" como
## defeito. Não é — é ONDE FICA O CHÃO. A arte desenha a sola do pé da
## frente na última linha da célula, e uma pose de pé que NÃO alcance
## essa linha é que está errada: ela flutua.

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
	_test_nenhuma_pose_de_pe_flutua(medidas)
	_test_a_base_de_cada_pose_bate_com_a_folha(medidas)
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
	# O CONTRATO QUE FALTAVA, E QUE É O PEDIDO INTEIRO: a imagem aparece
	# COMPLETA. Nenhuma parte do quadro pode ficar abaixo do chão, senão
	# o tapete — que é desenhado na frente — corta alguma coisa.
	_ok(base_da_linha.call(Lutador3D.ALTURA_DA_FOLHA - 1.0) >= -0.0005,
		"nenhuma parte do desenho pode ficar abaixo do chão")
	l.free()

## NENHUMA POSE DE PÉ FLUTUA.
##
## Todas as poses em que o lutador está com os pés no chão têm de
## alcançar a última linha da célula, porque é ali que a arte desenhou a
## sola do pé da frente e é ali que o código põe o tapete. Uma que pare
## antes aparece no ar.
func _test_nenhuma_pose_de_pe_flutua(medidas: Dictionary) -> void:
	for nome in FolhaDoLutador.POSES_QUE_PISAM:
		_ok(medidas.has(nome), "a folha precisa da pose %s" % nome)
		if not medidas.has(nome):
			continue
		_ok("BAIXO" in (medidas[nome]["bordas"] as PackedStringArray),
			"a pose de pé %s não alcança a linha do chão: vai flutuar" % nome)
		_perto(float(medidas[nome]["base"]), Lutador3D.SOLA_DO_PE_PX, TOLERANCIA_PX,
			"a sola de %s tem de cair na linha do chão declarada" % nome)

## A BASE DECLARADA DE CADA POSE É A QUE A FOLHA TEM.
##
## `Lutador3D.BASE_DA_POSE` diz, pose por pose, qual é a linha mais
## baixa com tinta. É dela que sai a regra "nenhuma parte do desenho
## passa abaixo da lona": sem a tabela certa, o tombo do nocaute manda
## doze centímetros de desenho para debaixo do tapete, e uma pose com a
## base declarada baixa demais faz o corpo flutuar.
##
## São nove números medidos à mão uma vez. Este teste é o que impede que
## eles envelheçam em silêncio quando a arte for trocada.
func _test_a_base_de_cada_pose_bate_com_a_folha(medidas: Dictionary) -> void:
	for pose in Lutador3D.BASE_DA_POSE:
		var nome := str(pose)
		_ok(medidas.has(nome), "a folha precisa da pose %s" % nome)
		if not medidas.has(nome):
			continue
		_perto(float(medidas[nome]["base"]), float(Lutador3D.BASE_DA_POSE[pose]),
			TOLERANCIA_PX,
			"BASE_DA_POSE[%s] diz %d e a folha tem %d — rode tools/medir_folha.gd"
				% [nome, int(Lutador3D.BASE_DA_POSE[pose]), int(medidas[nome]["base"])])

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
