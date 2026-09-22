extends SceneTree

## Testes de núcleo: curva, níveis, ranking e estatística. Puros — não
## abrem cena nem tocam áudio. O fluxo da máquina é testado em
## `tests/test_show_flow.gd`.

func _initialize() -> void:
	_test_escala_e_niveis()
	_test_curva_monotonica()
	_test_ancoras_da_curva()
	_test_zona_morta_e_teto()
	_test_progressao_sensor()
	_test_migracao_acontece_uma_vez()
	_test_top20_guarda_vinte_e_a_foto_certa()
	_test_comemoracoes_do_ranking_sao_diferentes()
	_test_statistics()
	_test_ritmo()
	_test_auto_escala()
	_test_a_festa_cabe_num_quadro()
	_test_calibracao()
	# ---------------------------------------------- as fitas de LED
	# O quinto campo do CONFIG e o teto das fitas, e ele e OPCIONAL nos
	# dois lados: firmware novo tem de aceitar o CONFIG de quatro campos
	# de um jogo antigo, e este jogo so manda o quinto quando ele existe.
	var curto := ArduinoProtocol.build_config("A", 0.020, 1.2, 0.7)
	assert(curto == "CONFIG,A,0.020,1.20,0.70")
	var longo := ArduinoProtocol.build_config("L", 0.035, 1.2, 0.7, 16.0)
	assert(longo == "CONFIG,L,0.035,1.20,0.70,16.00")
	# Teto abaixo do piso nao existe: a placa dividiria por uma faixa
	# negativa e a coluna encheria ao contrario.
	var invertido := ArduinoProtocol.build_config("A", 0.020, 5.0, 0.7, 1.0)
	assert(invertido == "CONFIG,A,0.020,5.00,0.70,5.50")

	# A altura da coluna vai em por mil, e presa entre 0 e 1000.
	assert(ArduinoProtocol.build_leds(0.0) == "LEDS,0")
	assert(ArduinoProtocol.build_leds(1.0) == "LEDS,1000")
	assert(ArduinoProtocol.build_leds(0.4567) == "LEDS,457")
	assert(ArduinoProtocol.build_leds(-3.0) == "LEDS,0")
	assert(ArduinoProtocol.build_leds(9.0) == "LEDS,1000")

	# ------------------------------------------ o estado cru dos pinos
	# 1 e APERTADO: com INPUT_PULLUP o pino em repouso le ALTO, e o
	# firmware ja manda invertido para o numero significar o que a pessoa
	# espera ler.
	var pinos := ArduinoProtocol.parse("PINS,1,0")
	assert(str(pinos["type"]) == "PINS")
	assert(bool(pinos["start"]))
	assert(not bool(pinos["credit"]))
	assert(str(ArduinoProtocol.parse("PINS,1")["type"]) == "")

	# ------------------------------------ o arquivo chegou inteiro?
	# Se o .gd foi lido como Latin-1 e gravado como UTF-8 em algum
	# momento -- um PowerShell com Get-Content/Set-Content sem
	# -Encoding UTF8 faz isso --, o "c-cedilha" vira dois caracteres e
	# esta palavra passa de tres para cinco. Um length() responde.
	assert(Versao.PROVA.length() == 3)
	assert(Versao.acentos_inteiros())

	print("CORE_TESTS_OK")
	quit(0)

# ------------------------------------------------------------ escala
func _test_escala_e_niveis() -> void:
	assert(GameDef.SCORE_MAX == 9999)
	assert(ScoreTier.PERFEITO == GameDef.SCORE_MAX)
	# As oito faixas cobrem 0..9999 sem buraco e sem sobreposição.
	var esperado := 0
	for nivel in ScoreTier.NIVEIS:
		assert(int(nivel["min"]) == esperado)
		assert(int(nivel["max"]) >= int(nivel["min"]))
		esperado = int(nivel["max"]) + 1
	assert(esperado == GameDef.SCORE_MAX + 1)
	assert(ScoreTier.NIVEIS.size() == 8)
	# Cada nível tem apresentação PRÓPRIA: nenhum par pode compartilhar a
	# mesma receita de efeito, senão dois níveis leem igual na tela.
	var assinaturas := {}
	for nivel in ScoreTier.NIVEIS:
		var chave := "%s|%.2f|%.2f|%.3f|%d|%d|%d" % [
			str(nivel["cor"]), nivel["tremor"], nivel["clarao"], nivel["hitstop"],
			int(nivel["ondas"]), int(nivel["brasas"]), int(nivel["raios"]),
		]
		assert(not assinaturas.has(chave))
		assinaturas[chave] = true
		assert(not str(nivel["som"]).is_empty())
	assert(ScoreTier.nome_de(0) == "IMPACTO LEVE")
	assert(ScoreTier.nome_de(9999) == "SOCO PERFEITO")
	assert(ScoreTier.nome_de(9998) == "LENDÁRIO")
	# As três faixas grossas continuam derivando dos níveis.
	assert(GameDef.faixa_de(0) == GameDef.Faixa.FRACA)
	assert(GameDef.faixa_de(4500) == GameDef.Faixa.MEDIA)
	assert(GameDef.faixa_de(9999) == GameDef.Faixa.FORTE)

