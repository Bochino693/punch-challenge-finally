extends SceneTree

## A ARENA SOB TESTE.
##
## Tudo aqui nasceu de um erro que a tela de verdade cometeu e que
## nenhum teste antigo pegaria — porque nenhum teste antigo sabia que
## existia um mundo 3D. Os dois piores:
##
##   • o nocaute AFUNDAVA o lutador. A queda baixava o corpo 62 cm além
##     de tombá-lo, e como o nó raiz já fica na altura da lona, o boneco
##     saía por baixo do ringue: a moldura mostrava um ringue vazio no
##     momento mais importante do jogo.
##   • a janela 3D e o buraco da moldura tinham proporções diferentes, e
##     a imagem chegava esticada na tela — o tipo de coisa que ninguém vê
##     olhando o código e que salta aos olhos na máquina.
##
## Os dois viraram teste. Os demais guardam as regras que a arena promete
## ao resto do jogo: dano que só sobe dentro da rodada, frase que não
## troca sozinha, som que existe de verdade no disco.



var falhas := 0

func _ok(condicao: bool, o_que: String) -> void:
	if not condicao:
		falhas += 1
		print("FALHOU: %s" % o_que)

func _perto(a: float, b: float, folga: float, o_que: String) -> void:
	_ok(absf(a - b) <= folga, "%s (%.4f vs %.4f)" % [o_que, a, b])

func _initialize() -> void:
	_test_o_lutador_nasce_completo()
	_test_a_folha_de_sprites_existe_com_as_nove_poses()
	_test_o_lutador_tem_tamanho_de_gente()
	_test_a_janela_tem_a_proporcao_do_buraco()
	_test_as_barras_cabem_na_moldura()
	_test_a_postura_parada_se_mexe()
	_test_a_reacao_cresce_com_a_forca()
	_test_o_dano_soma_e_nao_passa_de_um()
	_test_cada_forca_tem_reacao_propria()
	_test_desdenho_usa_a_nota_e_respeita_a_lona()
	_test_o_nocaute_derruba_de_verdade()
	_test_o_nocaute_nao_afunda_o_lutador()
	_test_levantar_devolve_o_lutador_para_cima_da_lona()
	_test_preparar_desfaz_a_pose_do_tombo()
	_test_as_frases_cobrem_todos_os_niveis()
	_test_a_frase_nao_troca_sozinha()
	_test_os_sons_da_arena_existem()
	_test_a_arena_so_liga_nas_telas_do_soco()
	if falhas == 0:
		print("ARENA_OK")
	quit(1 if falhas > 0 else 0)

# ------------------------------------------------------------- o lutador
## O LUTADOR NASCE INTEIRO, E AGORA ELE É DESENHO.
##
## O corpo procedural — anéis torneados, músculo modelado, sombreador de
## desenho — saiu. Ele funcionava e custava onze chamadas de desenho, mas
## geometria feita de elipsoides somados tem um teto de qualidade, e esse
## teto fica bem abaixo de uma ilustração. No lugar entrou uma folha de
## nove poses desenhadas.
##
## O contrato mudou de forma e não de fundo: continuam sendo nove papéis,
## e cada um precisa achar o seu desenho na folha. Um papel sem desenho é
## um lutador que congela no meio de uma reação.
func _test_o_lutador_nasce_completo() -> void:
	var controle := _lutador()
	var animacoes := controle.animacoes_disponiveis()
	for nome in Lutador3D.ALIASES:
		_ok(nome in animacoes, "o lutador precisa do papel %s" % nome)
	_ok(controle.completo(), "os nove papéis têm de achar desenho na folha")
	controle.free()

## A FOLHA TEM DE ESTAR NO DISCO, e com os nove recortes.
##
## Ela é o personagem inteiro agora: sem ela não há adversário nenhum, e
## o modo de falhar é silencioso — um `AnimatedSprite3D` sem quadros
## simplesmente não desenha nada, e a arena fica sendo um ringue vazio
## com as luzes acesas.
func _test_a_folha_de_sprites_existe_com_as_nove_poses() -> void:
	_ok(ResourceLoader.exists(Lutador3D.FOLHA), "a folha de poses tem de estar no disco")
	if not ResourceLoader.exists(Lutador3D.FOLHA):
		return
	var folha := load(Lutador3D.FOLHA) as SpriteFrames
	_ok(folha != null, "a folha tem de abrir como SpriteFrames")
	if folha == null:
		return
	for pose in ["guarda", "idle", "preparado", "jab", "direto",
			"impacto_corpo", "impacto_forte", "nocaute", "recuperacao"]:
		_ok(folha.has_animation(StringName(pose)), "falta a pose %s na folha" % pose)
		if folha.has_animation(StringName(pose)):
			_ok(folha.get_frame_texture(StringName(pose), 0) != null,
				"a pose %s existe mas não tem desenho" % pose)

