extends SceneTree

## Teste de contrato da apresentação. Ele não precisa abrir uma TV real:
## garante que o projeto preserve 9:16 sem introduzir uma borda interna.

func _init() -> void:
	var projeto := ConfigFile.new()
	var erro := projeto.load("res://project.godot")
	_assert(erro == OK, "project.godot precisa ser legível")
	_assert(projeto.get_value("display", "window/stretch/mode", "") == "canvas_items",
		"stretch deve usar canvas_items")
	_assert(projeto.get_value("display", "window/stretch/aspect", "") == "keep",
		"a proporção 9:16 precisa ser preservada")
	_assert(projeto.get_value("display", "window/stretch/scale_mode", "") == "fractional",
		"resoluções não inteiras precisam de escala fracionária")

	var principal := FileAccess.get_file_as_string("res://scripts/main.gd")
	_assert(principal.contains("scale = Vector2.ONE"),
		"o quadro principal não pode ser reduzido")
	_assert(principal.contains("position = Vector2.ZERO"),
		"o quadro principal precisa começar na borda da tela")
	_assert(principal.contains("return _arduino_conectado() and camera_liberou_a_rodada()"),
		"START deve depender do Arduino, não da busca do sensor")

	print("OK: tela cheia 9:16 e início por conexão Arduino validados")
	quit(0)

func _assert(condicao: bool, mensagem: String) -> void:
	if condicao:
		return
	push_error("FALHA: " + mensagem)
	quit(1)
