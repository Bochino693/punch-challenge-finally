class_name EstudioArena
extends RefCounted

## OS SONS DO RINGUE: o baque no corpo, a queda na lona e a plateia.
##
## POR QUE ELES PRECISARAM EXISTIR. O soco já tinha o couro e o subgrave
## — o que faltava era o CORPO. Sem estes três, o lutador aparecia na
## tela mas o ouvido continuava batendo num saco de areia, e a arena
## inteira virava decoração.

var d: EstudioDSP
var pasta: String

func _init(dsp: EstudioDSP, destino: String) -> void:
	d = dsp
	pasta = destino

func gerar() -> void:
	d.salvar(pasta, "arena_corpo", corpo(), PackedFloat32Array(), false, 0.17)
	d.salvar(pasta, "arena_queda", queda(), PackedFloat32Array(), false, 0.16)
	# A torcida deixou de ser ruído sintetizado. Estes cinco WAVs são uma
	# gravação real CC0 e devem sobreviver a qualquer regeneração do banco.
	# Num destino de conferência, copie os masters em vez de inventar outra
	# plateia. A origem e a licença estão em assets/audio/LICENCAS.md.
	_copiar_torcidas_reais()
	# Reação exclusiva do golpe abaixo de 6.000; não compartilha o áudio
	# de comemoração para não premiar um golpe fraco.
	var par := torcida_desdenho()
	d.salvar(pasta, "torcida_desdenho", par[0], par[1], false, 0.105)

func _copiar_torcidas_reais() -> void:
	if pasta == "res://assets/audio/arcade":
		return
	for nome in ["arena_publico", "torcida_recorde", "torcida_podio", "torcida_top10", "torcida_top20"]:
		var origem := "res://assets/audio/arcade/%s.wav" % nome
		var destino := pasta.path_join("%s.wav" % nome)
		var bytes := FileAccess.get_file_as_bytes(origem)
		if bytes.is_empty():
			push_error("Torcida real ausente: %s" % origem)
			continue
		var arquivo := FileAccess.open(destino, FileAccess.WRITE)
		if arquivo != null:
			arquivo.store_buffer(bytes)

## O BAQUE NO TRONCO.
##
## A receita é a de um soco de cinema: um grave que despenca (o peso), um
## estalo curtíssimo e SURDO (o ar saindo), e nada de agudo. Todo o
## brilho fica por conta do `hit`, que toca junto — se os dois tivessem
## transiente agudo, o golpe soaria dobrado em vez de encorpado.
##
## AQUI ESTAVA O DEFEITO MAIS CARO DO BANCO DE ÁUDIO. `varredura` devolve
## uma CURVA DE FREQUÊNCIA — uma lista de hertz —, e ela só vira som
## depois de passar por um oscilador. O gerador antigo da arena usava a
## curva diretamente como se fosse onda, nas quatro vezes em que a
## chamava; o gerador dos efeitos, escrito antes, nunca fez isso.
##
## O que saía: uma rampa de 148 a 41 — de VALOR, não de frequência —
## moldada pelo envelope. Medido no arquivo gravado, `arena_corpo` tem
## ZERO cruzamentos de zero em meio segundo: não há oscilação nenhuma
## dentro dele. O "grave que despenca", que é a camada principal do
## baque, nunca existiu como tom; sobrava o estalo e o ar.
func corpo() -> PackedFloat32Array:
	var dur := 0.55
	var saida := d.zeros(dur)
	d.somar(saida, d.multiplicar(
		d.senoide_curva(d.varredura(148.0, 41.0, dur, 2.6)), d.env_ad(dur, 0.002, 0.34, 2.2)
	), 0, 1.0)
	d.somar(saida, d.multiplicar(
		d.senoide(78.0, dur), d.env_ad(dur, 0.004, 0.22, 3.0)
	), 0, 0.6)
	# O "UF": ruído passado num passa-baixas bem fechado. É o ar deixando
	# o pulmão, e é o que separa "bateu numa parede" de "bateu em alguém".
	d.somar(saida, d.multiplicar(
		d.biquad(d.ruido(dur), 420.0, 0.8, "lp"), d.env_ad(dur, 0.008, 0.18, 2.4)
	), 0, 0.5)
	d.somar(saida, d.multiplicar(
		d.biquad(d.ruido(0.06), 1800.0, 1.1, "bp"), d.env_ad(0.06, 0.001, 0.05, 4.0)
	), 0, 0.35)
	return d.satura(saida, 2.2)

