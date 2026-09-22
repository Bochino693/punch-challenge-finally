class_name EstudioArcade
extends RefCounted

## OS INSTRUMENTOS E AS RECEITAS DO BANCO DE ÁUDIO.
##
## A regra que governa esta página inteira: DOIS SONS NÃO PODEM SOAR
## PARECIDOS. Cada nível muda de FAMÍLIA, e não só de volume — seco,
## couro, metal, estouro, sirene, fanfarra, coro. Quem joga duas vezes
## seguidas percebe volume repetido na hora; timbre diferente ele sente
## antes de conseguir explicar.
##
## Cada som é montado em camadas, do jeito que um sound designer monta:
##
##     transiente  →  clique curtíssimo, ruído filtrado no agudo
##     corpo       →  a parte afinada, que dá a nota
##     grave       →  senóide varrendo para baixo, que dá o peso
##     cauda       →  reverberação curta, que dá o tamanho da sala
##
## A primeira versão do banco era meia dúzia de senóides com decaimento
## exponencial por cima. Isso não é som de fliperama, é bipe de relógio:
## falta o transiente (o estalo dos primeiros milissegundos, que é o que
## o ouvido usa para julgar "forte"), falta grave (o corpo que se sente
## no peito), falta ruído (nenhuma percussão real é periódica) e falta
## espaço (tudo soa colado no alto-falante).

var d: EstudioDSP
var pasta: String

func _init(dsp: EstudioDSP, destino: String) -> void:
	d = dsp
	pasta = destino

# ====================================================================
# INSTRUMENTOS
# ====================================================================

func bumbo(segundos := 0.42, f0 := 165.0, f1 := 44.0) -> PackedFloat32Array:
	var corpo := d.multiplicar(
		d.senoide_curva(d.varredura(f0, f1, segundos, 6.0)),
		d.env_ad(segundos, 0.001, 0.11, 4.0)
	)
	var clique := d.multiplicar(
		d.biquad(d.ruido(0.012), 2600.0, 0.9, "hp"), d.env_ad(0.012, 0.0002, 0.004, 6.0)
	)
	d.somar(corpo, clique, 0, 0.35)
	return d.satura(corpo, 1.9)

func caixa(segundos := 0.26) -> PackedFloat32Array:
	var cru := d.multiplicar(d.ruido(segundos), d.env_ad(segundos, 0.001, 0.055, 4.0))
	var corpo := d.escalar(d.biquad(cru, 1900.0, 0.8, "bp"), 1.4)
	d.somar(corpo, d.biquad(cru, 320.0, 1.2, "bp"), 0, 0.7)
	var afinado := d.multiplicar(
		d.senoide_curva(d.varredura(330.0, 180.0, segundos, 8.0)),
		d.env_ad(segundos, 0.001, 0.035, 5.0)
	)
	var soma := d.escalar(corpo, 0.8)
	d.somar(soma, afinado, 0, 0.45)
	return d.satura(soma, 1.6)

func chimbal(segundos := 0.055, aberto := false) -> PackedFloat32Array:
	var dur := 0.24 if aberto else segundos
	var x := d.biquad(d.ruido(dur), 8200.0, 0.7, "hp")
	return d.escalar(d.multiplicar(x, d.env_ad(dur, 0.0005, 0.05 if aberto else 0.012, 5.0)), 0.6)

func prato(segundos := 1.4) -> PackedFloat32Array:
	var x := d.biquad(d.ruido(segundos), 6000.0, 0.5, "hp")
	return d.escalar(d.multiplicar(x, d.env_ad(segundos, 0.002, 0.45, 3.0)), 0.5)

## `forma` é "quadrada" ou "dente" — a mesma escolha que o gerador
## anterior fazia passando a função adiante.
func blip(midi: float, segundos: float, forma := "quadrada", queda := 0.05) -> PackedFloat32Array:
	var onda := (
		d.dente(d.nota(midi), segundos) if forma == "dente"
		else d.quadrada(d.nota(midi), segundos)
	)
	return d.multiplicar(onda, d.env_ad(segundos, 0.002, queda, 3.5))

