extends SceneTree

## CONFERE O ESTÚDIO NOVO CONTRA O BANCO QUE JÁ ESTÁ NO REPOSITÓRIO.
##
##     godot --headless --path . --script tools/gerar_audio.gd -- /tmp/audio_novo
##     godot --headless --path . --script tools/conferir_audio.gd -- /tmp/audio_novo
##
## POR QUE NÃO COMPARA AMOSTRA POR AMOSTRA. Metade de cada som é ruído,
## e o gerador gaussiano que o estúdio em Python usava (o do NumPy) não é
## reproduzível fora dele. Isso não é um problema de fidelidade: ruído
## branco não tem FORMA, só estatística — dois ruídos diferentes com a
## mesma média, o mesmo desvio e o mesmo espectro soam iguais, e é
## justamente por isso que se usa ruído.
##
## O que PODE ser comparado, e é o que este arquivo compara:
##
##   duração    tem de bater exatamente: ela vem só das receitas;
##   pico       o limitador tem de agir igual nos dois;
##   RMS        é o volume percebido, e o alvo é explícito na receita;
##   espectro   a energia em três faixas (grave / médio / agudo). É o que
##              denuncia um filtro com o Q errado ou uma varredura
##              invertida, que é o tipo de erro que um porte introduz.
##
## Um som que sai fora da folga é um som em que o porte errou alguma
## coisa — e o relatório diz qual das quatro medidas escorregou.

const FOLGA_DURACAO := 0.002
const FOLGA_RMS := 0.06
const FOLGA_PICO := 0.10
const FOLGA_FAIXA := 0.16

func _initialize() -> void:
	var novo := ""
	for argumento in OS.get_cmdline_user_args():
		novo = str(argumento)
	if novo.is_empty():
		print("Diga onde está o banco novo. Ver o cabeçalho.")
		quit(2)
		return
	var problemas := 0
	var conferidos := 0
	var pasta := DirAccess.open("res://assets/audio/arcade")
	if pasta == null:
		print("FALHOU: não achei o banco do repositório")
		quit(1)
		return
	for arquivo in pasta.get_files():
		if not arquivo.ends_with(".wav"):
			continue
		var antigo := _ler("res://assets/audio/arcade/".path_join(arquivo))
		var atual := _ler(novo.path_join(arquivo))
		if antigo.is_empty() or atual.is_empty():
			print("FALHOU: %s não abriu dos dois lados" % arquivo)
			problemas += 1
			continue
		conferidos += 1
		problemas += _comparar(arquivo, antigo, atual)
	print("conferidos: %d" % conferidos)
	if problemas == 0:
		print("AUDIO_OK")
	quit(1 if problemas > 0 else 0)

func _comparar(nome: String, antigo: Dictionary, atual: Dictionary) -> int:
	var erros := 0
	var queixas := PackedStringArray()
	if absf(float(antigo["segundos"]) - float(atual["segundos"])) > FOLGA_DURACAO:
		queixas.append("duração %.3f vs %.3f" % [antigo["segundos"], atual["segundos"]])
	if _longe(float(antigo["pico"]), float(atual["pico"]), FOLGA_PICO):
		queixas.append("pico %.3f vs %.3f" % [antigo["pico"], atual["pico"]])
	if _longe(float(antigo["rms"]), float(atual["rms"]), FOLGA_RMS):
		queixas.append("RMS %.4f vs %.4f" % [antigo["rms"], atual["rms"]])
	for faixa in ["grave", "medio", "agudo"]:
		if _longe(float(antigo[faixa]), float(atual[faixa]), FOLGA_FAIXA):
			queixas.append("%s %.3f vs %.3f" % [faixa, antigo[faixa], atual[faixa]])
	if not queixas.is_empty():
		print("FALHOU %s: %s" % [nome, ", ".join(queixas)])
		erros = 1
	return erros

## Compara em PROPORÇÃO, e não em diferença: um desvio de 0,01 é enorme
## num som baixo e desprezível num alto.
func _longe(a: float, b: float, folga: float) -> bool:
	var maior := maxf(absf(a), absf(b))
	if maior < 1e-5:
		return false
	return absf(a - b) / maior > folga

func _ler(caminho: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(caminho)
	if bytes.size() < 44:
		return {}
	# Passa os pedaços do RIFF até achar o `data`; o cabeçalho nem sempre
	# tem exatos 44 bytes, e presumir isso é o erro clássico de quem lê
	# WAV à mão.
	var canais := bytes.decode_u16(22)
	var pos := 12
	# O laço procura o pedaço "data".
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var tamanho := bytes.decode_u32(pos + 4)
		if id == "data":
			return _medir(bytes.slice(pos + 8, pos + 8 + tamanho), canais)
		pos += 8 + tamanho + (tamanho % 2)
	return {}

func _medir(pcm: PackedByteArray, canais: int) -> Dictionary:
	var quadros := pcm.size() / (2 * canais)
	var x := PackedFloat32Array()
	x.resize(quadros)
	var pico := 0.0
	var soma := 0.0
	for i in range(quadros):
		# Mistura os canais: o que se mede aqui é o som, não a imagem
		# estéreo dele.
		var v := 0.0
		for c in range(canais):
			v += float(pcm.decode_s16((i * canais + c) * 2)) / 32768.0
		v /= float(canais)
		x[i] = v
		pico = maxf(pico, absf(v))
		soma += v * v
	var dsp := EstudioDSP.new()
	return {
		"segundos": float(quadros) / float(EstudioDSP.RATE),
		"pico": pico,
		"rms": sqrt(soma / float(maxi(quadros, 1))),
		"grave": _energia(dsp.biquad(x, 300.0, 0.7, "lp")),
		"medio": _energia(dsp.biquad(x, 1200.0, 0.8, "bp")),
		"agudo": _energia(dsp.biquad(x, 4000.0, 0.7, "hp")),
	}

func _energia(x: PackedFloat32Array) -> float:
	var soma := 0.0
	for i in range(x.size()):
		soma += x[i] * x[i]
	return sqrt(soma / float(maxi(x.size(), 1)))