## O LUTADOR CABE NO RINGUE, em metros.
##
## A folha não sabe de metros: ela tem 426 pixels de altura por pose, e é
## `pixel_size` que decide se aquilo vira um lutador de 1,80 m ou um
## gigante de três metros que estoura o quadro. Foi o que aconteceu na
## primeira montagem, e é um erro que não aparece em teste nenhum que
## olhe só para o código.
func _test_o_lutador_tem_tamanho_de_gente() -> void:
	var l := _lutador()
	var figura := l.get_node_or_null("Corpo/Figura") as AnimatedSprite3D
	_ok(figura != null, "o desenho tem de estar montado")
	if figura == null:
		l.free()
		return
	var alto := Lutador3D.ALTURA_DO_QUADRO
	_ok(alto > 1.7 and alto < 2.6, "o quadro do desenho mede %.2f m — fora de escala" % alto)
	_perto(figura.pixel_size * Lutador3D.ALTURA_DA_FOLHA, alto, 0.001,
		"o tamanho do pixel tem de sair da altura pedida")
	# E UMA SÓ CHAMADA DE DESENHO. O corpo anterior custava onze; este
	# custa um, que é o piso do possível — importa numa TV Box.
	_ok(figura is AnimatedSprite3D, "o lutador é um desenho só, e não uma coleção de malhas")
	l.free()


# -------------------------------------------------------------- moldura
func _test_a_janela_tem_a_proporcao_do_buraco() -> void:
	var buraco := ArenaQuadro.TELA.size.x / ArenaQuadro.TELA.size.y
	for tamanho in [Arena3D.TAMANHO_CHEIO, Arena3D.TAMANHO_MAGRO]:
		var janela := float(tamanho.x) / float(tamanho.y)
		_perto(janela, buraco, 0.01, "a janela 3D %s tem de ter a proporção do buraco da moldura" % tamanho)

func _test_as_barras_cabem_na_moldura() -> void:
	# As colunas ficam FORA da moldura e DENTRO da tela. Encostar numa
	# coisa ou sair da outra é o tipo de deslize que só aparece quando o
	# gabinete já está montado.
	_ok(ArenaQuadro.BARRA_E.end.x < ArenaQuadro.MOLDURA.position.x, "a coluna esquerda não pode invadir a moldura")
	_ok(ArenaQuadro.BARRA_D.position.x > ArenaQuadro.MOLDURA.end.x, "a coluna direita não pode invadir a moldura")
	_ok(ArenaQuadro.BARRA_E.position.x > 0.0, "a coluna esquerda não pode sair da tela")
	_ok(ArenaQuadro.BARRA_D.end.x < 1080.0, "a coluna direita não pode sair da tela")
	# E o buraco tem de estar inteiro dentro da moldura, senão a imagem
	# vaza por cima da borda.
	_ok(ArenaQuadro.MOLDURA.encloses(ArenaQuadro.TELA), "o buraco tem de caber na moldura")

# ------------------------------------------------------------- o corpo
func _lutador() -> Lutador3D:
	var l := Lutador3D.new()
	l.montar()
	l.preparar()
	return l

## O RELÓGIO DO LUTADOR É O DO JOGO, e mais nada.
##
## Enquanto o corpo era animado por um `AnimationPlayer`, um teste
## precisava empurrar o tocador à mão porque ele só anda sozinho dentro
## da árvore da cena. Com poses desenhadas não há tocador: todo o
## movimento — troca de quadro, recuo, tombo — sai de `atualizar`, e
## chamar `atualizar` É rodar o lutador.
func _correr(l: Lutador3D, quadros: int) -> void:
	for i in range(quadros):
		l.atualizar(1.0 / 60.0)