## O SOCO. Quatro camadas, e é a soma delas que soa caro.
func impacto(segundos := 0.75, peso := 1.0) -> PackedFloat32Array:
	var grave := d.multiplicar(
		d.senoide_curva(d.varredura(150.0 * peso, 38.0, segundos, 7.0)),
		d.env_ad(segundos, 0.001, 0.13, 3.5)
	)
	var estalo := d.multiplicar(
		d.biquad(d.ruido(0.03), 3200.0, 0.8, "hp"), d.env_ad(0.03, 0.0002, 0.008, 6.0)
	)
	var couro := d.multiplicar(
		d.biquad(d.ruido(segundos), 900.0, 1.1, "bp"), d.env_ad(segundos, 0.001, 0.06, 4.0)
	)
	var metal := d.multiplicar(
		d.senoide_curva(d.varredura(520.0, 210.0, 0.25, 9.0)), d.env_ad(0.25, 0.001, 0.05, 4.0)
	)
	d.somar(grave, estalo, 0, 0.75)
	d.somar(grave, couro, 0, 0.6)
	d.somar(grave, metal, 0, 0.30)
	return d.satura(grave, 2.4)

## RISER: ruído filtrado subindo. É o som que promete que algo vem.
func subida(segundos: float, f0 := 180.0, f1 := 2400.0) -> PackedFloat32Array:
	var n := d.n_amostras(segundos)
	var x := d.ruido(segundos)
	var passo := maxi(1, n / 40)
	var saida := PackedFloat32Array()
	saida.resize(n)
	for i in range(40):
		var inicio := i * passo
		if inicio >= n:
			break
		var fim := mini((i + 1) * passo, n)
		var corte := f0 * pow(f1 / f0, float(i) / 39.0)
		var fatia := x.slice(inicio, fim)
		var filtrada := d.biquad(fatia, corte, 2.2, "bp")
		for k in range(filtrada.size()):
			saida[inicio + k] = filtrada[k]
	for i in range(n):
		saida[i] *= pow(lerpf(0.15, 1.0, float(i) / float(maxi(n - 1, 1))), 1.6)
	return saida

func arpejo(midis: Array, segundos_por_nota: float, forma := "quadrada", cauda := 0.28) -> PackedFloat32Array:
	var total := float(midis.size()) * segundos_por_nota + cauda
	var saida := d.zeros(total)
	for i in range(midis.size()):
		var voz := blip(float(midis[i]), segundos_por_nota + cauda, forma, cauda * 0.55)
		d.somar(saida, voz, d.n_amostras(float(i) * segundos_por_nota), 0.5)
	return saida

# ====================================================================
# EFEITOS
# ====================================================================