# ------------------------------------------------------------ curva
func _test_curva_monotonica() -> void:
	var vmin := ScoreCurve.DEFAULT_MIN_SPEED
	var vmax := ScoreCurve.DEFAULT_MAX_SPEED
	var k := ScoreCurve.DEFAULT_CONTRASTE
	var dz := ScoreCurve.DEFAULT_DEAD_ZONE
	# Passo fino, e além do teto: um soco mais forte NUNCA pode valer
	# menos. Vale para qualquer âncora e qualquer contraste — é a única
	# promessa que uma máquina de soco não pode quebrar nem uma vez.
	for ref_fracao in [0.25, 0.45, 0.55, 0.78]:
		for contraste in [ScoreCurve.CONTRASTE_MIN, 1.0, k, ScoreCurve.CONTRASTE_MAX]:
			var ref: float = lerpf(vmin, vmax, ref_fracao)
			var anterior := -1
			for i in range(0, 2001):
				var v := float(i) * 0.02
				var pts := ScoreCurve.points_from_speed(v, vmin, vmax, contraste, dz, ref)
				assert(pts >= anterior)
				assert(pts >= 0 and pts <= GameDef.SCORE_MAX)
				anterior = pts

	# A DIFICULDADE É O SOCO DE REFERÊNCIA, e ela é monotônica: exigir
	# mais velocidade para pagar meio placar nunca pode render MAIS
	# pontos na mesma velocidade. É o que torna o ajuste defensável.
	var meio := (vmin + vmax) * 0.5
	var facil := ScoreCurve.points_from_speed(meio, vmin, vmax, k, dz, lerpf(vmin, vmax, 0.35))
	var normal := ScoreCurve.points_from_speed(meio, vmin, vmax, k, dz, lerpf(vmin, vmax, 0.55))
	var duro := ScoreCurve.points_from_speed(meio, vmin, vmax, k, dz, lerpf(vmin, vmax, 0.78))
	assert(facil > normal)
	assert(normal > duro)
	assert(ScoreCurve.difficulty_name(vmin, vmax, lerpf(vmin, vmax, 0.30)) == "FÁCIL")
	assert(ScoreCurve.difficulty_name(vmin, vmax, lerpf(vmin, vmax, 0.55)) == "NORMAL")
	assert(ScoreCurve.difficulty_name(vmin, vmax, lerpf(vmin, vmax, 0.78)) == "IMPLACÁVEL")

	# A amostragem que a Central desenha também é monotônica.
	var curva := ScoreCurve.amostrar(vmin, vmax, k, dz, 60)
	var ultimo := -1.0
	for ponto in curva:
		assert((ponto as Vector2).y >= ultimo)
		ultimo = (ponto as Vector2).y

## A PROMESSA DAS TRÊS ÂNCORAS, que é o contrato inteiro da mecânica.
##
## Se alguma destas quebrar, "o soco médio paga 5000" deixa de ser uma
## frase que se pode dizer ao dono da máquina — e era exatamente a falta
## dessa frase que fazia a regulagem antiga ser adivinhação.
func _test_ancoras_da_curva() -> void:
	var vmin := ScoreCurve.DEFAULT_MIN_SPEED
	var vmax := ScoreCurve.DEFAULT_MAX_SPEED
	for ref_fracao in [0.25, 0.35, 0.45, 0.55, 0.70, 0.78]:
		for contraste in [ScoreCurve.CONTRASTE_MIN, 1.0, 1.15, ScoreCurve.CONTRASTE_MAX]:
			var ref: float = lerpf(vmin, vmax, ref_fracao)
			# 1. O soco de referência paga exatamente meio placar,
			#    qualquer que seja o contraste.
			var no_ref := ScoreCurve.points_from_speed(ref, vmin, vmax, contraste, 0.0, ref)
			assert(absi(no_ref - ScoreCurve.PONTOS_DE_REFERENCIA) <= 2)
			# 2. O piso é zero e o teto é o teto.
			assert(ScoreCurve.points_from_speed(vmin, vmin, vmax, contraste, 0.0, ref) == 0)
			assert(
				ScoreCurve.points_from_speed(vmax, vmin, vmax, contraste, 0.0, ref)
				== GameDef.SCORE_MAX
			)
	# 3. O CONTRASTE NÃO MEXE NA DIFICULDADE MÉDIA: ele espalha em volta
	#    da referência. Abaixo dela, mais contraste dá menos; acima dela,
	#    mais. Se os dois lados andassem juntos, o botão seria um segundo
	#    botão de dificuldade disfarçado — e dois botões para a mesma
	#    coisa é como eles acabam discordando.
	var ref_meio: float = lerpf(vmin, vmax, 0.55)
	var abaixo: float = lerpf(vmin, ref_meio, 0.5)
	var acima: float = lerpf(ref_meio, vmax, 0.5)
	assert(
		ScoreCurve.points_from_speed(abaixo, vmin, vmax, 1.6, 0.0, ref_meio)
		< ScoreCurve.points_from_speed(abaixo, vmin, vmax, 0.8, 0.0, ref_meio)
	)
	assert(
		ScoreCurve.points_from_speed(acima, vmin, vmax, 1.6, 0.0, ref_meio)
		> ScoreCurve.points_from_speed(acima, vmin, vmax, 0.8, 0.0, ref_meio)
	)
	# 4. UM SOCO COMUM TEM DE LER COMO SOCO. Era esta a queixa: a curva
	#    antiga pagava 974 a 35% da faixa, e "mil" lê como máquina que
	#    não registrou. Com as âncoras, a mesma velocidade paga bem mais
	#    de dois mil — e continua longe do topo.
	var comum: float = lerpf(vmin, vmax, 0.35)
	var nota := ScoreCurve.points_from_speed(comum, vmin, vmax)
	assert(nota > 2000)
	assert(nota < 4000)
	# 5. E UM SOCO FORTE TEM DE LER COMO FORTE, sem ser 9999.
	var forte: float = lerpf(vmin, vmax, 0.85)
	assert(GameDef.faixa_de(ScoreCurve.points_from_speed(forte, vmin, vmax)) == GameDef.Faixa.FORTE)
	assert(ScoreCurve.points_from_speed(forte, vmin, vmax) < GameDef.SCORE_MAX)

