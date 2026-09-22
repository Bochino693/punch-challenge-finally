extends SceneTree

## MEDE A FOLHA DE POSES E IMPRIME OS NÚMEROS DA ESCALA.
##
## POR QUE ISTO EXISTE. A escala do lutador vinha de uma frase — "a
## figura ocupa cerca de 86% do quadro" — que ninguém tinha medido. Não
## ocupava: ocupa 97,9%. O erro não aparece em teste de código nenhum,
## não quebra nada e não dá aviso: só sai um lutador de 2,03 m onde se
## pediu 1,80, estourando o enquadramento por cima e por baixo. A câmera
## foi afastada três vezes para compensar isso.
##
## Agora quem troca a arte roda ISTO, lê a tabela e copia as duas
## constantes para `scripts/arena/lutador.gd`. O trabalho de olho sai da
## conta.
##
## Uso:
##     godot --headless --path . --script tools/medir_folha.gd

func _init() -> void:
	var folha := Lutador3D.FOLHA
	var medidas := FolhaDoLutador.medir(folha)
	if medidas.is_empty():
		push_error("Não deu para ler a folha em %s" % folha)
		quit(1)
		return
	print("FOLHA: %s" % folha)
	print("limiar de alfa: %d de 255" % FolhaDoLutador.LIMIAR)
	print("")
	print("A SOLA É A BASE: a figura encosta no chão pelo ponto mais baixo.")
	print("O pé de trás aparece mais alto por perspectiva e NÃO é o chão.")
	print("")
	print("pose              topo  base(=sola)  pé de trás   encosta na borda")
	for nome in medidas:
		var m: Dictionary = medidas[nome]
		print("%-16s %5d %12d %11s   %s" % [
			nome, m["topo"], m["base"],
			("%d" % m["pe_de_tras"]) if int(m["pe_de_tras"]) >= 0 else "—",
			", ".join(m["bordas"]) if not (m["bordas"] as PackedStringArray).is_empty() else "—",
		])
	print("")
	_sugerir(medidas)
	quit(0)

## AS CONSTANTES PRONTAS PARA COLAR. É o passo que costuma ser feito de
## cabeça e errado.
func _sugerir(medidas: Dictionary) -> void:
	var topo := 1 << 30
	var sola := -1
	for nome in FolhaDoLutador.POSES_EM_PE:
		if not medidas.has(nome):
			continue
		var m: Dictionary = medidas[nome]
		topo = mini(topo, int(m["topo"]))
		sola = maxi(sola, int(m["sola"]))
	if topo == 1 << 30 or sola < 0:
		push_warning("Nenhuma pose em pé foi encontrada; a escala não pode ser sugerida.")
		return
	var altura_px := sola - topo + 1
	print("PARA scripts/arena/lutador.gd:")
	print("    const TOPO_DA_CABECA_PX := %d.0" % topo)
	print("    const SOLA_DO_PE_PX := %d.0" % sola)
	print("")
	var alvo := Lutador3D.ALTURA_DA_FIGURA
	print("Com ALTURA_DA_FIGURA = %.2f m isso dá:" % alvo)
	print("    a figura mede %d px (%.1f%% do quadro)" % [
		altura_px, float(altura_px) / FolhaDoLutador.LADO_Y * 100.0])
	print("    pixel no mundo = %.6f m" % (alvo / float(altura_px)))
	print("    quadro inteiro = %.4f m" % (FolhaDoLutador.LADO_Y * alvo / float(altura_px)))
	var flutuando := PackedStringArray()
	for nome in FolhaDoLutador.POSES_QUE_PISAM:
		if not medidas.has(nome):
			continue
		if not ("BAIXO" in (medidas[nome]["bordas"] as PackedStringArray)):
			flutuando.append(str(nome))
	print("")
	if flutuando.is_empty():
		print("Todas as poses de pé alcançam a linha do chão.")
	else:
		print("POSES DE PÉ QUE NÃO ALCANÇAM A ÚLTIMA LINHA DA CÉLULA:")
		print("    %s" % ", ".join(flutuando))
		print("    Elas vão aparecer flutuando acima do tapete. A linha do")
		print("    chão é a borda de baixo da célula, e é lá que a sola do")
		print("    pé da frente tem de ser desenhada.")