func gerar_efeitos() -> void:
	# --- o soco: o som mais importante do jogo
	var par := d.largura(d.reverb(impacto(0.85, 1.0), 0.55, 0.30), 9.0, 0.8)
	d.salvar(pasta, "hit", par[0], par[1])

	# --- contagem: blip curto e seco, com peso
	var conta := d.escalar(blip(88, 0.16, "quadrada", 0.035), 0.9)
	d.somar(conta, d.multiplicar(
		d.senoide_curva(d.varredura(700.0, 480.0, 0.1, 8.0)), d.env_ad(0.1, 0.001, 0.03, 4.0)
	), 0, 0.5)
	d.salvar(pasta, "count", d.satura(conta, 1.5))

	# --- GO: riser curto terminando num impacto
	var vai := d.zeros(0.9)
	d.somar(vai, subida(0.42, 220.0, 3000.0), 0, 0.8)
	d.somar(vai, impacto(0.6, 0.8), d.n_amostras(0.40), 1.0)
	d.somar(vai, prato(0.8), d.n_amostras(0.40), 0.5)
	par = d.largura(d.reverb(vai, 0.5, 0.25), 11.0)
	d.salvar(pasta, "go", par[0], par[1])

	# --- start: fanfarra curta ascendente + bumbo
	var ini := arpejo([57, 64, 69, 76], 0.085, "quadrada", 0.34)
	d.somar(ini, bumbo(0.4), 0, 0.9)
	d.somar(ini, prato(1.0), d.n_amostras(0.255), 0.45)
	par = d.largura(d.reverb(ini, 0.45, 0.22), 13.0)
	d.salvar(pasta, "start", par[0], par[1])

	# --- crédito: duas moedas metálicas (FM curta)
	var moeda := d.zeros(0.5)
	var midis_da_moeda := [93, 100]
	for i in range(midis_da_moeda.size()):
		var f := d.nota(float(midis_da_moeda[i]))
		var n := d.n_amostras(0.24)
		var voz := PackedFloat32Array()
		voz.resize(n)
		for k in range(n):
			var t := float(k) / float(EstudioDSP.RATE)
			voz[k] = sin(TAU * f * t + 3.4 * sin(TAU * f * 2.76 * t) * exp(-24.0 * t))
		d.somar(moeda, d.multiplicar(voz, d.env_ad(0.24, 0.0008, 0.06, 4.0)),
			d.n_amostras(float(i) * 0.085), 0.55)
	par = d.largura(d.reverb(moeda, 0.35, 0.2), 8.0)
	d.salvar(pasta, "credit", par[0], par[1])

	# --- menu: tique curtíssimo
	d.salvar(pasta, "menu", d.satura(blip(84, 0.06, "quadrada", 0.014), 1.3))

	# --- erro: zumbido descendente e sujo
	var erro := d.multiplicar(
		d.dente_curva(d.varredura(240.0, 90.0, 0.45, 5.0)), d.env_ad(0.45, 0.002, 0.13, 3.0)
	)
	d.salvar(pasta, "error", d.satura(erro, 3.2))

	# --- médio / vitória / lendário: a mesma família, subindo de porte
	var medio := arpejo([64, 71, 76], 0.10, "quadrada", 0.36)
	d.somar(medio, bumbo(0.35), 0, 0.6)
	par = d.largura(d.reverb(medio, 0.45, 0.24), 12.0)
	d.salvar(pasta, "medium", par[0], par[1])

	var venceu := arpejo([69, 73, 76, 81], 0.095, "quadrada", 0.5)
	d.somar(venceu, bumbo(0.45), 0, 0.8)
	d.somar(venceu, prato(1.2), d.n_amostras(0.285), 0.5)
	par = d.largura(d.reverb(venceu, 0.6, 0.3), 14.0)
	d.salvar(pasta, "win", par[0], par[1])

	var lenda := d.zeros(2.6)
	d.somar(lenda, subida(0.5, 300.0, 3600.0), 0, 0.5)
	var midis_da_lenda := [57, 64, 69, 73, 76, 81, 88]
	for i in range(midis_da_lenda.size()):
		var m := float(midis_da_lenda[i])
		var voz2 := blip(m, 0.9, "dente", 0.35)
		d.somar(voz2, blip(m + 12.0, 0.9, "quadrada", 0.3), 0, 0.4)
		d.somar(lenda, voz2, d.n_amostras(0.5 + float(i) * 0.075), 0.42)
	d.somar(lenda, impacto(1.0, 1.1), d.n_amostras(0.5), 0.9)
	d.somar(lenda, prato(1.6), d.n_amostras(0.5), 0.6)
	par = d.largura(d.reverb(lenda, 0.75, 0.34), 16.0)
	d.salvar(pasta, "legendary", par[0], par[1])

	# --- derrota: descida curta e abafada
	var perdeu := d.biquad(arpejo([64, 59, 52], 0.14, "dente", 0.4), 1400.0, 0.7, "lp")
	par = d.largura(d.reverb(perdeu, 0.4, 0.2), 10.0)
	d.salvar(pasta, "lose", par[0], par[1])

	# --- recorde: brilho subindo, sem peso grave (o peso já veio do hit)
	var rec := d.zeros(2.0)
	var midis_do_recorde := [81, 85, 88, 93, 96, 100]
	for i in range(midis_do_recorde.size()):
		d.somar(rec, blip(float(midis_do_recorde[i]), 0.7, "quadrada", 0.26),
			d.n_amostras(float(i) * 0.085), 0.4)
	d.somar(rec, prato(1.4), 0, 0.45)
	par = d.largura(d.reverb(rec, 0.7, 0.34), 15.0)
	d.salvar(pasta, "record", par[0], par[1])

	# --- ranking: varredura entrando na lista
	var rank := d.zeros(1.5)
	d.somar(rank, subida(0.45, 400.0, 5200.0), 0, 0.55)
	var midis_do_rank := [76, 81, 85, 88]
	for i in range(midis_do_rank.size()):
		d.somar(rank, blip(float(midis_do_rank[i]), 0.55, "quadrada", 0.2),
			d.n_amostras(0.42 + float(i) * 0.075), 0.42)
	par = d.largura(d.reverb(rank, 0.55, 0.28), 13.0)
	d.salvar(pasta, "ranking", par[0], par[1])

	# --- obturador: mecânico, dois estalos e uma mola
	var obt := d.zeros(0.3)
	for dupla in [[0.0, 1.0], [0.055, 0.7]]:
		d.somar(obt, d.multiplicar(
			d.biquad(d.ruido(0.018), 3600.0, 1.1, "hp"), d.env_ad(0.018, 0.0002, 0.004, 7.0)
		), d.n_amostras(float(dupla[0])), float(dupla[1]))
	d.somar(obt, d.multiplicar(
		d.biquad(d.ruido(0.12), 5200.0, 3.0, "bp"), d.env_ad(0.12, 0.001, 0.03, 5.0)
	), d.n_amostras(0.012), 0.35)
	d.salvar(pasta, "shutter", d.satura(obt, 1.4))