func _test_zona_morta_e_teto() -> void:
	var vmin := ScoreCurve.DEFAULT_MIN_SPEED
	var vmax := ScoreCurve.DEFAULT_MAX_SPEED
	var k := ScoreCurve.DEFAULT_CONTRASTE
	var dz := 0.08
	# Abaixo e no piso: zero. Dentro da zona morta: ainda zero.
	assert(ScoreCurve.points_from_speed(0.0, vmin, vmax, k, dz) == 0)
	assert(ScoreCurve.points_from_speed(vmin, vmin, vmax, k, dz) == 0)
	var span := vmax - vmin
	assert(ScoreCurve.points_from_speed(vmin + span * dz * 0.5, vmin, vmax, k, dz) == 0)
	assert(ScoreCurve.points_from_speed(vmin + span * dz, vmin, vmax, k, dz) == 0)
	# Passada a zona morta, a nota existe e cresce.
	assert(ScoreCurve.points_from_speed(vmin + span * (dz + 0.02), vmin, vmax, k, dz) > 0)
	assert(ScoreCurve.points_from_speed(vmin + span * 0.5, vmin, vmax, k, dz) > 0)
	# 9999 SÓ no teto — esta é a garantia que faz o topo valer alguma
	# coisa, e ela não mudou com a curva nova.
	assert(ScoreCurve.points_from_speed(vmax, vmin, vmax, k, dz) == GameDef.SCORE_MAX)
	assert(ScoreCurve.points_from_speed(vmax * 2.0, vmin, vmax, k, dz) == GameDef.SCORE_MAX)
	assert(ScoreCurve.points_from_speed(vmax - 0.01, vmin, vmax, k, dz) < GameDef.SCORE_MAX)
	assert(ScoreCurve.points_from_speed(vmax * 0.90, vmin, vmax, k, dz) < GameDef.SCORE_MAX)

# ------------------------------------------------------------ ranking
func _test_progressao_sensor() -> void:
	# Leituras baixas distintas antes colapsavam em 1; agora progridem.
	var anterior := 1
	for velocidade in [0.6, 0.8, 1.0, 1.5, 2.0]:
		var pontos := ScoreCurve.points_from_speed(velocidade, 0.3, 5.2)
		assert(pontos > anterior)
		anterior = pontos
	# A ESCALA É RELATIVA À FAIXA CALIBRADA, e não a um teto fixo: a
	# mesma fração da faixa paga a mesma nota numa máquina que mede até
	# 1,2 m/s e noutra que mede até 16.
	var referencia := -1
	for teto in [1.2, 2.4, 5.2, 16.0]:
		assert(is_equal_approx(
			ScoreCurve.sanitize(0.3, teto, ScoreCurve.DEFAULT_CONTRASTE, 0.0)["max_speed"], teto
		))
		var a_noventa := ScoreCurve.points_from_speed(lerpf(0.3, teto, 0.90), 0.3, teto)
		if referencia < 0:
			referencia = a_noventa
		assert(absi(a_noventa - referencia) <= 2)
		# Noventa por cento da faixa é NOCAUTE para cima — um soco assim
		# merece ser comemorado —, e mesmo assim não é o topo.
		assert(a_noventa >= 8000)
		assert(a_noventa < GameDef.SCORE_MAX)
		assert(ScoreCurve.points_from_speed(teto, 0.3, teto) == 9999)
	# Uma montagem lenta (saco pesado, palheta larga) continua entregando
	# a escala inteira: o teto dela é 9999 como o de qualquer outra.
	var cfg := Calibracao.sugerir(
		[0.3, 0.35, 0.4, 0.45, 0.5], [1.0, 1.1, 1.2, 1.25, 1.3], 0.3
	)
	assert(float(cfg["vmax"]) < 1.8)
	assert(float(cfg["vmin"]) < float(cfg["vref"]))
	assert(float(cfg["vref"]) < float(cfg["vmax"]))
	assert(ScoreCurve.points_from_speed(
		float(cfg["vref"]), cfg["vmin"], cfg["vmax"], ScoreCurve.DEFAULT_CONTRASTE, 0.0, cfg["vref"]
	) >= ScoreCurve.PONTOS_DE_REFERENCIA - 2)

