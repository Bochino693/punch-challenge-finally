class_name EstudioDSP
extends RefCounted

## A MESA DE SOM DO JOGO, EM GDSCRIPT.
##
## POR QUE ISTO DEIXOU DE SER PYTHON. O banco de áudio inteiro era
## sintetizado por dois scripts em Python com NumPy. O jogo nunca
## precisou deles — os `.wav` viajam prontos no repositório —, mas o
## PROJETO precisava, e isso quer dizer que mexer num som do jogo exigia
## instalar uma linguagem e uma biblioteca de cálculo numérico. Numa
## máquina de salão isso não é uma dependência aceitável nem para quem
## opera nem para quem mantém.
##
## Aqui a mesma mesa roda dentro do Godot, sem nada instalado:
##
##     godot --headless --script tools/gerar_audio.gd
##
## O QUE MUDA NO RESULTADO: nada de estrutura, e tudo de ruído. As
## camadas afinadas — senóides, serras, varreduras, envelopes, filtros —
## são contas determinísticas e saem idênticas. As camadas de RUÍDO não:
## o gerador gaussiano do NumPy não é reproduzível fora do NumPy. Como
## ruído branco só tem estatística (média, desvio e espectro), e não
## forma, dois ruídos diferentes com a mesma estatística soam iguais —
## é por isso que `tools/conferir_audio.gd` compara duração, pico, RMS e
## centroide espectral, e não amostra por amostra.
##
## POR QUE SINTETIZAR EM VEZ DE BAIXAR, que é a razão original e continua
## valendo: uma máquina de salão toca os mesmos quinze sons mil vezes por
## dia, e qualquer amostra licenciada vira um problema de licença
## multiplicado por cada gabinete vendido. Sintetizado, o banco é do
## projeto e cabe no repositório.

const RATE := 44100

var _ruido := RandomNumberGenerator.new()
## Box–Muller entrega DUAS amostras gaussianas por vez; guardar a segunda
## corta metade das raízes e dos logaritmos.
var _gaussiana_guardada := 0.0
var _tem_guardada := false

func _init(semente := 8258) -> void:
	_ruido.seed = semente

# ====================================================================
# O BÁSICO
# ====================================================================

func n_amostras(segundos: float) -> int:
	return int(round(segundos * RATE))

func zeros(segundos: float) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(n_amostras(segundos))
	return v

## RUÍDO BRANCO GAUSSIANO, por Box–Muller.
##
## Gaussiano e não uniforme: a soma de muitas fontes independentes tende
## à gaussiana, e é por isso que ruído de verdade (ar, couro, plateia)
## tem essa distribuição. Ruído uniforme soa chapado e digital.
func ruido(segundos: float) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	var n := n_amostras(segundos)
	v.resize(n)
	for i in range(n):
		v[i] = _gaussiana()
	return v

func _gaussiana() -> float:
	if _tem_guardada:
		_tem_guardada = false
		return _gaussiana_guardada
	var u1 := maxf(_ruido.randf(), 1e-12)
	var u2 := _ruido.randf()
	var r := sqrt(-2.0 * log(u1))
	var a := TAU * u2
	_gaussiana_guardada = r * sin(a)
	_tem_guardada = true
	return r * cos(a)

## Um número aleatório do mesmo gerador, para posição de palma e afins.
func entre(a: float, b: float) -> float:
	return _ruido.randf_range(a, b)

# ====================================================================
# OSCILADORES
# ====================================================================

func senoide(freq: float, segundos: float, fase := 0.0) -> PackedFloat32Array:
	var n := n_amostras(segundos)
	var v := PackedFloat32Array()
	v.resize(n)
	var w := TAU * freq / float(RATE)
	for i in range(n):
		v[i] = sin(w * float(i) + fase)
	return v

## A MESMA COISA COM A FREQUÊNCIA VARIANDO A CADA AMOSTRA.
##
## A fase é a INTEGRAL da frequência, e não o produto dela pelo tempo.
## Multiplicar (o erro comum) dá um glissando com o dobro da inclinação
## pedida — sobe o dobro do que a receita diz.
func senoide_curva(freq: PackedFloat32Array, fase := 0.0) -> PackedFloat32Array:
	var n := freq.size()
	var v := PackedFloat32Array()
	v.resize(n)
	var soma := 0.0
	for i in range(n):
		soma += freq[i]
		v[i] = sin(TAU * soma / float(RATE) + fase)
	return v