## O CORPO NA LONA.
##
## Duas coisas soam ao mesmo tempo quando alguém cai num ringue: o corpo
## (grave, curto) e o ESTRADO (madeira ressoando, longa). A segunda é a
## que dá tamanho — sem ela a queda tem o mesmo peso de um livro caindo
## na mesa.
func queda() -> PackedFloat32Array:
	var dur := 1.5
	var saida := d.zeros(dur)
	# O mesmo conserto de `corpo`: a curva de frequência precisa passar
	# por um oscilador para virar som.
	d.somar(saida, d.multiplicar(
		d.senoide_curva(d.varredura(120.0, 33.0, 0.7, 3.2)), d.env_ad(0.7, 0.002, 0.5, 2.0)
	), 0, 1.1)
	var estrado := d.zeros(dur)
	for voz in [[62.0, 1.0, 1.1], [97.0, 0.55, 0.85], [151.0, 0.3, 0.6]]:
		d.somar(estrado, d.multiplicar(
			d.senoide(float(voz[0]), dur), d.env_ad(dur, 0.004, float(voz[2]), 2.4)
		), 0, float(voz[1]))
	d.somar(saida, d.escalar(estrado, 0.45), d.n_amostras(0.012), 1.0)
	d.somar(saida, d.multiplicar(
		d.biquad(d.ruido(0.35), 900.0, 0.7, "lp"), d.env_ad(0.35, 0.004, 0.3, 2.0)
	), 0, 0.4)
	# Uma sala grande em volta: a queda é o único som do jogo que precisa
	# soar LONGE, porque é o momento em que a câmera se afasta.
	return d.satura(d.reverb(saida, 0.72, 0.30), 1.8)

## O GINÁSIO DE PÉ.
##
## Multidão, acusticamente, é ruído rosa com formantes por volta de
## 500 Hz a 2 kHz e uma modulação lenta e irregular por cima — nunca um
## "aaah" afinado. A onda de aplauso entra depois do grito, porque é
## assim que acontece: primeiro o susto, depois a mão.
func publico() -> Array:
	var dur := 2.6
	var n := d.n_amostras(dur)
	var base := d.ruido(dur)
	var vozes := d.biquad(base, 850.0, 0.55, "bp")
	d.somar(vozes, d.biquad(base, 1750.0, 0.9, "bp"), 0, 0.55)
	var onda := PackedFloat32Array()
	var tremor := PackedFloat32Array()
	onda.resize(n)
	tremor.resize(n)
	for i in range(n):
		var t := float(i) / float(EstudioDSP.RATE)
		# A onda: sobe rápido, se sustenta, desce devagar.
		onda[i] = clampf(1.6 * (1.0 - exp(-t * 7.0)) * exp(-maxf(0.0, t - 0.9) * 1.25), 0.0, 1.6)
		# Irregularidade: sem ela o ruído soa como chuveiro, não como gente.
		tremor[i] = 1.0 + 0.22 * sin(TAU * 3.7 * t) + 0.14 * sin(TAU * 1.3 * t + 1.1)
	var grito := d.multiplicar(d.multiplicar(vozes, onda), tremor)

	var palmas := d.zeros(dur)
	# SETENTA PALMAS espalhadas, cada uma um estalo de 12 ms. Setenta e
	# não setecentas: o ouvido preenche o resto, e setecentas custariam
	# meio minuto de geração para soar igual.
	for i in range(70):
		var quando := d.n_amostras(d.entre(0.35, dur - 0.2))
		var estalo := d.multiplicar(
			d.biquad(d.ruido(0.012), d.entre(1600.0, 3400.0), 1.4, "bp"),
			d.env_ad(0.012, 0.0005, 0.010, 3.0)
		)
		d.somar(palmas, estalo, quando, d.entre(0.25, 0.75))
	for i in range(n):
		var t2 := float(i) / float(EstudioDSP.RATE)
		palmas[i] *= clampf((t2 - 0.3) * 1.4, 0.0, 1.0) * exp(-maxf(0.0, t2 - 1.4) * 0.9)

	var misto := d.escalar(grito, 0.75)
	d.somar(misto, palmas, 0, 0.9)
	# ESTÉREO DE VERDADE: a plateia é o único som do jogo que tem de
	# parecer vir de TODOS os lados, e dois ruídos independentes fazem
	# isso melhor que qualquer atraso.
	var outro := d.multiplicar(
		d.multiplicar(d.biquad(d.ruido(dur), 1150.0, 0.6, "bp"), onda), tremor
	)
	d.escalar(outro, 0.55)
	var esquerda := misto.duplicate()
	d.somar(esquerda, outro, 0, 0.55 * 0.4)
	var direita := d.escalar(misto, 0.92)
	d.somar(direita, outro, 0, 0.55 * 0.7)
	return [d.reverb(esquerda, 0.8, 0.22), d.reverb(direita, 0.8, 0.22)]