func _test_migracao_acontece_uma_vez() -> void:
	# Arquivo antigo, escala 0 a 999, sem versão gravada.
	var antigo := [{"score": 900}, {"score": 500}, 250]
	var convertido := RankingStore.migrate(antigo, 0, RankingStore.ESQUEMA_LEGADO)
	assert(RankingStore.best(convertido) == 9000)
	assert(RankingStore.score_at(convertido, 1) == 5000)
	assert(RankingStore.score_at(convertido, 2) == 2500)
	# Reabrir JÁ CONVERTIDO não pode multiplicar de novo.
	var reaberto := RankingStore.migrate(convertido, 0, RankingStore.ESQUEMA)
	assert(RankingStore.best(reaberto) == 9000)
	var terceira := RankingStore.migrate(reaberto, 0, RankingStore.ESQUEMA)
	assert(RankingStore.best(terceira) == 9000)
	# O recorde solto de instalações muito antigas também converte uma vez.
	var so_recorde := RankingStore.migrate([], 870, RankingStore.ESQUEMA_LEGADO)
	assert(RankingStore.best(so_recorde) == 8700)
	# E a conversão respeita o teto.
	var estourado := RankingStore.migrate([{"score": 999}], 0, RankingStore.ESQUEMA_LEGADO)
	assert(RankingStore.best(estourado) == 9990)

func _test_comemoracoes_do_ranking_sao_diferentes() -> void:
	var posicoes := [1, 2, 7, 15]
	var ids := {}
	var anterior := 10000
	for posicao in posicoes:
		var festa := RankingCelebration.para(posicao)
		assert(not festa.is_empty())
		assert(not ids.has(festa["id"]))
		ids[festa["id"]] = true
		assert(int(festa["confetes"]) < anterior)
		anterior = int(festa["confetes"])
		assert(not str(festa["som"]).is_empty())
	assert(RankingCelebration.para(21).is_empty())

func _test_top20_guarda_vinte_e_a_foto_certa() -> void:
	var entries: Array[Dictionary] = []
	for score in range(1000, 3500, 100):
		entries.assign(RankingStore.insert(entries, score, "foto_%d.png" % score)["entries"])
	assert(entries.size() == RankingStore.LIMIT)
	# A foto acompanha a marca, e não o índice.
	for entrada in entries:
		assert(str(entrada["photo_path"]) == "foto_%d.png" % int(entrada["score"]))
	assert(RankingStore.score_at(entries, 0) == 3400)
	assert(RankingStore.score_at(entries, 19) == 1500)
	# Entrar no fim empurra a última para fora e devolve a foto descartada.
	var entrou := RankingStore.insert(entries, 1550, "foto_nova.png")
	assert(int(entrou["position"]) == 20)
	assert((entrou["entries"] as Array).size() == RankingStore.LIMIT)
	assert((entrou["dropped_photos"] as Array).size() == 1)
	assert(str((entrou["dropped_photos"] as Array)[0]) == "foto_1500.png")
	# Marca fraca demais não entra e não guarda foto.
	var fora := RankingStore.insert(entries, 100, "descartar.png")
	assert(int(fora["position"]) == 0)
	assert(str((fora["dropped_photos"] as Array)[0]) == "descartar.png")

func _test_statistics() -> void:
	var stats := StatisticsStore.record({}, 5000, GameDef.Faixa.MEDIA, true)
	stats = StatisticsStore.record(stats, 8000, GameDef.Faixa.FORTE, false)
	var summary := StatisticsStore.summary(stats)
	assert(int(summary["today"]) == 2)
	assert(int(summary["average"]) == 6500)
	assert(int(summary["best"]) == 8000)
	assert(int(summary["top5_entries"]) == 1)