# ====================================================================
# OS OITO NÍVEIS
# ====================================================================

func gerar_niveis() -> void:
	# 1) IMPACTO LEVE — seco, curto, sem grave e sem cauda.
	var leve := d.zeros(0.34)
	d.somar(leve, d.multiplicar(
		d.biquad(d.ruido(0.05), 1800.0, 1.0, "bp"), d.env_ad(0.05, 0.001, 0.03, 6.0)
	), 0, 0.8)
	d.somar(leve, blip(69, 0.10, "quadrada", 0.03), d.n_amostras(0.02), 0.35)
	d.salvar(pasta, "nivel_leve", d.satura(leve, 1.2), PackedFloat32Array(), false, 0.10)

	# 2) BOM GOLPE — couro: ruído grave abafado com um corpo de seno.
	var bom := d.zeros(0.7)
	d.somar(bom, d.multiplicar(
		d.biquad(d.ruido(0.22), 620.0, 0.8, "lp"), d.env_ad(0.22, 0.002, 0.09, 3.5)
	), 0, 1.0)
	d.somar(bom, d.multiplicar(
		d.senoide_curva(d.varredura(150.0, 62.0, 0.25, 3.0)), d.env_ad(0.25, 0.002, 0.1, 3.0)
	), 0, 0.7)
	d.somar(bom, arpejo([64, 71], 0.09, "quadrada", 0.22), d.n_amostras(0.12), 0.35)
	var par := d.largura(d.reverb(bom, 0.35, 0.16), 9.0)
	d.salvar(pasta, "nivel_bom", par[0], par[1], false, 0.13)

	# 3) GOLPE FORTE — metal: bumbo encorpado, acorde de serra e prato.
	var forte := d.zeros(1.2)
	d.somar(forte, bumbo(0.5, 190.0, 46.0), 0, 1.0)
	for m in [52, 59, 64]:
		d.somar(forte, blip(float(m), 0.55, "dente", 0.22), d.n_amostras(0.04), 0.30)
	d.somar(forte, prato(0.9), d.n_amostras(0.04), 0.40)
	d.somar(forte, d.multiplicar(
		d.senoide_curva(d.varredura(90.0, 40.0, 0.5, 3.0)), d.env_ad(0.5, 0.003, 0.2, 2.5)
	), 0, 0.6)
	par = d.largura(d.reverb(forte, 0.5, 0.24), 12.0)
	d.salvar(pasta, "nivel_forte", par[0], par[1], false, 0.15)

	# 4) EXPLOSIVO — estouro: clarão de ruído agudo mais subgrave caindo.
	var expl := d.zeros(1.4)
	d.somar(expl, d.multiplicar(
		d.biquad(d.ruido(0.35), 2600.0, 0.7, "hp"), d.env_ad(0.35, 0.0004, 0.10, 5.0)
	), 0, 0.9)
	d.somar(expl, d.multiplicar(
		d.senoide_curva(d.varredura(120.0, 30.0, 0.9, 4.0)), d.env_ad(0.9, 0.002, 0.45, 2.0)
	), 0, 1.0)
	d.somar(expl, impacto(0.7, 1.0), 0, 0.8)
	d.somar(expl, impacto(0.5, 0.7), d.n_amostras(0.16), 0.5)
	par = d.largura(d.reverb(expl, 0.6, 0.30), 13.0)
	d.salvar(pasta, "nivel_explosivo", par[0], par[1], false, 0.16)

	# 5) NOCAUTE — sirene curta de ringue e três marteladas.
	var noc := d.zeros(1.8)
	var sirene := d.senoide_curva(d.varredura(760.0, 1250.0, 0.5, 1.0))
	d.somar(noc, d.multiplicar(sirene, d.env_ad(0.5, 0.02, 0.25, 2.0)), d.n_amostras(0.30), 0.45)
	var posicoes := [0.0, 0.19, 0.38]
	for i in range(posicoes.size()):
		d.somar(noc, impacto(0.8, 1.1 - float(i) * 0.12),
			d.n_amostras(float(posicoes[i])), 1.0 - float(i) * 0.18)
	d.somar(noc, prato(1.3), d.n_amostras(0.38), 0.5)
	par = d.largura(d.reverb(noc, 0.68, 0.32), 15.0)
	d.salvar(pasta, "nivel_nocaute", par[0], par[1], false, 0.17)

	# 6) PESO-PESADO — fanfarra: tríade subindo em serra, sub e rufo.
	var peso := d.zeros(2.4)
	d.somar(peso, subida(0.42, 240.0, 2600.0), 0, 0.55)
	var midis_do_peso := [52, 59, 64, 71]
	for i in range(midis_do_peso.size()):
		var m2 := float(midis_do_peso[i])
		var voz := blip(m2, 0.95, "dente", 0.34)
		d.somar(voz, blip(m2 + 12.0, 0.95, "quadrada", 0.28), 0, 0.35)
		d.somar(peso, voz, d.n_amostras(0.42 + float(i) * 0.11), 0.42)
	d.somar(peso, impacto(1.1, 1.15), d.n_amostras(0.42), 0.95)
	for i in range(6):
		d.somar(peso, bumbo(0.26, 150.0, 48.0),
			d.n_amostras(0.9 + float(i) * 0.075), 0.30 + float(i) * 0.05)
	d.somar(peso, prato(1.6), d.n_amostras(0.42), 0.55)
	par = d.largura(d.reverb(peso, 0.72, 0.34), 16.0)
	d.salvar(pasta, "nivel_peso", par[0], par[1], false, 0.18)

	# 7) LENDÁRIO — vitória inteira: riser, arpejo longo e cauda grande.
	var lend := d.zeros(3.0)
	d.somar(lend, subida(0.55, 300.0, 3800.0), 0, 0.55)
	var midis_lendarios := [57, 64, 69, 73, 76, 81, 88, 93]
	for i in range(midis_lendarios.size()):
		var m3 := float(midis_lendarios[i])
		var voz3 := blip(m3, 1.1, "dente", 0.38)
		d.somar(voz3, blip(m3 + 12.0, 1.1, "quadrada", 0.32), 0, 0.42)
		d.somar(lend, voz3, d.n_amostras(0.55 + float(i) * 0.08), 0.40)
	d.somar(lend, impacto(1.2, 1.2), d.n_amostras(0.55), 0.95)
	d.somar(lend, prato(1.9), d.n_amostras(0.55), 0.62)
	for i in range(4):
		d.somar(lend, caixa(0.22), d.n_amostras(1.5 + float(i) * 0.13), 0.30)
	par = d.largura(d.reverb(lend, 0.82, 0.38), 18.0)
	d.salvar(pasta, "nivel_lendario", par[0], par[1], false, 0.185)

	# 8) SOCO PERFEITO — coro: vozes empilhadas com ataque lento, gongo e
	#    a maior cauda do jogo. É a única vez que a máquina faz isso.
	var perf := d.zeros(4.0)
	d.somar(perf, subida(0.7, 200.0, 5200.0), 0, 0.6)
	var coro := d.zeros(3.0)
	var envelope_do_coro := d.env_ad(3.0, 0.25, 2.0, 1.6)
	for m4 in [45, 52, 57, 64, 69, 76, 81]:
		var f := d.nota(float(m4))
		# TRÊS VOZES LEVEMENTE DESAFINADAS POR NOTA: é a desafinação
		# pequena que faz um seno virar coro em vez de apito.
		for det in [-0.4, 0.0, 0.4]:
			var v := d.senoide(f * pow(2.0, det / 1200.0 * 10.0), 3.0)
			d.somar(coro, d.multiplicar(v, envelope_do_coro), 0, 0.085)
	d.somar(perf, d.biquad(coro, 5200.0, 0.7, "lp"), d.n_amostras(0.7), 1.0)
	d.somar(perf, impacto(1.4, 1.3), d.n_amostras(0.7), 1.0)
	d.somar(perf, prato(2.4), d.n_amostras(0.7), 0.7)
	d.somar(perf, d.multiplicar(
		d.senoide_curva(d.varredura(70.0, 26.0, 1.6, 3.0)), d.env_ad(1.6, 0.004, 0.9, 1.8)
	), d.n_amostras(0.7), 0.9)
	par = d.largura(d.reverb(perf, 0.9, 0.42), 22.0)
	d.salvar(pasta, "nivel_perfeito", par[0], par[1], false, 0.19)