## TORCIDA DE ESTÁDIO para a cerimônia do ranking.
##
## Combina massa vocal, canto grave, palmas, assobios e a cauda longa do
## ginásio. As quatro colocações usam durações e densidades diferentes;
## não são o mesmo arquivo apenas tocado mais baixo — quem chega em
## primeiro tem de OUVIR que chegou em primeiro.
func torcida_estadio(dur: float, intensidade: float) -> Array:
	var n := d.n_amostras(dur)
	var onda := PackedFloat32Array()
	var modulacao := PackedFloat32Array()
	var pulso := PackedFloat32Array()
	onda.resize(n)
	modulacao.resize(n)
	pulso.resize(n)
	for i in range(n):
		var t := float(i) / float(EstudioDSP.RATE)
		var entrada := clampf(1.0 - exp(-t * (9.0 + intensidade * 3.0)), 0.0, 1.0)
		var saindo := exp(-maxf(0.0, t - dur * 0.68) * (1.0 + 0.45 / intensidade))
		onda[i] = entrada * saindo
		modulacao[i] = 1.0 + 0.16 * sin(TAU * 2.7 * t) + 0.10 * sin(TAU * 4.3 * t + 0.8)
		pulso[i] = pow(clampf(sin(TAU * 1.65 * t), 0.0, 1.0), 0.55)

	# Milhares de vozes viram bandas largas; duas fontes independentes dão
	# largura real, sem copiar o mesmo ruído nos dois canais.
	var massa_l := d.biquad(d.ruido(dur), 620.0, 0.45, "bp")
	d.somar(massa_l, d.biquad(d.ruido(dur), 1280.0, 0.65, "bp"), 0, 0.72)
	d.somar(massa_l, d.biquad(d.ruido(dur), 2350.0, 0.90, "bp"), 0, 0.32)
	var massa_r := d.biquad(d.ruido(dur), 710.0, 0.48, "bp")
	d.somar(massa_r, d.biquad(d.ruido(dur), 1460.0, 0.70, "bp"), 0, 0.68)
	d.somar(massa_r, d.biquad(d.ruido(dur), 2700.0, 1.00, "bp"), 0, 0.28)
	var voz_do_lado := 0.55 + intensidade * 0.28
	var esquerda := d.escalar(d.multiplicar(d.multiplicar(massa_l, onda), modulacao), voz_do_lado)
	var direita := d.escalar(
		d.multiplicar(d.multiplicar(massa_r, onda), d.rolar(modulacao, 117)), voz_do_lado
	)

	# CANTO COLETIVO "Ô-Ô": não forma uma palavra, mas dá à massa a
	# identidade de arquibancada que ruído filtrado sozinho não tem.
	var canto := d.zeros(dur)
	for v in range(18 + int(22.0 * intensidade)):
		var fundamental := d.entre(145.0, 235.0)
		var fase := d.entre(0.0, TAU)
		var voz := d.senoide(fundamental, dur, fase)
		d.somar(voz, d.senoide(fundamental * 2.02, dur, fase * 0.7), 0, 0.38)
		d.somar(canto, voz, 0, d.entre(0.018, 0.040))
	for i in range(n):
		canto[i] *= onda[i] * (0.35 + pulso[i] * 0.65) * intensidade
	d.somar(esquerda, canto, 0, 0.78)
	d.somar(direita, d.rolar(canto, 71), 0, 0.74)

	# Palmas densas e curtas. A posição estéreo de cada grupo varia.
	var palmas_l := d.zeros(dur)
	var palmas_r := d.zeros(dur)
	for p in range(int((85.0 + dur * 52.0) * intensidade)):
		var quando := d.n_amostras(d.entre(0.18, maxf(0.19, dur - 0.08)))
		var estalo := d.multiplicar(
			d.biquad(d.ruido(0.014), d.entre(1700.0, 3900.0), 1.25, "bp"),
			d.env_ad(0.014, 0.0004, 0.012, 2.8)
		)
		var panorama := d.entre(0.08, 0.92)
		var ganho := d.entre(0.20, 0.62)
		d.somar(palmas_l, estalo, quando, ganho * (1.0 - panorama))
		d.somar(palmas_r, estalo, quando, ganho * panorama)
	d.somar(esquerda, d.multiplicar(palmas_l, onda), 0, 1.0)
	d.somar(direita, d.multiplicar(palmas_r, onda), 0, 1.0)

	# ASSOBIOS aparecem só nas festas maiores e sobem como grito de gol.
	#
	# E aqui o mesmo defeito custava mais do que em `corpo`: sem o
	# oscilador, cada "assobio" era uma rampa de valores entre 1.700 e
	# 3.600. Medido, isso levava o sinal que entra na reverberação de 0,3
	# para 40 de RMS — cento e trinta e cinco vezes acima do pretendido —
	# e a saturação que vem depois passava a ceifar a torcida inteira. As
	# quatro festas do ranking eram, na prática, ruído ceifado por um
	# artefato, e não a plateia que a receita descreve.
	for a in range(int(2.0 + intensidade * 5.0)):
		var inicio := d.entre(0.12, maxf(0.13, dur * 0.56))
		var quanto := d.entre(0.28, 0.72)
		var apito := d.multiplicar(
			d.senoide_curva(d.varredura(d.entre(1700.0, 2400.0), d.entre(2500.0, 3600.0), quanto, 1.2)),
			d.env_ad(quanto, 0.025, quanto * 0.82, 1.5)
		)
		d.escalar(apito, 0.055 * intensidade)
		var pos := d.n_amostras(inicio)
		var forte := 0.055 * intensidade
		if d.entre(0.0, 1.0) < 0.5:
			d.somar(esquerda, apito, pos, forte)
			d.somar(direita, apito, pos, forte * 0.28)
		else:
			d.somar(esquerda, apito, pos, forte * 0.28)
			d.somar(direita, apito, pos, forte)

	return [
		d.satura(d.reverb(esquerda, 0.90, 0.30), 1.35),
		d.satura(d.reverb(direita, 0.90, 0.30), 1.35),
	]

