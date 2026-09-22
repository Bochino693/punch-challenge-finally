extends SceneTree

## A FAXINA DAS FOTOS SOB TESTE.
##
## "RANKING + FOTOS" tinha dois defeitos que se escondiam um atrás do
## outro. Apagava só as vinte fotos da lista, deixando na pasta a de
## todo mundo que entrou no ranking e depois caiu dele — e varrer a
## pasta inteira, que é o conserto, trocaria esse defeito por um pior:
## centenas de remoções dentro de um clique congelam a tela no meio do
## salão.
##
## O que este arquivo guarda são as quatro promessas:
##
##   1. a faxina leva TODA foto da pasta, não só as da lista;
##   2. nada bloqueia: cada passo apaga um punhado e devolve a máquina;
##   3. a lista é um retrato do instante do clique — foto tirada DEPOIS
##      do reset é de uma partida nova e não pode sumir junto;
##   4. um arquivo que resiste é contado, não trava a faxina.

const PASTA := RankingStore.PHOTO_DIR

var falhas := 0

func _ok(condicao: bool, o_que: String) -> void:
	if not condicao:
		falhas += 1
		print("FALHOU: %s" % o_que)

func _semear(quantas: int) -> void:
	DirAccess.make_dir_recursive_absolute(PASTA)
	for antiga in RankingStore.listar_fotos():
		RankingStore.delete_photo(antiga)
	for i in range(quantas):
		var f := FileAccess.open("%s/teste_%03d.png" % [PASTA, i], FileAccess.WRITE)
		f.store_string("x")
		f.close()

func _init() -> void:
	# 1. A PASTA INTEIRA, E NÃO SÓ A LISTA.
	#
	# Vinte marcas no ranking, cento e cinquenta fotos na pasta: é o
	# retrato de uma casa que roda há um mês. O que o operador mandou
	# apagar foram as cento e cinquenta.
	_semear(150)
	_ok(RankingStore.listar_fotos().size() == 150, "a pasta devia listar as 150 fotos")

	var faxina := Faxina.new()
	faxina.comecar(RankingStore.listar_fotos())
	_ok(faxina.total == 150, "a faxina devia abrir com 150 arquivos")
	_ok(faxina.rodando, "a faxina devia estar correndo")

	# 2. NADA BLOQUEIA.
	#
	# Um passo apaga um punhado e devolve. Se alguém trocar o corte por
	# um laço até o fim, este número denuncia na hora.
	faxina.passo()
	_ok(
		faxina.feitas == Faxina.POR_QUADRO,
		"um passo devia apagar %d, apagou %d" % [Faxina.POR_QUADRO, faxina.feitas]
	)
	_ok(faxina.rodando, "com 142 arquivos pela frente a faxina não podia ter acabado")
	_ok(faxina.progresso() < 0.1, "o andamento devia estar no começo")

	# 3. O RETRATO DO INSTANTE DO CLIQUE.
	#
	# Enquanto a faxina corre, alguém bate um soco e entra no ranking. A
	# foto DESSA partida não estava na lista tirada no clique, e apagá-la
	# seria apagar a marca de quem acabou de jogar.
	var nova := "%s/depois_do_reset.png" % PASTA
	var f := FileAccess.open(nova, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	var voltas := 0
	while faxina.rodando and voltas < 200:
		faxina.passo()
		voltas += 1
	_ok(not faxina.rodando, "a faxina devia ter terminado")
	_ok(faxina.feitas == 150, "devia ter apagado as 150, apagou %d" % faxina.feitas)
	_ok(faxina.progresso() >= 1.0, "o andamento devia estar cheio")
	_ok(faxina.erros() == 0, "nenhum arquivo devia ter resistido")
	_ok(
		FileAccess.file_exists(nova),
		"a foto tirada DEPOIS do clique não podia ter sido apagada junto"
	)
	_ok(
		RankingStore.listar_fotos().size() == 1,
		"devia sobrar só a foto nova, sobraram %d" % RankingStore.listar_fotos().size()
	)

	# 4. UM ARQUIVO QUE RESISTE É CONTADO, NÃO TRAVA.
	#
	# Caminho que não existe mais (outra faxina levou, ou o Windows
	# segurou o arquivo e ele saiu depois). A faxina segue e o número da
	# Central continua verdadeiro.
	var teimoso := Faxina.new()
	teimoso.comecar(PackedStringArray([
		"%s/nunca_existiu.png" % PASTA,
		"res://fora_da_pasta.png",
		nova,
	]))
	while teimoso.rodando:
		teimoso.passo()
	_ok(teimoso.feitas == 3, "a faxina devia ter percorrido os três caminhos")
	_ok(not FileAccess.file_exists(nova), "a foto listada devia ter saído")

	# 5. SEM FAXINA ABERTA, O PASSO NÃO CUSTA NADA — é o que deixa a
	#    chamada morar no `_process` sem condição em volta.
	var parada := Faxina.new()
	parada.passo()
	_ok(not parada.rodando and parada.total == 0, "faxina vazia não podia abrir sozinha")
	_ok(parada.progresso() == 1.0, "faxina vazia devia desenhar a barra como pronta")

	for sobra in RankingStore.listar_fotos():
		RankingStore.delete_photo(sobra)

	if falhas == 0:
		print("FAXINA_OK")
	else:
		print("FAXINA COM %d FALHA(S)" % falhas)
	quit(1 if falhas > 0 else 0)