## Serra por SOMA DE HARMÔNICOS, e não por rampa.
##
## Uma rampa de -1 a 1 tem harmônicos acima da metade da taxa de
## amostragem, que voltam dobrados para dentro do som como assobios que
## não pertencem a nota nenhuma. Somando só os harmônicos que cabem, não
## há alias nenhum.
func dente(freq: float, segundos: float, harmonicos := 14) -> PackedFloat32Array:
	var saida := zeros(segundos)
	for h in range(1, harmonicos + 1):
		var f := freq * float(h)
		if f > float(RATE) * 0.45:
			break
		_misturar(saida, senoide(f, segundos), 1.0 / float(h))
	_ganho(saida, 0.6)
	return saida

func dente_curva(freq: PackedFloat32Array, harmonicos := 14) -> PackedFloat32Array:
	var saida := PackedFloat32Array()
	saida.resize(freq.size())
	for h in range(1, harmonicos + 1):
		var f := _escalar(freq, float(h))
		if _maior(f) > float(RATE) * 0.45:
			break
		_misturar(saida, senoide_curva(f), 1.0 / float(h))
	_ganho(saida, 0.6)
	return saida

func quadrada(freq: float, segundos: float, harmonicos := 9) -> PackedFloat32Array:
	var saida := zeros(segundos)
	for h in range(1, harmonicos * 2, 2):
		var f := freq * float(h)
		if f > float(RATE) * 0.45:
			break
		_misturar(saida, senoide(f, segundos), 1.0 / float(h))
	_ganho(saida, 0.8)
	return saida

## A curva de frequência de f0 a f1. EXPONENCIAL, porque é assim que o
## ouvido percebe altura: uma rampa linear soa depressa no começo e
## parada no fim.
func varredura(f0: float, f1: float, segundos: float, curva := 3.0) -> PackedFloat32Array:
	var n := n_amostras(segundos)
	var v := PackedFloat32Array()
	v.resize(n)
	var razao := f1 / f0
	for i in range(n):
		var t := float(i) / float(maxi(n - 1, 1))
		v[i] = f0 * pow(razao, 1.0 - exp(-curva * t))
	return v

# ====================================================================
# ENVELOPE E FILTRO
# ====================================================================

## Envelope ataque-queda. O ataque curtíssimo é o que dá o ESTALO — é
## nos primeiros milissegundos que o ouvido decide se um som é forte.
func env_ad(segundos: float, ataque: float, queda: float, curva := 2.5) -> PackedFloat32Array:
	var n := n_amostras(segundos)
	var na := maxi(1, n_amostras(ataque))
	var v := PackedFloat32Array()
	v.resize(n)
	for i in range(mini(na, n)):
		v[i] = pow(float(i) / float(maxi(na - 1, 1)), 0.6)
	var resto := n - na
	if resto > 0 and queda > 0.0:
		var fim := segundos / queda
		for i in range(resto):
			v[na + i] = exp(-curva * fim * float(i) / float(maxi(resto - 1, 1)))
	elif resto > 0:
		for i in range(resto):
			v[na + i] = 1.0
	return v

## FILTRO RBJ DE SEGUNDA ORDEM. Um pólo só (média móvel) não tem
## inclinação suficiente para separar um chimbal de um estalo: os dois
## são ruído, e o que os distingue é EXATAMENTE a banda.
func biquad(x: PackedFloat32Array, freq: float, q: float, modo: String) -> PackedFloat32Array:
	var f := clampf(freq, 20.0, float(RATE) * 0.45)
	var w := TAU * f / float(RATE)
	var alfa := sin(w) / (2.0 * q)
	var cw := cos(w)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	match modo:
		"lp":
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = b0
		"hp":
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = b0
		_:
			b0 = alfa
			b1 = 0.0
			b2 = -alfa
	var a0 := 1.0 + alfa
	var a1 := -2.0 * cw
	var a2 := 1.0 - alfa
	b0 /= a0
	b1 /= a0
	b2 /= a0
	a1 /= a0
	a2 /= a0
	var n := x.size()
	var y := PackedFloat32Array()
	y.resize(n)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in range(n):
		var amostra := x[i]
		var saida := b0 * amostra + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = amostra
		y2 = y1
		y1 = saida
		y[i] = saida
	return y

