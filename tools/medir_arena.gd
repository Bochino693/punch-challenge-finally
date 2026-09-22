extends SceneTree

## QUANTO CUSTA A ARENA, EM MILISSEGUNDOS POR QUADRO.
##
## O jogo vai para uma TV Box, e a arena é a primeira coisa desta versão
## que gasta GPU de verdade — mundo 3D, três luzes, uma janela extra para
## renderizar. "Parece rápido aqui" não é medida: esta ferramenta roda a
## MESMA tela duas vezes, com e sem a janela 3D ligada, e imprime a
## diferença.
##
## Uso: godot --path . --script tools/medir_arena.gd
##      (não use --headless: sem rasterizador o custo do 3D não aparece)
##
## O número absoluto depende da máquina — num PC de desenvolvimento com
## vídeo por software ele é péssimo e não quer dizer nada. O que se lê
## aqui é a RAZÃO entre as duas colunas.

const QUADROS := 120
const AQUECIMENTO := 30

var jogo: Control
var fase := 0
var quadro := 0
var soma := 0.0
var pior := 0.0
var resultados: Array = []

func _initialize() -> void:
	get_root().content_scale_size = Vector2i(1080, 1920)
	jogo = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(jogo)
	jogo.intro_active = false
	jogo.state = GameDef.State.ARMED
	jogo.espera_left = 90.0
	jogo.animation_time = 3.0

func _process(delta: float) -> bool:
	quadro += 1
	# A arena é religada todo quadro: `_process` do jogo decide por conta
	# própria, e sem isto a segunda medição voltaria a ligá-la.
	if fase == 1 and jogo.arena != null:
		jogo.arena.ligar(false)
	if quadro > AQUECIMENTO:
		soma += delta
		pior = maxf(pior, delta)
	if quadro >= AQUECIMENTO + QUADROS:
		var media := soma / float(QUADROS) * 1000.0
		resultados.append({"nome": "com arena" if fase == 0 else "sem arena",
			"media": media, "pior": pior * 1000.0})
		fase += 1
		quadro = 0
		soma = 0.0
		pior = 0.0
		if fase >= 2:
			for r in resultados:
				print("%-11s  media %6.2f ms   pior %6.2f ms" % [r["nome"], r["media"], r["pior"]])
			var custo: float = resultados[0]["media"] - resultados[1]["media"]
			print("ARENA_CUSTA %.2f ms/quadro" % custo)
			quit(0)
	return false