# ====================================================================
# OS AVISOS DE OPERAÇÃO
# ====================================================================

func gerar_avisos() -> void:
	# START SEM CRÉDITO: dois zumbidos graves descendo, secos. Precisa
	# soar NEGADO e não quebrado — quem ouve tem de entender que faltou
	# ficha, não que a máquina pifou.
	var negado := d.zeros(0.55)
	var pos_do_negado := [0.0, 0.17]
	for i in range(pos_do_negado.size()):
		var z := d.biquad(d.dente(d.nota(45.0 - float(i) * 3.0), 0.13), 900.0, 1.2, "lp")
		d.somar(negado, d.multiplicar(z, d.env_ad(0.13, 0.004, 0.05, 3.0)),
			d.n_amostras(float(pos_do_negado[i])), 0.9)
	d.salvar(pasta, "start_negado", d.satura(negado, 1.6), PackedFloat32Array(), false, 0.12)

	# SENSOR ARMADO: duas notas curtas subindo e um chiado leve. Diz
	# "pode vir" sem parecer contagem.
	var armado := d.zeros(0.6)
	d.somar(armado, blip(76, 0.10, "quadrada", 0.03), 0, 0.7)
	d.somar(armado, blip(83, 0.14, "quadrada", 0.04), d.n_amostras(0.10), 0.75)
	d.somar(armado, d.multiplicar(
		d.biquad(d.ruido(0.25), 3800.0, 0.9, "hp"), d.env_ad(0.25, 0.02, 0.12, 3.0)
	), d.n_amostras(0.10), 0.22)
	var par := d.largura(d.reverb(armado, 0.35, 0.18), 10.0)
	d.salvar(pasta, "armado", par[0], par[1], false, 0.11)

	# COURO DO SACO: o baque do material, sem nota nenhuma.
	var couro := d.multiplicar(
		d.biquad(d.ruido(0.3), 520.0, 0.7, "lp"), d.env_ad(0.3, 0.0015, 0.12, 3.2)
	)
	d.somar(couro, d.multiplicar(
		d.senoide_curva(d.varredura(120.0, 55.0, 0.3, 3.0)), d.env_ad(0.3, 0.002, 0.12, 3.0)
	), 0, 0.6)
	d.salvar(pasta, "couro", d.satura(couro, 1.4), PackedFloat32Array(), false, 0.13)

	# SUBGRAVE DO IMPACTO: só o chão tremendo, para somar por baixo dos
	# níveis altos sem disputar o agudo com eles.
	var sub := d.multiplicar(
		d.senoide_curva(d.varredura(78.0, 27.0, 1.1, 3.2)), d.env_ad(1.1, 0.003, 0.6, 1.9)
	)
	sub = d.biquad(sub, 160.0, 0.7, "lp")
	d.salvar(pasta, "subgrave", d.satura(sub, 1.2), PackedFloat32Array(), false, 0.15)