# ---------------------------------------------------------- partículas
## A FESTA INTEIRA TEM DE CABER NUM QUADRO — COM FOLGA.
##
## Este é o teste do "o confete desce travado". Medido, a versão anterior
## gastava 31 ms só para DESENHAR as partículas de uma comemoração cheia.
## Um quadro a 60 fps tem 16,7 ms no total: o confete sozinho custava
## quase dois quadros, e a festa — justamente o momento em que o jogo
## precisa impressionar — rodava a menos de 30 fps em qualquer máquina.
##
## Duas causas, as duas por partícula: um `Dictionary` cada (busca por
## chave de texto, e lixo para o coletor recolher) e uma chamada de
## desenho cada (novecentos comandos por quadro para a placa de vídeo).
## Ver `PunchFX`.
##
## O limite aqui é de teste de fumaça, não de precisão: numa máquina de
## integração o relógio é ruidoso e o número exato não se repete. O que
## ele guarda é a ORDEM DE GRANDEZA — se alguém voltar a desenhar
## partícula por partícula, o tempo sobe dez vezes e isto reprova.
func _test_a_festa_cabe_num_quadro() -> void:
	var tela := Control.new()
	tela.size = Vector2(1080.0, 1920.0)
	var fx := PunchFX.new()
	var cores := [Color("ffd34e"), Color("ff9f36"), Color("33d7ff"), Color("7be495")]
	# A festa de um campeão: chuva, canhões e a explosão do soco juntos.
	for i in range(6):
		fx.chuva_de_confete(1080.0, 40, cores, 1.2)
		fx.confete(Vector2(540.0, 1880.0), 40, cores, 880.0)
		fx.explosao(Vector2(540.0, 893.0), 120, cores, 1100.0)
		fx.faiscas(Vector2(540.0, 893.0), 110, cores[0], 1000.0)
		fx.estilhacos(Vector2(540.0, 893.0), 30, cores[1])
		fx.raios(Vector2(540.0, 893.0), 26, cores[2], 780.0)
		fx.poeira(Vector2(540.0, 1000.0), 30, cores[3], 380.0)
	# O teto de partículas é respeitado — sem ele não há orçamento que valha.
	assert(fx.quantidade() == PunchFX.LIMITE)

	var inicio := Time.get_ticks_usec()
	for q in range(240):
		fx.atualizar(1.0 / 60.0)
	var por_quadro := float(Time.get_ticks_usec() - inicio) / 240.0 / 1000.0
	# Medido em 0,13 ms. Cinco milissegundos é folga de sobra e ainda
	# reprova a volta ao `Dictionary`, que custava quatro vezes mais.
	assert(por_quadro < 5.0)

	# E as partículas morrem: uma festa que não termina enche o teto e
	# nunca mais sai de lá, e aí toda a tela seguinte paga por ela.
	for q in range(400):
		fx.atualizar(1.0 / 60.0)
	assert(fx.quantidade() == 0)
	assert(not fx.vivo())
	tela.free()