## A POSTURA PARADA TEM DE SE MEXER, E NÃO CONGELAR.
##
## É a mesma promessa de sempre, com o defeito ao contrário. Com
## animações, o perigo era `idle` acabar e recomeçar com um solavanco a
## cada ciclo. Com poses DESENHADAS, o perigo é não acontecer nada: um
## desenho parado é um cartaz, e o jogador percebe isso no primeiro
## segundo da tela em que ele mais olha para o adversário.
##
## Duas coisas guardam isso: os papéis contínuos alternam entre dois
## desenhos, e o corpo respira o tempo todo.
func _test_a_postura_parada_se_mexe() -> void:
	for papel in Lutador3D.PAPEIS_CONTINUOS:
		var receita: Dictionary = Lutador3D.PAPEIS[papel]
		_ok((receita["quadros"] as Array).size() >= 2,
			"a postura %s precisa de mais de um desenho para não congelar" % papel)
	var l := _lutador()
	var corpo := l.get_node_or_null("Corpo") as Node3D
	_ok(corpo != null, "o corpo tem de existir")
	if corpo == null:
		l.free()
		return
	var visto := {}
	var alturas := []
	var figura := l.get_node_or_null("Corpo/Figura") as AnimatedSprite3D
	for i in range(140):
		l.atualizar(1.0 / 60.0)
		visto[String(figura.animation)] = true
		alturas.append(corpo.position.y)
	_ok(visto.size() >= 2, "parado, o lutador tem de trocar de desenho (viu %d)" % visto.size())
	var menor: float = alturas[0]
	var maior: float = alturas[0]
	for a in alturas:
		menor = minf(menor, float(a))
		maior = maxf(maior, float(a))
	_ok(maior - menor > 0.01, "ele tem de respirar (balançou %.3f m)" % (maior - menor))
	l.free()

## CADA REAÇÃO DURA O QUE A DIREÇÃO MANDA, e a escada entre elas é o que
## faz a nota na tela e o corpo contarem a mesma história.
##
## Com animações de verdade a duração saía do comprimento delas — uma
## tabela à mão não teria como acompanhar. Com poses desenhadas não há
## comprimento a medir: a duração É a decisão, e o que um teste pode
## guardar é que ela CRESCE com a força do golpe. Um soco de 9.000 que
## acabasse antes de um de 3.000 seria um adversário que desmente o
## placar.
func _test_a_reacao_cresce_com_a_forca() -> void:
	var escada := ["hit_light", "hit_medium", "hit_heavy", "stagger"]
	for i in range(escada.size() - 1):
		var antes := float(Lutador3D.DURACAO[escada[i]])
		var depois := float(Lutador3D.DURACAO[escada[i + 1]])
		_ok(depois > antes, "%s tem de durar mais que %s" % [escada[i + 1], escada[i]])
		var recuo_antes := float(Lutador3D.RECUO[escada[i]]["tras"])
		var recuo_depois := float(Lutador3D.RECUO[escada[i + 1]]["tras"])
		_ok(recuo_depois > recuo_antes,
			"%s tem de empurrar mais que %s" % [escada[i + 1], escada[i]])
	# E O RECUO ACONTECE DE VERDADE no corpo, não só na tabela.
	var l := _lutador()
	var corpo := l.get_node_or_null("Corpo") as Node3D
	l.bater(0.70, false, 8000)
	_correr(l, 6)
	_ok(corpo.position.z < -0.05,
		"o golpe tem de empurrar o corpo para trás (z=%.3f)" % corpo.position.z)
	_correr(l, 120)
	_perto(corpo.position.z, 0.0, 0.02, "e ele tem de voltar sozinho")
	l.free()

func _test_o_dano_soma_e_nao_passa_de_um() -> void:
	var l := _lutador()
	_ok(l.dano == 0.0, "o lutador começa a rodada inteiro")
	l.bater(0.30)
	var depois_de_um := l.dano
	_ok(depois_de_um > 0.0, "um soco de verdade tem de marcar o adversário")
	l.bater(0.30)
	_ok(l.dano > depois_de_um, "o segundo soco soma em cima do primeiro")
	for i in range(10):
		l.bater(1.0)
	_ok(l.dano <= 1.0, "o medidor de dano não pode passar de 100%")
	# Um tapa não conta: sem este piso, o ruído do sensor encheria a barra
	# sozinho ao longo de uma noite.
	l.preparar()
	l.bater(0.005)
	_ok(l.dano == 0.0, "golpe abaixo do mínimo não marca dano")
	l.free()

func _test_cada_forca_tem_reacao_propria() -> void:
	var casos := {
		0.05: "taunt_weak", 0.20: "hit_light", 0.45: "hit_medium",
		0.68: "hit_heavy", 0.90: "stagger",
	}
	for forca in casos:
		_ok(Lutador3D.reacao_para_forca(forca) == casos[forca],
			"força %.2f precisa tocar %s" % [forca, casos[forca]])