# ====================================================================
# LOOPS
# ====================================================================

func gerar_loops() -> void:
	# --- carga: serra grave subindo, com tremolo. Emenda exata em 1 s.
	#
	# AS DUAS FREQUÊNCIAS PRECISAM FECHAR CICLO INTEIRO EM UM SEGUNDO. A
	# versão anterior desafinava a segunda serra em 110,5 Hz: meio ciclo
	# sobrando na emenda, e o loop estalava a cada volta.
	#
	# E O FILTRO PRECISA ENTRAR AQUECIDO. Um biquad começa com estado
	# zerado, então os primeiros milissegundos saem abafados enquanto o
	# fim do loop já está em regime — o degrau entre os dois é outro
	# clique. Filtrando DOIS períodos e ficando com o segundo, o trecho
	# gravado é todo regime permanente.
	var dur := 1.0
	var n := d.n_amostras(dur)
	var base2 := d.dente(110.0, dur * 2.0)
	d.somar(base2, d.dente(111.0, dur * 2.0), 0, 0.6)
	var fechado := d.biquad(base2, 480.0, 2.6, "lp").slice(n)
	var aberto := d.biquad(base2, 2300.0, 2.6, "lp").slice(n)
	var filtrado := PackedFloat32Array()
	filtrado.resize(n)
	for i in range(n):
		var t := float(i) / float(EstudioDSP.RATE)
		var mistura := 0.5 + 0.5 * sin(TAU * 1.0 * t - PI * 0.5)
		var tremolo := 0.72 + 0.28 * sin(TAU * 8.0 * t)
		filtrado[i] = (fechado[i] * (1.0 - mistura) + aberto[i] * mistura) * tremolo
	d.salvar(pasta, "charge", d.satura(filtrado, 1.8),
		d.satura(d.rolar(filtrado, d.n_amostras(0.004)), 1.8), true, 0.12)

	# --- contagem do placar: tique rápido. O jogo ainda muda o tom.
	var dur_do_tique := 0.5
	var tick := d.zeros(dur_do_tique)
	for i in range(8):
		d.somar(tick, blip(96, 0.06, "quadrada", 0.012),
			d.n_amostras(float(i) * dur_do_tique / 8.0), 0.7, true)
	d.salvar(pasta, "score_loop", tick, d.rolar(tick, d.n_amostras(0.003)), true, 0.11)

	gerar_musica()

