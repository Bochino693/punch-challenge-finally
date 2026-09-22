extends SceneTree

## O ÍCONE DO JOGO: o emblema oficial do Punch Challenge.
##
##     godot --headless --path . --script tools/gerar_icone.gd
##
## O master continua vetorial em `assets/branding/punch_emblem.svg`; este
## utilitário apenas rasteriza a marca sem redesenhá-la nem substituí-la.

const LADO := 512
## SUPERAMOSTRAGEM: desenha três vezes maior e reduz no fim. É o que dá
## borda lisa sem nenhuma conta de antisserrilhado — e borda serrilhada
## num ícone é a primeira coisa que denuncia trabalho apressado.
const SUPER := 3
const CREME := Color8(255, 248, 236)
const MARINHO := Color8(28, 53, 102)
const VERMELHO := Color8(230, 57, 80)
const AMBAR := Color8(242, 160, 7)
const BRANCO := Color8(255, 255, 255)

var tela: Image

func _initialize() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://assets/branding/punch_emblem.svg")
	var marca := Image.new()
	var erro := marca.load_svg_from_buffer(bytes, float(LADO) / 900.0)
	if erro != OK or marca.is_empty():
		print("FALHOU ao abrir o emblema oficial")
		quit(1)
		return
	marca.resize(LADO, LADO, Image.INTERPOLATE_LANCZOS)
	for destino_icone in ["res://assets/icon.png", "res://assets/icon-android.png"]:
		if marca.save_png(destino_icone) != OK:
			print("FALHOU ao gravar %s" % destino_icone)
			quit(1)
			return
	print("ICONE_OK → Windows/Android (%d × %d)" % [LADO, LADO])
	quit(0)
	return

	# Implementação antiga mantida abaixo apenas como referência do desenho.
	var w := LADO * SUPER
	tela = Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
	tela.fill(Color(0, 0, 0, 0))
	var s := float(SUPER)

	# A placa: moldura marinho e miolo creme.
	_retangulo(14.0 * s, 14.0 * s, 498.0 * s, 498.0 * s, 112.0 * s, MARINHO)
	_retangulo(34.0 * s, 34.0 * s, 478.0 * s, 478.0 * s, 94.0 * s, CREME)

	# Raios de impacto atrás da luva.
	var cx := 256.0 * s
	var cy := 262.0 * s
	for k in range(8):
		var a := TAU * float(k) / 8.0 + 0.35
		_linha(
			Vector2(cx + cos(a) * 150.0 * s, cy + sin(a) * 150.0 * s),
			Vector2(cx + cos(a) * 205.0 * s, cy + sin(a) * 205.0 * s),
			18.0 * s, AMBAR
		)

	# A LUVA. A silhueta é a UNIÃO de quatro formas redondas, e o contorno
	# sai de desenhar as mesmas quatro dilatadas por baixo: assim a borda
	# continua redonda em vez de ganhar bicos, que é o que acontece ao
	# escalar um polígono de poucos vértices.
	var r := 150.0 * s
	_luva(cx, cy, r, 0.09 * r, MARINHO)
	_luva(cx, cy, r, 0.0, VERMELHO)
	# Vinco dos dedos e faixa do punho: os dois riscos que fazem o olho
	# ler "luva" e não "mancha vermelha".
	_linha(Vector2(cx - 0.24 * r, cy - 0.22 * r), Vector2(cx + 0.60 * r, cy - 0.26 * r), 0.10 * r, BRANCO)
	_linha(Vector2(cx - 0.20 * r, cy + 0.42 * r), Vector2(cx + 0.40 * r, cy + 0.42 * r), 0.11 * r, BRANCO)

	tela = _reduzir(tela)
	var saida := "res://assets/icon.png"
	if tela.save_png(saida) != OK:
		print("FALHOU ao gravar %s" % saida)
		quit(1)
		return
	print("ICONE_OK → %s (%d × %d)" % [saida, LADO, LADO])
	quit(0)

## A REDUÇÃO É UMA MÉDIA DE CAIXA, e não um filtro do motor.
##
## Três por três pixels viram um, somando e dividindo. É exatamente o que
## a superamostragem pede: cada pixel final conta quantas das nove
## amostras caíram dentro da forma, o que dá a borda suave. Um filtro
## mais esperto (Lanczos) inventa meio-tons que não estão no desenho,
## realça as bordas e quintuplica o tamanho do arquivo sem melhorar nada
## num ícone de cores chapadas.
func _reduzir(grande: Image) -> Image:
	var pequena := Image.create_empty(LADO, LADO, false, Image.FORMAT_RGBA8)
	var n := float(SUPER * SUPER)
	for y in range(LADO):
		for x in range(LADO):
			var soma := Color(0, 0, 0, 0)
			for dy in range(SUPER):
				for dx in range(SUPER):
					var px := grande.get_pixel(x * SUPER + dx, y * SUPER + dy)
					# O PIXEL TRANSPARENTE NÃO TEM COR. Somar o preto que
					# mora por baixo dele escurece a borda inteira; é o
					# halo cinza que aparece em volta de todo ícone feito
					# sem este cuidado.
					soma += Color(px.r * px.a, px.g * px.a, px.b * px.a, px.a)
			var a := soma.a / n
			if a <= 0.0001:
				pequena.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				pequena.set_pixel(x, y, Color(soma.r / n / a, soma.g / n / a, soma.b / n / a, a))
	return pequena

func _luva(cx: float, cy: float, r: float, dilata: float, cor: Color) -> void:
	_disco(cx + 0.10 * r, cy - 0.26 * r, 0.64 * r + dilata, cor)
	_retangulo(cx - 0.54 * r - dilata, cy - 0.30 * r - dilata,
		cx + 0.58 * r + dilata, cy + 0.26 * r + dilata, 0.16 * r, cor)
	_disco(cx - 0.58 * r, cy + 0.02 * r, 0.30 * r + dilata, cor)
	_retangulo(cx - 0.30 * r - dilata, cy + 0.24 * r - dilata,
		cx + 0.50 * r + dilata, cy + 0.84 * r + dilata, 0.16 * r, cor)

func _pintar(x: int, y: int, cor: Color) -> void:
	if x < 0 or y < 0 or x >= tela.get_width() or y >= tela.get_height():
		return
	tela.set_pixel(x, y, cor)

func _disco(cx: float, cy: float, r: float, cor: Color) -> void:
	for y in range(int(cy - r) - 1, int(cy + r) + 2):
		var dy := float(y) - cy
		var dentro := r * r - dy * dy
		if dentro <= 0.0:
			continue
		var dx := sqrt(dentro)
		for x in range(int(cx - dx), int(cx + dx) + 1):
			_pintar(x, y, cor)

## Retângulo de cantos redondos: o ponto mais próximo do centro do canto
## dá a distância, e a distância dá o recorte. Dois `clamp` e uma conta.
func _retangulo(x0: float, y0: float, x1: float, y1: float, r: float, cor: Color) -> void:
	for y in range(int(y0), int(y1) + 1):
		for x in range(int(x0), int(x1) + 1):
			var qx := clampf(float(x), x0 + r, x1 - r)
			var qy := clampf(float(y), y0 + r, y1 - r)
			var dx := float(x) - qx
			var dy := float(y) - qy
			if dx * dx + dy * dy <= r * r:
				_pintar(x, y, cor)

func _linha(p0: Vector2, p1: Vector2, largura: float, cor: Color) -> void:
	var n := int(p0.distance_to(p1)) + 1
	for i in range(n + 1):
		var t := float(i) / float(n)
		var p := p0.lerp(p1, t)
		_disco(p.x, p.y, largura * 0.5, cor)