# --------------------------------------------------------- auto-escala
## A MÁQUINA APRENDE A FAIXA DO PRÓPRIO GABINETE.
##
## Este é o teste do "não consigo passar de mil". A faixa de fábrica
## (0,30 a 5,20 m/s) foi medida na bancada; um gabinete cuja palheta mal
## alcança 1,2 m/s vive no primeiro quinto dela, e todo mundo tira a
## mesma nota baixa — sem que nada esteja quebrado e sem nenhuma pista na
## tela de por quê.
func _test_auto_escala() -> void:
	# Um gabinete lento: os socos vão de 0,45 a 1,25 m/s, com a maioria
	# em torno de 0,85. É o caso real que chegou.
	var rng := RandomNumberGenerator.new()
	rng.seed = 17092026
	var salao: Array[float] = []
	for i in range(160):
		salao.append(clampf(rng.randfn(0.85, 0.22), 0.40, 1.30))

	var ordenado := salao.duplicate()
	ordenado.sort()
	var mediana: float = ordenado[ordenado.size() / 2]

	# ANTES: com a régua de fábrica, o cliente mediano tira menos de mil.
	# Não é uma estatística escolhida a dedo — é literalmente a frase que
	# chegou, "não consigo passar de mil", escrita como teste.
	assert(ScoreCurve.points_from_speed(
		mediana, ScoreCurve.DEFAULT_MIN_SPEED, ScoreCurve.DEFAULT_MAX_SPEED
	) < 1000)

	# A régua aprende, um passo por rodada, a partir da de fábrica.
	var escala := AutoEscala.new()
	var vmin := ScoreCurve.DEFAULT_MIN_SPEED
	var vmax := ScoreCurve.DEFAULT_MAX_SPEED
	var vref := vmin + (vmax - vmin) * ScoreCurve.REFERENCIA_PADRAO
	for v in salao:
		escala.registrar(v)
		var novo := escala.passo(vmin, vref, vmax)
		if not novo.is_empty():
			var limpo := ScoreCurve.sanitize(
				float(novo["vmin"]), float(novo["vmax"]),
				ScoreCurve.DEFAULT_CONTRASTE, 0.0, float(novo["vref"])
			)
			vmin = limpo["min_speed"]
			vmax = limpo["max_speed"]
			vref = limpo["ref_speed"]

	# DEPOIS: a régua descreve o gabinete, e a escala inteira volta a ser
	# usada. A mediana do salão passa a valer perto de meio placar — é
	# esta linha que significa "equilibrado", e é o que a régua aprendida
	# entrega em QUALQUER gabinete, sem ninguém configurar nada.
	var nota_da_mediana := ScoreCurve.points_from_speed(
		mediana, vmin, vmax, ScoreCurve.DEFAULT_CONTRASTE, 0.0, vref
	)
	assert(nota_da_mediana > 3200)
	assert(nota_da_mediana < 6800)

	# E O SOCO MAIS FORTE DO SALÃO CHEGA PERTO DO TOPO, sem entregá-lo.
	var mais_forte: float = ordenado[ordenado.size() - 1]
	var nota_do_forte := ScoreCurve.points_from_speed(
		mais_forte, vmin, vmax, ScoreCurve.DEFAULT_CONTRASTE, 0.0, vref
	)
	assert(nota_do_forte > 7000)
	assert(nota_do_forte <= GameDef.SCORE_MAX)

	# MAIS FORTE CONTINUA VALENDO MAIS. A régua pode se mexer, mas dentro
	# de uma mesma régua a ordem é sagrada — é a promessa do jogo.
	var anterior := -1
	for i in range(0, 300):
		var v := float(i) * 0.01
		var pts := ScoreCurve.points_from_speed(
			v, vmin, vmax, ScoreCurve.DEFAULT_CONTRASTE, 0.0, vref
		)
		assert(pts >= anterior)
		anterior = pts

	# ----------------------------------------------------- as travas
	# 1. SEM AMOSTRA ELA NÃO OPINA. Um gabinete recém-ligado usa o que
	#    está configurado, e não uma média de três golpes.
	var nova := AutoEscala.new()
	for i in range(AutoEscala.MINIMO_PARA_VALER - 1):
		nova.registrar(1.0)
		assert(nova.passo(0.3, 3.0, 5.2).is_empty())
	nova.registrar(1.0)
	assert(not nova.passo(0.3, 3.0, 5.2).is_empty())

	# 2. DESLIGADA, NÃO MEXE EM NADA.
	nova.ligada = false
	assert(nova.passo(0.3, 3.0, 5.2).is_empty())
	nova.ligada = true

	# 3. O PASSO É LIMITADO. Uma criança batendo dez vezes seguidas não
	#    pode derrubar a régua e fazer o adulto seguinte tirar 9999 — a
	#    tabela de recordes do dia iria junto.
	var firme := AutoEscala.new()
	for i in range(60):
		firme.registrar(0.5)
	var um_passo := firme.passo(0.3, 3.0, 5.2)
	assert(not um_passo.is_empty())
	# O teto anda em direção ao alvo, mas longe de chegar nele de uma vez.
	assert(float(um_passo["vmax"]) > 4.0)
	assert(float(um_passo["vmax"]) < 5.2)

	# 4. A MEMÓRIA NÃO CRESCE SEM LIMITE, e sobrevive ao disco.
	var cheia := AutoEscala.new()
	for i in range(AutoEscala.JANELA * 2):
		cheia.registrar(1.0 + float(i % 7) * 0.1)
	assert(cheia.quantos() == AutoEscala.JANELA)
	var copia := AutoEscala.new()
	copia.carregar(cheia.para_salvar())
	assert(copia.quantos() == cheia.quantos())
	assert(copia.ligada == cheia.ligada)
	# Lixo gravado por uma versão anterior não entra: uma velocidade
	# absurda deslocaria a régua inteira sem nenhuma explicação na tela.
	var suja := AutoEscala.new()
	suja.carregar({"ligada": true, "socos": [1.0, -3.0, 999.0, 2.0, 0.0]})
	assert(suja.quantos() == 2)