## Murmúrio, vaias curtas e assobios DESCENDENTES para golpe fraco.
## Descendentes de propósito: subir é festa, descer é decepção, e é essa
## direção que o ouvido lê antes de qualquer outra coisa.
func torcida_desdenho() -> Array:
	var dur := 2.15
	var n := d.n_amostras(dur)
	var env := PackedFloat32Array()
	env.resize(n)
	for i in range(n):
		var t := float(i) / float(EstudioDSP.RATE)
		env[i] = clampf(t * 9.0, 0.0, 1.0) * exp(-maxf(0.0, t - 0.72) * 1.35)
	var massa_l := d.escalar(d.multiplicar(d.biquad(d.ruido(dur), 720.0, 0.55, "bp"), env), 0.50)
	var massa_r := d.escalar(d.multiplicar(d.biquad(d.ruido(dur), 890.0, 0.62, "bp"), env), 0.47)
	# Pulsos graves imitam o "ôôô" de desaprovação sem sintetizar fala.
	var vaias := d.zeros(dur)
	for freq in [132.0, 151.0, 178.0, 204.0]:
		d.somar(vaias, d.senoide(float(freq), dur, d.entre(0.0, TAU)), 0, 0.055)
	for i in range(n):
		var t2 := float(i) / float(EstudioDSP.RATE)
		vaias[i] *= env[i] * (0.72 + 0.28 * sin(TAU * 3.1 * t2))
	d.somar(massa_l, vaias, 0, 1.0)
	d.somar(massa_r, d.rolar(vaias, 83), 0, 0.92)
	for i in range(4):
		var inicio := 0.18 + float(i) * 0.31 + d.entre(-0.05, 0.05)
		var apito := d.multiplicar(
			d.senoide_curva(d.varredura(d.entre(2700.0, 3400.0), d.entre(1500.0, 2100.0), 0.34, 1.1)),
			d.env_ad(0.34, 0.018, 0.28, 1.8)
		)
		var pos := d.n_amostras(inicio)
		if i % 2 == 0:
			d.somar(massa_l, apito, pos, 0.05)
			d.somar(massa_r, apito, pos, 0.05 * 0.24)
		else:
			d.somar(massa_l, apito, pos, 0.05 * 0.24)
			d.somar(massa_r, apito, pos, 0.05)
	return [d.reverb(massa_l, 0.84, 0.26), d.reverb(massa_r, 0.84, 0.26)]
