extends SceneTree

const Stage = preload("res://scripts/presentation/arcade_stage.gd")
var jogo: Control

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
	jogo.central_aberta = false
	jogo.calib_ativo = false
	jogo.transicao = -1.0
	jogo.state = GameDef.State.IDLE
	jogo.intro_active = true
	# Exercita o desenho, não apenas a duração da animação.
	for i in range(61):
		jogo.intro_time = Stage.T_MORPH + float(i) / 60.0 * Stage.MORPH_SECONDS
		await quadro()
	jogo._processar_abertura(0.01)
	await quadro()
	assert(not jogo.letreiro_do_nome._linhas.is_empty())
	for pagina in [1, 2, 0, 2, 1, 0]:
		jogo.state_time = pagina * jogo.ABERTURA_DURACAO + 0.6
		await quadro()
		assert(jogo.letreiro_do_nome._linhas.is_empty() == (pagina != 0))
	jogo.central_aberta = true
	await quadro()
	assert(jogo.letreiro_do_nome._linhas.is_empty())
	jogo.central_aberta = false
	jogo.state = GameDef.State.MEASURING
	jogo.hitstop_left = 0.15
	var antes: float = jogo.animation_time
	jogo._process(0.016)
	assert(jogo.animation_time > antes)
	await quadro()
	assert(jogo.letreiro_do_nome._linhas.is_empty())
	jogo.state = GameDef.State.RESULT
	jogo.ranking.clear()
	for i in range(20):
		jogo.ranking.append({"score": 9999 - i * 200, "photo_path": "", "id": str(i)})
	# A TABELA SÓ ENTRA COM A RODADA FECHADA. Sem isto o laço abaixo
	# rodava cento e dez quadros sem desenhar uma única vez a tela que
	# ele existe para exercitar — e `RENDER_FLOW_OK` continuaria saindo.
	# Ver `_tabela_no_ar`.
	jogo.rodada_encerrada_antecipadamente = true
	jogo.socos = [{"pontos": 7200, "velocidade": 4.1, "pico_g": 0.0, "duracao_ms": 5.0, "simulado": true}]
	assert(jogo._rodada_terminou())
	jogo.posicao_no_ranking = 15
	for i in range(80):
		jogo.verdict_time = jogo.ESPERA_DO_RANKING + float(i) / 15.0
		assert(jogo._tabela_no_ar())
		await quadro()
	jogo.posicao_no_ranking = 0
	for i in range(30):
		jogo.verdict_time = jogo.ESPERA_DO_RANKING + float(i) / 15.0
		await quadro()

	# ------------------------------------------------ a Central inteira
	# TODA PÁGINA DA CENTRAL TEM DE DESENHAR. Ela é feita de tabelas de
	# retângulos por chave (`PASSOS`, `BOTOES_SIMPLES`), e tirar um passo
	# de uma página sem tirar a chave — ou o contrário — não dá erro de
	# compilação: dá um `_stepper` desenhando no vazio ou um botão
	# invisível que ainda responde ao clique. Só desenhar as quatro
	# páginas encontra isso.
	jogo.state = GameDef.State.IDLE
	jogo.verdict_time = -1.0
	jogo.socos = []
	jogo.rodada_encerrada_antecipadamente = false
	jogo.central_aberta = true
	for pagina in range(jogo.PAGINAS.size()):
		jogo.central_pagina = pagina
		await quadro()
	# E o assistente de calibração, nos seus quatro passos — inclusive o
	# da sugestão, que é onde os rótulos e as unidades aparecem.
	jogo.central_pagina = 1
	jogo._abrir_calibracao()
	for passo in range(4):
		jogo.calib_passo = passo
		if passo == 3:
			jogo.calib_fracos.assign([2.0, 2.2, 2.4, 2.1, 2.3])
			jogo.calib_fortes.assign([9.0, 9.4, 10.1, 9.7, 9.2])
			jogo.calib_sugestao = Calibracao.sugerir(
				jogo.calib_fracos, jogo.calib_fortes, 0.2, jogo.sensor_raio
			)
			assert(not jogo.calib_sugestao.is_empty())
		await quadro()
	jogo._fechar_calibracao()
	jogo.central_aberta = false

	jogo.queue_free()
	await process_frame
	print("RENDER_FLOW_OK")
	quit()