# --------------------------------------------------------------- ritmo
## O PASSO DO JOGO. Ver `scripts/ritmo.gd` para o defeito que ele
## conserta; aqui ficam as três promessas que ele faz, porque nenhuma
## delas dá para conferir olhando a tela: um movimento trêmulo e um
## movimento liso parecem a mesma coisa num print.
func _test_ritmo() -> void:
	var r := Ritmo.new()
	var quadro := 1.0 / 60.0

	# 1. O RUÍDO DESAPARECE. Entrando um relógio que chacoalha alguns
	#    décimos de milissegundo em volta do quadro de tela — que é o que
	#    um PC folgado entrega —, o passo sai constante. É esta trepidação,
	#    e não a queda de quadros, que o olho lê como "não natural".
	var ruidosos := [0.0167, 0.0182, 0.0151, 0.0167, 0.0179, 0.0155, 0.0167, 0.0171]
	for volta in range(3):
		for d in ruidosos:
			r.passo(d)
	var maior := 0.0
	var menor := 1.0
	for d in ruidosos:
		var p := r.passo(d)
		maior = maxf(maior, p)
		menor = minf(menor, p)
	# O espalhamento na entrada é de 3,1 ms. Medido, o de saída fica em
	# torno de 0,7 ms — o limite aqui é folgado de propósito, porque o
	# que este teste guarda é "melhorou muito", não um número exato que
	# qualquer ajuste fino da janela quebraria sem nada ter piorado.
	assert(maior - menor < 0.0015)

	# 1b. O CASO QUE MAIS IMPORTA: o vsync alternando 60/30/60/30 numa
	#     máquina que não fecha o quadro a tempo. A entrada salta 16,7 ms
	#     entre um quadro e o seguinte — o dobro de duração —, e é esse
	#     salto que vira solavanco na tela. É o modo de falhar normal de
	#     um PC fraco, e nenhum teto de delta jamais o pegou.
	var rv := Ritmo.new()
	var alterna: Array[float] = []
	for i in range(24):
		alterna.append(quadro if i % 2 == 0 else quadro * 2.0)
	for d in alterna:
		rv.passo(d)
	var v_maior := 0.0
	var v_menor := 1.0
	for d in alterna:
		var p := rv.passo(d)
		v_maior = maxf(v_maior, p)
		v_menor = minf(v_menor, p)
	# De 16,7 ms de salto para menos de 3: o movimento deixa de pular.
	assert(v_maior - v_menor < 0.003)

	# 2. O SOLUÇO NÃO VIRA UM PULO. Um quadro de meio segundo — a
	#    primeira fonte sendo rasterizada, o sistema engasgando — não
	#    pode fazer o jogo inteiro andar meio segundo de uma vez, com a
	#    contagem saltando números.
	var r2 := Ritmo.new()
	for i in range(8):
		r2.passo(quadro)
	assert(r2.passo(0.75) < Ritmo.PASSO_MAXIMO)
	assert(r2.passo(0.75) < 0.05)

	# 3. SUAVIZAR NÃO É ATRASAR. Uma média sozinha deixaria o relógio do
	#    jogo para trás do relógio de verdade, para sempre — e atraso
	#    acumulado é como uma contagem de três segundos passa a durar
	#    três segundos e meio. A dívida devolve o que a média segurou.
	var r3 := Ritmo.new()
	var real := 0.0
	var jogo := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260917
	for i in range(1200):
		var d := quadro * rng.randf_range(0.88, 1.16)
		real += d
		jogo += r3.passo(d)
	# Vinte segundos de jogo com menos de um quadro de diferença.
	assert(absf(jogo - real) < quadro)

	# 4. NENHUMA ENTRADA ABSURDA PODE CONGELAR A MÁQUINA.
	#
	#    Zero, negativo, um centésimo de milissegundo, dez segundos: em
	#    todos o passo tem de continuar sendo um passo de jogo. O caso do
	#    quadro quase-zero foi um defeito de verdade deste módulo — ele
	#    entrava na média e deixava o relógio preso no piso do `clampf`,
	#    com o jogo desenhando e nada se movendo. Parece travamento, e é
	#    o tipo de coisa que ninguém consegue relatar direito.
	var r4 := Ritmo.new()
	for d in [0.0, -1.0, 0.00001, 10.0, 1e12, -1e12]:
		var p := r4.passo(d)
		assert(p >= Ritmo.PISO_DO_QUADRO * 0.5)
		assert(p <= Ritmo.PASSO_MAXIMO)
	# E depois do absurdo ele volta ao normal no primeiro quadro bom.
	assert(absf(r4.passo(quadro) - quadro) < 0.002)

