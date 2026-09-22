param(
    [string]$Godot = "godot",
    [string]$Preset = "Windows Desktop"
)

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$saida = Join-Path $raiz "build\windows"
$zip = Join-Path $raiz "build\PunchChallenge-Windows-x64.zip"

if (Test-Path $saida) { Remove-Item -Recurse -Force $saida }
New-Item -ItemType Directory -Force -Path $saida | Out-Null
& $Godot --headless --path $raiz --export-release $Preset
if ($LASTEXITCODE -ne 0) { throw "A exportacao do Godot falhou." }

# Não depende do exportador adivinhar onde pôr as bibliotecas. Copia cada
# backend para o mesmo caminho declarado no .gdextension, preservando a
# estrutura que o carregador resolve a partir de res://.
$nativas = @(
    @("addons\CameraServerExtension\x86_64\libcameraserver-extension.windows.dll",
      "addons\CameraServerExtension\x86_64\libcameraserver-extension.windows.dll"),
    @("addons\gdserial\bin\windows-x86_64\gdserial.dll",
      "addons\gdserial\bin\windows-x86_64\gdserial.dll")
)
foreach ($par in $nativas) {
    $origem = Join-Path $raiz $par[0]
    $destino = Join-Path $saida $par[1]
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destino) | Out-Null
    Unblock-File -LiteralPath $origem -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $origem -Destination $destino -Force
    Unblock-File -LiteralPath $destino -ErrorAction SilentlyContinue
}

$obrigatorios = @(
    "PunchChallenge.exe",
    "PunchChallenge.pck",
    "gdserial.dll",
    "libcameraserver-extension.windows.dll"
)
foreach ($nome in $obrigatorios) {
    $achado = Get-ChildItem -Path $saida -Recurse -File -Filter $nome | Select-Object -First 1
    if (-not $achado) { throw "Pacote incompleto: faltou $nome" }
}

$leia = @"
PUNCH CHALLENGE - WINDOWS x64

1. Extraia este ZIP inteiro.
2. Execute PunchChallenge.exe dentro da pasta extraida.
3. Nao mova apenas o EXE: o PCK, a camera e o sensor ficam nesta pasta.

Se uma maquina Windows limpa recusar as bibliotecas, instale o Microsoft
Visual C++ 2015-2022 Redistributable x64 e execute novamente.
"@
Set-Content -LiteralPath (Join-Path $saida "LEIA-ANTES-DE-EXECUTAR.txt") -Value $leia -Encoding UTF8

if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $saida "*") -DestinationPath $zip -CompressionLevel Optimal
Write-Host "PACOTE_OK $zip"
