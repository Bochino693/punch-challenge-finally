extends SceneTree

## A CENTRAL TEM DE SER LEGÍVEL — e isso é mensurável.
##
## "Nenhum texto tapa o outro" não é uma regra que se cumpre olhando.
## São cinco páginas, dezenas de rótulos, e basta acrescentar uma linha
## para empurrar outra por baixo de um cartão. Já aconteceu duas vezes
## neste projeto, e nas duas o defeito só apareceu numa foto da tela —
## depois de o gabinete estar montado.
##
## E a conferência desce a página inteira, rolando: o pé de uma página
## longa é onde mora o diagnóstico, que é o que alguém lê ao telefone às
## onze da noite.
##
## Aqui cada texto desenhado registra o retângulo que ocupa de fato
## (ver `main.gd`, `_anotar_texto`), e o teste percorre as páginas
## procurando cruzamento. É a única forma de a regra continuar valendo
## depois que eu sair de perto.

## FOLGA, EM PIXELS. Duas letras que se encostam por um pixel são
## arredondamento de fonte, não defeito. Quatro pixels de invasão já são
## visíveis numa tela de 1080 vista de pé.
const FOLGA := 4.0

## O MENOR CORPO ACEITÁVEL. Abaixo disto a Saira Condensed deixa de
## separar o "0" do "O" a um metro e meio — que é a distância de quem
## está mexendo na Central com o gabinete em pé.
const CORPO_MINIMO := 20

var jogo: Control
var falhas := 0

func _ok(condicao: bool, o_que: String) -> void:
	if not condicao:
		falhas += 1
		print("FALHOU: %s" % o_que)

func _initialize() -> void:
	call_deferred("run")

func quadro() -> void:
	jogo.queue_redraw()
	await process_frame
	await process_frame

func run() -> void:
	jogo = load("res://scenes/main.tscn").instantiate()
	root.add_child(jogo)
	await process_frame
	jogo.set_process(false)
	jogo.central_aberta = true
	jogo.calib_ativo = false
	jogo.transicao = -1.0

	# A PÁGINA É CONFERIDA ROLANDO, e não só no topo.
	#
	# A auditoria só anota o que está DENTRO da janela que rola: o
	# cabeçalho e o rodapé da Central são repintados opacos por cima do
	# miolo, e acusar uma linha que eles cobrem seria apontar um defeito
	# que ninguém vê. O preço disso é que conferir uma vez, parado no
	# topo, deixaria de fora tudo o que mora no pé de uma página longa —
	# que é justamente onde o diagnóstico fica.
	#
	# Meia janela por vez garante que toda linha apareça inteira em pelo
	# menos uma das passagens.
	for pagina in range(jogo.PAGINAS.size()):
		jogo.central_pagina = pagina
		var rolagem := 0.0
		var voltas := 0
		while voltas < 24:
			jogo.central_rolagem = rolagem
			# `clear()`, E NÃO `= []`. Atribuir um array destipado a uma
			# propriedade `Array[Dictionary]` de outro script TRAVA o
			# motor aqui — o processo fica vivo e o quadro nunca mais
			# acontece. Custou meia hora para achar, e o sintoma não
			# aponta para a causa em lugar nenhum.
			jogo.auditoria.clear()
			jogo.auditoria_de_layout = true
			await quadro()
			jogo.auditoria_de_layout = false
			var anotados: Array = jogo.auditoria.duplicate()
			if rolagem == 0.0:
				_ok(anotados.size() > 4,
					"a página %s tem de desenhar texto (anotou %d)"
						% [jogo.PAGINAS[pagina], anotados.size()])
			var onde := "%s" % jogo.PAGINAS[pagina]
			if rolagem > 0.0:
				onde += " (rolada %d px)" % int(rolagem)
			_conferir_corpo(onde, anotados)
			_conferir_cruzamento(onde, anotados)
			var maxima: float = jogo._rolagem_maxima()
			if rolagem >= maxima:
				break
			rolagem = minf(rolagem + jogo.CENTRAL_JANELA * 0.5, maxima)
			voltas += 1
		jogo.central_rolagem = 0.0

	if falhas == 0:
		print("CENTRAL_LEGIVEL_OK")
	quit(1 if falhas > 0 else 0)

## NINGUÉM ESCREVE MIÚDO. O piso existe no código (`CORPO_MINIMO` em
## `main.gd`), mas um piso só vale se alguém conferir que ele está sendo
## aplicado em toda chamada — e são dezenas.
func _conferir_corpo(pagina: String, anotados: Array) -> void:
	for item in anotados:
		var corpo := int(item["corpo"])
		if corpo < CORPO_MINIMO:
			_ok(false, "%s: \"%s\" desenhado com corpo %d, abaixo do piso %d"
				% [pagina, item["texto"], corpo, CORPO_MINIMO])
			return

## E NINGUÉM TAPA NINGUÉM.
##
## A conferência é entre pares. Com algumas dezenas de textos por página
## isso é um punhado de comparações — barato o bastante para rodar em
## toda bateria, que é o que faz a regra continuar valendo.
func _conferir_cruzamento(pagina: String, anotados: Array) -> void:
	var achados := 0
	for i in range(anotados.size()):
		for j in range(i + 1, anotados.size()):
			var a: Rect2 = anotados[i]["rect"]
			var b: Rect2 = anotados[j]["rect"]
			var cruzamento := a.intersection(b)
			if cruzamento.size.x <= FOLGA or cruzamento.size.y <= FOLGA:
				continue
			_ok(false, "%s: \"%s\" e \"%s\" se cruzam em %.0f × %.0f px"
				% [pagina, anotados[i]["texto"], anotados[j]["texto"],
					cruzamento.size.x, cruzamento.size.y])
			achados += 1
			# RELATA ATÉ CINCO POR PÁGINA. Parar no primeiro faria o
			# conserto virar uma fila de rodadas de uma em uma; relatar
			# tudo encheria a tela com o mesmo texto cruzando com cinco
			# vizinhos. Cinco é o que cabe numa leitura.
			if achados >= 5:
				return