# ------------------------------------------------------------ calibração
func _test_calibracao() -> void:
	assert(is_equal_approx(Calibracao.percentil([1.0, 2.0, 3.0], 0.5), 2.0))
	assert(is_equal_approx(Calibracao.percentil([5.0], 0.9), 5.0))
	assert(is_equal_approx(Calibracao.percentil([], 0.5), 0.0))
	# Percentil é interpolado, e não o elemento mais próximo.
	assert(is_equal_approx(Calibracao.percentil([0.0, 10.0], 0.25), 2.5))

	var fracos := [2.4, 2.0, 3.1, 2.2, 2.6]
	var fortes := [11.0, 12.5, 13.9, 12.1, 11.6]
	var s := Calibracao.sugerir(fracos, fortes, 0.6)
	# O piso sai ABAIXO do golpe fraco típico, e o teto ACIMA do forte
	# típico: quem bate fraco vê algum ponto, e 9999 continua raro.
	assert(float(s["vmin"]) < 2.4)
	assert(float(s["vmax"]) > 12.5)
	# A REFERÊNCIA CAI ENTRE AS DUAS DEMONSTRAÇÕES, e não em cima de
	# nenhuma delas: é a média do salão, não a do técnico.
	assert(float(s["vref"]) > 2.6)
	assert(float(s["vref"]) < 11.0)
	assert(Calibracao.pronta(fracos, fortes))
	assert(not Calibracao.pronta([1.0], fortes))

	# O GOLPE FORTE DA CALIBRAÇÃO NÃO PODE JÁ SER 9999. Um teto que o
	# próprio técnico encosta na primeira noite deixa de ser teto — e era
	# nisso que a folga de 8% ia dar com a curva nova.
	var forte_tipico := Calibracao.percentil(fortes, 0.5)
	var nota_do_forte := ScoreCurve.points_from_speed(
		forte_tipico, s["vmin"], s["vmax"], ScoreCurve.DEFAULT_CONTRASTE, 0.0, s["vref"]
	)
	assert(nota_do_forte >= 7500)
	assert(nota_do_forte < 9700)

	# UM GOLPE ESCAPADO NÃO PODE MANDAR NA CALIBRAÇÃO. Com um forte
	# ridículo e um fraco absurdo no meio, os percentis seguram.
	var sujo_fracos := [2.4, 2.0, 3.1, 2.2, 9.9]
	var sujo_fortes := [11.0, 12.5, 1.2, 12.1, 11.6]
	var t := Calibracao.sugerir(sujo_fracos, sujo_fortes, 0.6)
	assert(float(t["vmin"]) < 3.0)
	assert(float(t["vmax"]) > 10.0)

	# Se os dois grupos saírem parecidos, a escala não pode colapsar.
	var iguais := Calibracao.sugerir([6.0, 6.1, 6.0, 5.9, 6.0], [6.2, 6.1, 6.3, 6.0, 6.2], 0.4)
	assert(float(iguais["vmax"]) - float(iguais["vmin"]) >= 0.5)
	# E a sugestão sempre sai dentro dos limites que a Central aceita —
	# as três âncoras, e não só as duas pontas.
	for caso in [s, t, iguais]:
		var cfg := ScoreCurve.sanitize(
			float(caso["vmin"]), float(caso["vmax"]),
			ScoreCurve.DEFAULT_CONTRASTE, ScoreCurve.DEFAULT_DEAD_ZONE, float(caso["vref"])
		)
		assert(is_equal_approx(cfg["min_speed"], float(caso["vmin"])))
		assert(is_equal_approx(cfg["max_speed"], float(caso["vmax"])))
		assert(is_equal_approx(cfg["ref_speed"], float(caso["vref"])))

	_test_pulso_minimo()

## O PULSO MÍNIMO, QUE ERA O DEFEITO MAIS CARO DA REGULAGEM.
##
## A sugestão devolvia gravidades num campo que o firmware lê em
## milissegundos. Como pulso mínimo é um TETO DE VELOCIDADE ao contrário,
## o número errado não deixava a máquina insensível — deixava-a cega
## justamente para os socos fortes, que é o sintoma mais difícil de
## atribuir à causa certa.
func _test_pulso_minimo() -> void:
	# A conta é geometria pura: largura da palheta dividida pela
	# velocidade que ainda se aceita como soco.
	var pulso := ArduinoProtocol.pulso_minimo_ms(0.020, 5.2)
	var janela := ArduinoProtocol.janela_medivel(0.020, pulso)
	assert(is_equal_approx(janela.y, ArduinoProtocol.velocidade_teto(5.2)))

	# O TETO DO JOGO E O TETO DO FIRMWARE TROPEÇAM NO MESMO SOCO. Eram
	# duas regras para a mesma ideia, e a mais apertada vencia calada.
	for vmax in [1.2, 2.4, 5.2, 12.0, 20.0]:
		var ms := ArduinoProtocol.pulso_minimo_ms(0.020, vmax)
		var j := ArduinoProtocol.janela_medivel(0.020, ms)
		assert(is_equal_approx(j.y, ArduinoProtocol.velocidade_teto(vmax)))
		# E o teto calibrado sempre cabe dentro do que o sensor mede: se
		# não coubesse, a máquina recusaria como CURTO todo soco capaz
		# de tirar 9999 — o soco que ela existe para premiar.
		assert(j.y > vmax)

	# PALHETA MAIS LARGA, PULSO MAIS LONGO. Quem trocar a palheta sem
	# refazer a conta teria a faixa inteira deslocada.
	assert(
		ArduinoProtocol.pulso_minimo_ms(0.040, 5.2)
		> ArduinoProtocol.pulso_minimo_ms(0.020, 5.2)
	)
	# E a sugestão do assistente entrega o mesmo número que a conta —
	# uma fonte só, nunca duas que podem divergir.
	var sug := Calibracao.sugerir([2.0, 2.2, 2.4], [10.0, 11.0, 12.0], 0.2, 0.030)
	assert(is_equal_approx(
		float(sug["pulso_ms"]),
		ArduinoProtocol.pulso_minimo_ms(0.030, float(sug["vmax"]))
	))
	# O campo `amin` em gravidades NÃO VOLTA. Se ele reaparecer, alguém
	# religou o caminho que estrangulava a máquina.
	assert(not sug.has("amin"))
