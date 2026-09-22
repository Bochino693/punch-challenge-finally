extends SceneTree

## Contratos desta entrega: ranking de luta, contagem limitada pelo tempo e
## pacote Windows que não deixa a câmera para trás.

func _initialize() -> void:
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	var inicio := main.find("func _ranking_anuncio")
	var fim := main.find("\n# ---------------------------------------------------------------- central", inicio)
	var anuncio := main.substr(inicio, fim - inicio)
	assert("Icones.cinturao" in anuncio)
	assert("Icones.trofeu" in anuncio)
	assert("Icones.estrela" not in anuncio)

	# A subida usa interpolação temporal; 9999 custa os mesmos quadros que 99.
	var proc_inicio := main.find("func _processar_resultado")
	var proc_fim := main.find("\nfunc ", proc_inicio + 8)
	var contagem := main.substr(proc_inicio, proc_fim - proc_inicio)
	assert("result_time / GameDef.CONTAGEM_DURACAO" in contagem)
	assert("range(result_score" not in contagem)
	assert("func camera_liberou_a_rodada() -> bool:\n\treturn true" in main)
	assert("var camera_obrigatoria := false" in main)
	assert("const ESPERA_MAXIMA_DA_CAMERA := 0.0" in main)

	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert("export_path=\"build/windows/PunchChallenge.exe\"" in preset)
	assert("binary_format/embed_pck=false" in preset)
	var camera := FileAccess.get_file_as_string("res://scripts/camera_service.gd")
	assert("CameraServer.feeds().is_empty()" in camera)
	assert("CÂMERA INDISPONÍVEL" in camera)
	assert("_indice_camera_usb" in camera)
	assert("PACOTE INCOMPLETO" not in main)
	assert(FileAccess.file_exists("res://tools/exportar_windows.ps1"))
	assert(FileAccess.file_exists("res://assets/audio/LICENCAS.md"))
	assert(FileAccess.file_exists("res://assets/icon-android.png"))
	var ico := FileAccess.get_file_as_bytes("res://assets/icon.ico")
	assert(ico.size() > 6 and ico[0] == 0 and ico[1] == 0 and ico[2] == 1 and ico[3] == 0)
	assert("application/icon=\"res://assets/icon.png\"" in preset)
	assert("application/console_wrapper_icon=\"res://assets/icon.png\"" in preset)
	assert("launcher_icons/main_192x192=\"res://assets/icon-android.png\"" in preset)

	print("ENTREGA_FINAL_OK")
	quit(0)