## Saturação suave. É o que faz um som parecer ALTO sem subir o volume:
## os picos achatam e a energia média sobe. O mesmo truque de um disco
## masterizado.
func satura(x: PackedFloat32Array, forca := 2.5) -> PackedFloat32Array:
	var k := tanh(forca)
	var v := PackedFloat32Array()
	v.resize(x.size())
	for i in range(x.size()):
		v[i] = tanh(x[i] * forca) / k
	return v

## REVERBERAÇÃO DE SCHROEDER: quatro pentes em paralelo e dois passa-tudo
## em série. Barata e suficiente para dar tamanho de sala — e tamanho de
## sala é metade da diferença entre um efeito de 2026 e um bipe de 1985.
func reverb(x: PackedFloat32Array, tamanho := 0.5, mistura := 0.25) -> PackedFloat32Array:
	var cauda := n_amostras(0.6)
	var total := x.size() + cauda
	var entrada := PackedFloat32Array()
	entrada.resize(total)
	for i in range(x.size()):
		entrada[i] = x[i]
	var saida := PackedFloat32Array()
	saida.resize(total)
	var realim := 0.78 * tamanho + 0.14
	for atraso_s in [0.0297, 0.0371, 0.0411, 0.0437]:
		var d := n_amostras(atraso_s)
		var buf := PackedFloat32Array()
		buf.resize(total)
		for i in range(total):
			var anterior := buf[i - d] if i >= d else 0.0
			buf[i] = entrada[i] + anterior * realim
			saida[i] += buf[i] * 0.25
	for atraso_s in [0.005, 0.0017]:
		var d2 := n_amostras(atraso_s)
		var buf2 := PackedFloat32Array()
		buf2.resize(total)
		for i in range(total):
			var anterior_b := buf2[i - d2] if i >= d2 else 0.0
			var anterior_s := saida[i - d2] if i >= d2 else 0.0
			buf2[i] = -0.7 * saida[i] + anterior_b + 0.7 * anterior_s
		saida = buf2
	var fim := PackedFloat32Array()
	fim.resize(total)
	for i in range(total):
		var seco := x[i] if i < x.size() else 0.0
		fim[i] = seco * (1.0 - mistura) + saida[i] * mistura
	return fim

# ====================================================================
# MONTAGEM
# ====================================================================

## Mistura `trecho` em `destino` na posição dada.
##
## Com `circular`, o que passa do fim volta para o começo — é isso que
## faz a cauda de um prato atravessar a emenda de um loop sem o clique
## que denuncia repetição.
func somar(destino: PackedFloat32Array, trecho: PackedFloat32Array, posicao: int,
		ganho := 1.0, circular := false) -> void:
	var n := destino.size()
	if posicao >= n or posicao < -n:
		return
	for i in range(trecho.size()):
		var j := posicao + i
		if j >= n:
			if not circular:
				return
			j -= n
			if j >= n or j < 0:
				return
		destino[j] += trecho[i] * ganho

## Desloca o sinal em círculo, como o `roll` do NumPy: é o jeito barato
## de descorrelacionar os dois canais sem gerar outro ruído.
func rolar(x: PackedFloat32Array, passos: int) -> PackedFloat32Array:
	var n := x.size()
	if n == 0:
		return x
	var v := PackedFloat32Array()
	v.resize(n)
	for i in range(n):
		var j := (i + passos) % n
		if j < 0:
			j += n
		v[j] = x[i]
	return v

