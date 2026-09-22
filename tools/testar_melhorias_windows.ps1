param(
    [string]$Godot = ""
)

# O LUTADOR NAO E MAIS GERADO AQUI. Ele e construido pelo proprio jogo,
# em GDScript, quando a arena sobe: nao ha .glb para produzir, nem
# Blender, nem Python. O que sobrou deste script e o que ele sempre
# deveria ter sido — importar os recursos e rodar a bateria de testes.
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = Get-ChildItem (Join-Path $env:USERPROFILE "Downloads") -Filter "Godot_v4*.exe" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if ([string]::IsNullOrWhiteSpace($Godot) -or -not (Test-Path $Godot)) {
    throw "Godot não encontrado. Informe: -Godot 'C:\caminho\Godot_v4.6.1-stable_win64.exe'"
}

# MESMO DEFEITO QUE O exportar_windows.ps1 TINHA: o binario do Godot e de
# subsistema grafico, e `&` nao espera um programa de GUI terminar. O
# `$LASTEXITCODE` ficava vazio e o script morria antes de o Godot sequer
# comecar. `Start-Process -Wait -PassThru` espera e devolve o codigo.
function Invocar-Godot([string[]]$argumentos) {
    $aspeados = $argumentos | ForEach-Object { '"' + $_.TrimEnd('\') + '"' }
    $p = Start-Process -FilePath $Godot -ArgumentList $aspeados -NoNewWindow -Wait -PassThru
    return $p.ExitCode
}

Write-Host "Importando recursos no Godot..." -ForegroundColor Cyan
if ((Invocar-Godot @("--headless", "--editor", "--path", $ProjectRoot, "--quit")) -ne 0) {
    throw "Falha ao importar recursos no Godot"
}

$Tests = @(
    "tests/test_core.gd",
    "tests/test_arena.gd",
    "tests/test_folha_lutador.gd",
    "tests/test_quadro_liso.gd",
    "tests/test_camera_viva.gd",
    "tests/test_dois_socos.gd",
    "tests/test_render_flow.gd",
    "tests/test_show_flow.gd",
    "tests/test_linha_serial.gd",
    "tests/test_descoberta_da_porta.gd",
    "tests/test_native_reentry.gd",
    "tests/test_ponte_teimosa.gd",
    "tests/test_serial_teimoso.gd",
    "tests/test_enquadramento_responsivo.gd"
)

foreach ($Test in $Tests) {
    Write-Host "TESTE $Test" -ForegroundColor Yellow
    if ((Invocar-Godot @("--headless", "--path", $ProjectRoot, "--script", (Join-Path $ProjectRoot $Test))) -ne 0) {
        throw "Teste falhou: $Test"
    }
}

Write-Host "Todos os testes concluídos. Abrindo o jogo para inspeção visual." -ForegroundColor Green
& $Godot --path $ProjectRoot --editor