func _test_desdenho_usa_a_nota_e_respeita_a_lona() -> void:
	_ok(Lutador3D.reacao_para_pontos(5999, 0.72) == "taunt_weak",
		"abaixo de 6.000 o adversário precisa desdenhar mesmo com força física")
	_ok(Lutador3D.reacao_para_pontos(6000, 0.72) == "hit_heavy",
		"6.000 já usa a reação física normal")
	_ok(Lutador3D.reacao_para_pontos(6000, 0.02) == "hit_light",
		"a partir de 6.000 o adversário não pode desdenhar")
	var l := _lutador()
	var ko := l.bater(1.0, true, 9500)
	_ok(bool(ko["nocaute"]), "golpe forte precisa derrubar")
	var no_chao := l.bater(0.10, false, 2000)
	_ok(not bool(no_chao["desdenhou"]), "quem está na lona não pode desdenhar")
	l.free()

## O NOCAUTE PRECISA DERRUBAR.
##
## Medido no modelo anterior: durante a animação de nocaute que veio no
## arquivo, a cabeça do lutador saía de 1,59 m para 1,63 m e andava doze
## centímetros para trás. Ele não caía — inclinava e voltava. E o jogo
## inteiro acreditava: tocava o som de queda, anunciava NOCAUTE, gritava
## a torcida, levava a câmera para a altura da lona e esperava 3,35 s "no
## chão" com o boneco em pé o tempo todo.
##
## Com poses desenhadas a mecânica da queda é outra — o desenho já mostra
## o corpo no chão e o que falta é ele DESCER até lá —, mas a promessa ao
## jogo é exatamente a mesma, e é ela que este teste guarda.
func _test_o_nocaute_derruba_de_verdade() -> void:
	var l := _lutador()
	_ok(l.desenho_atual() != "nocaute", "de pé, ele não pode estar desenhado caído")
	l.bater(1.0, true, 9600)
	_correr(l, 130)
	_ok(l.queda > 0.9, "depois do nocaute o lutador tem de estar no chão")
	# AS DUAS COISAS QUE SÃO REAIS num corpo desenhado: o desenho exibido
	# vira o do nocaute, e o corpo desce até o tapete. Medir "a altura da
	# cabeça" seria inventar coordenada para um osso que não existe.
	_ok(l.desenho_atual() == "nocaute",
		"na lona ele tem de estar desenhado caído (está em %s)" % l.desenho_atual())
	_ok(l.fundura_do_tombo() > 0.85,
		"o corpo tem de descer até a lona (desceu %.2f)" % l.fundura_do_tombo())
	l.free()

## O CORPO CAÍDO CONTINUA DENTRO DO QUADRO.
##
## Esta é a linha que o erro original quebrava: a queda baixava o corpo
## 62 cm além de tombá-lo e, como a raiz já fica na altura da lona, o
## boneco saía por baixo do ringue. A moldura mostrava um ringue vazio no
## momento mais importante do jogo.
func _test_o_nocaute_nao_afunda_o_lutador() -> void:
	var l := _lutador()
	var reacao := l.bater(1.0, true)
	_ok(bool(reacao["nocaute"]), "um nível que derruba tem de derrubar no primeiro soco")
	_correr(l, 130)
	_ok(l.queda > 0.9, "depois de dois segundos ele tem de estar na lona")
	var corpo := l.get_node_or_null("Corpo") as Node3D
	_ok(corpo.position.y > -0.45,
		"o lutador caído não pode afundar na lona (y=%.2f)" % corpo.position.y)
	_ok(absf(corpo.position.x) < 0.6,
		"o lutador caído não pode sair de lado do quadro (x=%.2f)" % corpo.position.x)
	l.free()


func _test_levantar_devolve_o_lutador_para_cima_da_lona() -> void:
	var l := _lutador()
	l.bater(1.0, true)
	# Queda, contagem e volta: seis segundos cobrem o ciclo inteiro.
	_correr(l, 400)
	_ok(l.queda <= 0.001, "ele tem de levantar sozinho para o próximo soco")
	_ok(l.dano < 1.0, "quem levanta volta com fôlego para levar o segundo soco")
	_perto(l.fundura_do_tombo(), 0.0, 0.05, "de pé, o corpo volta à altura de antes")
	_ok(l.desenho_atual() != "nocaute", "e ele não pode continuar desenhado no chão")
	l.free()

## E A RODADA SEGUINTE COMEÇA COM O CORPO NO LUGAR.
##
## Uma rodada pode ACABAR com o adversário no chão. Sem devolver a pose
## de nascimento, o jogador seguinte encontraria o lutador deitado no
## tapete esperando um soco — e assim a noite inteira.
func _test_preparar_desfaz_a_pose_do_tombo() -> void:
	var l := _lutador()
	var corpo := l.get_node_or_null("Corpo") as Node3D
	l.bater(1.0, true)
	_correr(l, 90)
	_ok(corpo.position.y < -0.15, "o tombo tem de baixar o corpo")
	l.preparar()
	l.atualizar(1.0 / 60.0)
	_ok(corpo.position.y > -0.05, "a rodada seguinte começa com ele de pé")
	_ok(l.queda <= 0.001, "e sem queda pendurada")
	l.free()