func multiplicar(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := mini(a.size(), b.size())
	var v := PackedFloat32Array()
	v.resize(n)
	for i in range(n):
		v[i] = a[i] * b[i]
	return v

func _misturar(destino: PackedFloat32Array, trecho: PackedFloat32Array, ganho: float) -> void:
	for i in range(mini(destino.size(), trecho.size())):
		destino[i] += trecho[i] * ganho

func _ganho(x: PackedFloat32Array, g: float) -> void:
	for i in range(x.size()):
		x[i] *= g

func escalar(x: PackedFloat32Array, g: float) -> PackedFloat32Array:
	return _escalar(x, g)

func _escalar(x: PackedFloat32Array, g: float) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(x.size())
	for i in range(x.size()):
		v[i] = x[i] * g
	return v

func _maior(x: PackedFloat32Array) -> float:
	var m := 0.0
	for i in range(x.size()):
		m = maxf(m, x[i])
	return m

## ESPALHA UM SOM MONO NO ESTÉREO com um atraso curto de um lado (o
## efeito Haas). Duas linhas, e o som deixa de sair de um ponto só.
func largura(x: PackedFloat32Array, atraso_ms := 12.0, ganho := 0.55) -> Array:
	var d := n_amostras(atraso_ms / 1000.0)
	var esquerda := PackedFloat32Array()
	esquerda.resize(x.size() + d)
	for i in range(x.size()):
		esquerda[i] = x[i]
	var direita := PackedFloat32Array()
	direita.resize(x.size() + d)
	for i in range(x.size()):
		direita[d + i] = x[i] * ganho
	return [esquerda, direita]

func nota(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

# ====================================================================
# MASTERIZAÇÃO E GRAVAÇÃO
# ====================================================================

## IGUALA O VOLUME PERCEBIDO E DEPOIS SEGURA OS PICOS.
##
## Normalizar pelo pico deixa o volume à mercê do transiente: um som com
## estalo curto e forte fica com o corpo inaudível, e na versão que fazia
## assim a fanfarra de recorde saía mais baixa que o tique da contagem.
## Casando o RMS, todos os efeitos chegam com a mesma presença; o
## limitador suave impede que a conta estoure os picos.
func masterizar(canais: Array, alvo_rms := 0.15) -> void:
	var soma := 0.0
	var total := 0
	for canal in canais:
		var c: PackedFloat32Array = canal
		for i in range(c.size()):
			soma += c[i] * c[i]
		total += c.size()
	var rms := sqrt(soma / float(maxi(total, 1)))
	var g := (alvo_rms / rms) if rms > 1e-9 else 1.0
	var joelho := 0.70
	for canal in canais:
		var c: PackedFloat32Array = canal
		for i in range(c.size()):
			var v := c[i] * g
			var mod := absf(v)
			if mod > joelho:
				var excesso := (mod - joelho) / (1.0 - joelho)
				v = signf(v) * (joelho + (1.0 - joelho) * tanh(excesso))
			c[i] = clampf(v, -0.985, 0.985)

## Grava estéreo de 16 bits. Estéreo porque é o que separa um efeito de
## 2026 de um bipe de 1985: a largura é metade da sensação de moderno.
func salvar(pasta: String, nome: String, esquerda: PackedFloat32Array,
		direita := PackedFloat32Array(), loop := false, alvo_rms := 0.15) -> void:
	var d := direita
	if d.is_empty():
		d = esquerda.duplicate()
	var tamanho := mini(esquerda.size(), d.size())
	var e := esquerda.slice(0, tamanho)
	d = d.slice(0, tamanho)
	if not loop:
		# RAMPA DE SAÍDA. Sem ela o corte no fim do arquivo vira estalo —
		# e um estalo no fim de um som é a coisa que mais denuncia
		# síntese caseira.
		var n := mini(n_amostras(0.006), tamanho / 4)
		for i in range(n):
			var g := 1.0 - float(i) / float(maxi(n - 1, 1))
			e[tamanho - n + i] *= g
			d[tamanho - n + i] *= g
	masterizar([e, d], alvo_rms)
	var dados := PackedByteArray()
	dados.resize(tamanho * 4)
	for i in range(tamanho):
		dados.encode_s16(i * 4, int(round(e[i] * 32767.0)))
		dados.encode_s16(i * 4 + 2, int(round(d[i] * 32767.0)))
	_escrever_wav(pasta.path_join(nome + ".wav"), dados, 2)

func _escrever_wav(caminho: String, pcm: PackedByteArray, canais: int) -> void:
	var arquivo := FileAccess.open(caminho, FileAccess.WRITE)
	if arquivo == null:
		push_error("Não consegui gravar %s" % caminho)
		return
	var taxa_de_bytes := RATE * canais * 2
	arquivo.store_buffer("RIFF".to_ascii_buffer())
	arquivo.store_32(36 + pcm.size())
	arquivo.store_buffer("WAVEfmt ".to_ascii_buffer())
	arquivo.store_32(16)
	arquivo.store_16(1)
	arquivo.store_16(canais)
	arquivo.store_32(RATE)
	arquivo.store_32(taxa_de_bytes)
	arquivo.store_16(canais * 2)
	arquivo.store_16(16)
	arquivo.store_buffer("data".to_ascii_buffer())
	arquivo.store_32(pcm.size())
	arquivo.store_buffer(pcm)
	arquivo.close()
