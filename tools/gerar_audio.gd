extends SceneTree

## O ESTÚDIO INTEIRO, NUM COMANDO.
##
##     godot --headless --path . --script tools/gerar_audio.gd
##
## Grava em `assets/audio/arcade/`. Para conferir contra o banco que já
## está no repositório sem sobrescrevê-lo, passe um destino:
##
##     ... --script tools/gerar_audio.gd -- /tmp/audio_novo
##
## POR QUE ISTO NÃO É MAIS PYTHON: ver o cabeçalho de
## `tools/estudio/dsp.gd`. Em resumo — mexer num som do jogo não pode
## exigir instalar uma linguagem e uma biblioteca de cálculo numérico
## numa máquina que vive num salão de festas.

const PADRAO := "res://assets/audio/arcade"

func _initialize() -> void:
	var destino := PADRAO
	for argumento in OS.get_cmdline_user_args():
		destino = str(argumento)
	if not destino.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(destino)
	var comecou := Time.get_ticks_msec()
	var dsp := EstudioDSP.new()
	var arcade := EstudioArcade.new(dsp, destino)
	print("efeitos…")
	arcade.gerar_efeitos()
	print("níveis…")
	arcade.gerar_niveis()
	print("avisos…")
	arcade.gerar_avisos()
	print("loops e música…")
	arcade.gerar_loops()
	print("arena e torcidas…")
	EstudioArena.new(dsp, destino).gerar()
	print("ESTUDIO_OK em %.1f s → %s" % [(Time.get_ticks_msec() - comecou) / 1000.0, destino])
	quit(0)