# ------------------------------------------------------------- frases
func _test_as_frases_cobrem_todos_os_niveis() -> void:
	for nivel in ScoreTier.NIVEIS:
		var id := str(nivel["id"])
		_ok(ArenaFrases.GOLPES.has(id), "o nível %s precisa das frases dele" % id)
		var lista: Array = ArenaFrases.GOLPES.get(id, [])
		# Uma frase por nível vira rótulo; duas ou mais viram narrador.
		_ok(lista.size() >= 2, "o nível %s precisa de mais de uma frase" % id)
		for i in range(6):
			_ok(not ArenaFrases.de_golpe(id, i).is_empty(), "frase vazia no nível %s" % id)
	_ok(ArenaFrases.de_dano(0.0) == "INTEIRO", "sem dano, o adversário está inteiro")
	_ok(ArenaFrases.de_dano(1.0) == "POR UM FIO", "no talo, o adversário está por um fio")

func _test_a_frase_nao_troca_sozinha() -> void:
	# `_draw` roda sessenta vezes por segundo: a mesma semente TEM de
	# devolver a mesma frase, senão o texto pisca trocando de palavra
	# enquanto a pessoa lê.
	var primeira := ArenaFrases.de_golpe("NOCAUTE", 3)
	for i in range(20):
		_ok(ArenaFrases.de_golpe("NOCAUTE", 3) == primeira, "a frase não pode mudar com a mesma semente")

# --------------------------------------------------------------- som
func _test_os_sons_da_arena_existem() -> void:
	const Catalogo = preload("res://scripts/audio/audio_catalog.gd")
	for cue in [
		"arena_corpo", "arena_queda", "arena_publico",
		"torcida_desdenho",
		"torcida_recorde", "torcida_podio", "torcida_top10", "torcida_top20",
	]:
		_ok(cue in Catalogo.EXTRA, "%s tem de estar no catálogo" % cue)
		var caminho: String = Catalogo.path_for(cue)
		_ok(ResourceLoader.exists(caminho) or FileAccess.file_exists(caminho),
			"o arquivo de %s tem de existir" % cue)
	# O baque do corpo divide o barramento do soco: se ele caísse em SFX,
	# o controle de volume dos efeitos o abafaria junto com os bipes.
	_ok(Catalogo.bus_for("arena_corpo") == "Impact", "o baque do corpo é som de impacto")
	_ok(Catalogo.bus_for("arena_queda") == "Impact", "a queda é som de impacto")

# ------------------------------------------------------------ ligação
func _test_a_arena_so_liga_nas_telas_do_soco() -> void:
	var jogo := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(jogo)
	jogo.intro_active = false
	jogo.central_aberta = false
	var esperado := {
		GameDef.State.IDLE: false,
		GameDef.State.COUNTDOWN: true,
		GameDef.State.ARMED: true,
		GameDef.State.MEASURING: true,
		GameDef.State.RESULT: true,
	}
	for estado in esperado:
		jogo.state = estado
		jogo.verdict_time = -1.0
		_ok(jogo._arena_no_ar() == esperado[estado], "arena ligada no estado %d" % estado)
	# Na tabela de recordes a moldura já saiu da tela: manter o mundo 3D
	# desenhando ali é gastar uma TV Box por nada.
	#
	# A TABELA É O FIM DA RODADA, e não um relógio solto: quem ainda tem
	# soco a dar continua vendo a arena. Enquanto a revelação começava no
	# mesmo instante em que o segundo soco era armado, os dois casos
	# davam no mesmo e ninguém precisou escolher; encurtar a revelação
	# separou os relógios. Ver `_tabela_no_ar`.
	jogo.state = GameDef.State.RESULT
	jogo.verdict_time = 3.0
	jogo.socos = [{"pontos": 5000, "velocidade": 3.0, "pico_g": 0.0, "duracao_ms": 9.0, "simulado": true}]
	_ok(jogo._arena_no_ar(), "no meio da rodada a arena continua no ar")
	jogo.rodada_encerrada_antecipadamente = true
	_ok(not jogo._arena_no_ar(), "a arena desliga quando a tabela de recordes entra")
	jogo.socos = []
	jogo.rodada_encerrada_antecipadamente = false
	jogo.verdict_time = -1.0
	jogo.central_aberta = true
	jogo.state = GameDef.State.ARMED
	_ok(not jogo._arena_no_ar(), "a arena desliga com a Central aberta")
	jogo.queue_free()