## TEMA DA ABERTURA: 8 compassos em 150 BPM, lá menor.
##
## Loop de verdade, e não uma sequência que reinicia: as caudas que
## passam do fim voltam para o começo, então a emenda não estala. É o que
## separa uma trilha que a pessoa ouve o dia inteiro de uma que irrita
## depois da terceira volta.
func gerar_musica() -> void:
	var batida := 60.0 / 150.0
	var compassos := 8
	var dur := float(compassos) * 4.0 * batida
	var esq := d.zeros(dur)
	var dir := d.zeros(dur)

	# Progressão i - VI - III - VII, dois compassos cada: a mais direta
	# que existe para soar grande sem exigir atenção.
	var acordes := [
		[45, [57, 60, 64]],   # Am
		[41, [57, 60, 65]],   # F
		[48, [55, 60, 64]],   # C
		[43, [55, 59, 62]],   # G
	]

	for c in range(compassos):
		var acorde: Array = acordes[(c / 2) % 4]
		var raiz := float(acorde[0])
		var notas: Array = acorde[1]
		var base_c := float(c)

		# BATERIA: bumbo em todos os tempos, caixa em 2 e 4, chimbal nas
		# colcheias. É a fórmula que faz qualquer coisa andar.
		for b in range(4):
			var bd := bumbo(0.40)
			var onde := _pos(base_c + float(b) / 4.0, batida)
			d.somar(esq, bd, onde, 0.95, true)
			d.somar(dir, bd, onde, 0.95, true)
			if b == 1 or b == 3:
				var cx := caixa(0.28)
				d.somar(esq, cx, onde, 0.55, true)
				d.somar(dir, cx, onde, 0.55, true)
			for meia in [0.0, 0.5]:
				var ch := chimbal(0.05, b == 3 and meia == 0.5)
				# Chimbal alternando de lado: é o que dá largura sem
				# mexer no que precisa ficar no centro (bumbo e baixo).
				var forte := 0.38 if meia == 0.0 else 0.22
				var fraco := 0.22 if meia == 0.0 else 0.38
				var quando := _pos(base_c + (float(b) + meia) / 4.0, batida)
				d.somar(esq, ch, quando, forte, true)
				d.somar(dir, ch, quando, fraco, true)

		# Baixo: colcheias na tônica, com salto de oitava no fim do compasso.
		for oitavo in range(8):
			var m := raiz + (12.0 if oitavo >= 6 else 0.0)
			var voz := d.multiplicar(d.dente(d.nota(m), 0.24), d.env_ad(0.24, 0.002, 0.055, 3.5))
			voz = d.biquad(voz, 320.0, 1.1, "lp")
			var onde_b := _pos(base_c + float(oitavo) / 8.0, batida)
			d.somar(esq, voz, onde_b, 0.55, true)
			d.somar(dir, voz, onde_b, 0.55, true)

		# Arpejo em semicolcheias, alternando os lados: é ele que dá a
		# sensação de velocidade sem acelerar a batida.
		for s in range(16):
			var m2 := float(notas[s % notas.size()]) + (12.0 if (s / notas.size()) % 2 == 1 else 0.0)
			var voz2 := d.multiplicar(d.quadrada(d.nota(m2), 0.16), d.env_ad(0.16, 0.001, 0.035, 4.0))
			voz2 = d.biquad(voz2, 2600.0, 1.4, "lp")
			var ganho := 0.24 if s % 2 == 0 else 0.16
			var onde_a := _pos(base_c + float(s) / 16.0, batida)
			if s % 2 == 0:
				d.somar(esq, voz2, onde_a, ganho, true)
				d.somar(dir, voz2, onde_a, ganho * 0.18, true)
			else:
				d.somar(dir, voz2, onde_a, ganho, true)
				d.somar(esq, voz2, onde_a, ganho * 0.18, true)

		# Prato no começo de cada bloco de dois compassos.
		if c % 2 == 0:
			var pr := prato(1.3)
			d.somar(esq, pr, _pos(base_c, batida), 0.32, true)
			d.somar(dir, pr, _pos(base_c, batida), 0.32, true)

	# Melodia sobre a segunda metade: o "gancho" que faz lembrar do jogo.
	var gancho := [[0.0, 76], [0.5, 74], [1.0, 72], [1.75, 74], [2.0, 76], [3.0, 79], [3.5, 76]]
	for compasso_base in [4.0, 6.0]:
		for item in gancho:
			var voz3 := d.multiplicar(
				d.quadrada(d.nota(float(item[1])), 0.5), d.env_ad(0.5, 0.004, 0.16, 3.0)
			)
			voz3 = d.biquad(voz3, 3200.0, 1.0, "lp")
			# Gancho com atraso curto de um lado (efeito Haas): a melodia
			# deixa de sair de um ponto só e passa a envolver.
			var onde_m := _pos(float(compasso_base) + float(item[0]) / 4.0, batida)
			d.somar(esq, voz3, onde_m, 0.26, true)
			d.somar(dir, voz3, onde_m + d.n_amostras(0.011), 0.24, true)

	# Riser no último compasso, empurrando para a volta do loop.
	var riser := subida(batida * 4.0, 300.0, 4200.0)
	d.somar(esq, riser, _pos(float(compassos) - 1.0, batida), 0.28, true)
	d.somar(dir, riser, _pos(float(compassos) - 1.0, batida), 0.28, true)

	d.salvar(pasta, "music", d.satura(esq, 1.35), d.satura(dir, 1.35), true, 0.17)

func _pos(compasso: float, batida: float) -> int:
	return d.n_amostras(compasso * 4.0 * batida)
