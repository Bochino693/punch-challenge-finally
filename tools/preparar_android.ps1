<#
    PREPARA A MAQUINA PARA EXPORTAR O APK -- e depois exporta.

    O DIAGNOSTICO QUE LEVOU A ESTE ARQUIVO

    O erro era:

        ERROR: Cannot export project with preset "Android" due to
        configuration errors:

    com a lista VAZIA depois dos dois pontos -- pela linha de comando o
    Godot imprime o cabecalho e engole as mensagens.

    O projeto estava certo: preset Android com use_gradle_build=true,
    plugin PunchUsbSerial compilado, permissao de camera ligada, as duas
    arquiteturas ARM marcadas. O que faltava NAO ESTA NO PROJETO:

      o Android SDK, o JDK e a chave de depuracao vivem nas CONFIGURACOES
      DO EDITOR do Godot, num arquivo do perfil do usuario. Nada disso
      viaja no repositorio -- e por isso o mesmo projeto exporta numa
      maquina e falha na outra sem uma linha de codigo ter mudado.

    E o GERAR_APK_COMPLETO.ps1 definia ANDROID_HOME e ANDROID_SDK_ROOT
    como variaveis de ambiente. O Godot NAO LE essas variaveis para
    exportar: ele le `export/android/android_sdk_path` das
    Configuracoes do Editor. As variaveis ficavam certas e o Godot
    continuava sem saber onde esta o SDK.

    Este script preenche as tres coisas, cria a chave de depuracao se
    ela nao existir, e so entao exporta.

    USO
        powershell -ExecutionPolicy Bypass -File PREPARAR_ANDROID.ps1 -Exportar

        -Projeto <pasta>  onde esta o project.godot (padrao: a do script)
        -Sdk <pasta>      forca o caminho do Android SDK
        -Jdk <pasta>      forca o caminho do JDK 17
        -Exportar         depois de preparar, gera o APK
        -Release          exporta em release (exige keystore propria)

    FECHE O GODOT ANTES. O editor reescreve as configuracoes ao sair e
    desfaz o que este script gravar.
#>
param(
    [string]$Projeto = "",
    [string]$Sdk = "",
    [string]$Jdk = "",
    [switch]$Exportar,
    [switch]$Release
)

$ErrorActionPreference = "Stop"
if (-not $Projeto) { $Projeto = $PSScriptRoot }
$Projeto = (Resolve-Path -LiteralPath $Projeto).Path

function Passo([string]$t) { Write-Host "==> $t" -ForegroundColor Cyan }
function Bom([string]$t)   { Write-Host "    ok   $t" }
function Aviso([string]$t) { Write-Host "    AVISO: $t" -ForegroundColor Yellow }

# --------------------------------------------------- o Godot esta aberto?
$aberto = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Godot*" }
if ($aberto) {
    throw "Feche o Godot antes. Ao sair ele reescreve as configuracoes do editor e desfaz o que este script gravar."
}

# ------------------------------------------------------------- 1. o SDK
Passo "1. Android SDK"
function Achar-Sdk() {
    $candidatos = @($Sdk, $env:ANDROID_HOME, $env:ANDROID_SDK_ROOT,
        "C:\AndroidSdk", (Join-Path $env:LOCALAPPDATA "Android\Sdk"))
    foreach ($c in $candidatos) {
        if (-not $c) { continue }
        if (Test-Path -LiteralPath (Join-Path $c "platform-tools")) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return ""
}
$sdkPath = Achar-Sdk
if (-not $sdkPath) {
    throw @"
Android SDK nao encontrado.

Procurei em -Sdk, ANDROID_HOME, ANDROID_SDK_ROOT, C:\AndroidSdk e
$env:LOCALAPPDATA\Android\Sdk, por uma pasta com platform-tools dentro.

Passe o caminho: -Sdk "C:\AndroidSdk"
"@
}
Bom $sdkPath
foreach ($parte in @("platform-tools", "build-tools", "platforms")) {
    if (Test-Path -LiteralPath (Join-Path $sdkPath $parte)) { Bom "  $parte" }
    else { Aviso "  falta $parte no SDK -- o Gradle pode pedir por ele" }
}

# ------------------------------------------------------------- 2. o JDK
#
# O Godot 4.4+ compila o Android com JDK 17. Com 11 ou 21 o Gradle
# recusa, e a recusa aparece como mais uma linha da lista que a CLI
# engole.
Passo "2. JDK 17"
function Achar-Jdk() {
    $candidatos = @($Jdk, $env:JAVA_HOME,
        "C:\Program Files\Android\Android Studio\jbr",
        "C:\Program Files\Android\Android Studio\jre")
    foreach ($raiz in @("C:\Program Files\Java", "C:\Program Files\Eclipse Adoptium", "C:\Program Files\Microsoft")) {
        if (Test-Path -LiteralPath $raiz) {
            Get-ChildItem -Path $raiz -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "17" } |
                ForEach-Object { $candidatos += $_.FullName }
        }
    }
    foreach ($c in $candidatos) {
        if (-not $c) { continue }
        if (Test-Path -LiteralPath (Join-Path $c "bin\java.exe")) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return ""
}
$jdkPath = Achar-Jdk
if (-not $jdkPath) {
    throw @"
JDK 17 nao encontrado.

O Godot 4.6 compila o Android com JDK 17 -- nem 11, nem 21.

A saida mais curta e instalar o Temurin 17:
    winget install EclipseAdoptium.Temurin.17.JDK

Depois rode este script de novo, ou passe: -Jdk "C:\Program Files\Eclipse Adoptium\jdk-17..."
"@
}
Bom $jdkPath
$versaoJava = & (Join-Path $jdkPath "bin\java.exe") -version 2>&1 | Select-Object -First 1
Write-Host "         $versaoJava"
if ("$versaoJava" -notmatch '"17') {
    Aviso "este JDK nao parece ser 17. O Gradle do Godot 4.6 pede 17."
}

# --------------------------------------------- 3. a chave de depuracao
#
# Para --export-debug o Godot precisa de uma keystore de depuracao. Ele
# usa a chave padrao do Android, em ~/.android/debug.keystore, que so
# existe se o Android Studio ja tiver rodado nesta conta. Com um SDK
# instalado a mao ela NAO existe -- e "falta a chave de depuracao" e mais
# uma das linhas que a CLI engole.
Passo "3. chave de depuracao"
$pastaChave = Join-Path $env:USERPROFILE ".android"
$chave = Join-Path $pastaChave "debug.keystore"
if (Test-Path -LiteralPath $chave) {
    Bom $chave
} else {
    New-Item -ItemType Directory -Force -Path $pastaChave | Out-Null
    $keytool = Join-Path $jdkPath "bin\keytool.exe"
    Write-Host "    criando a chave padrao do Android (validade 9999 dias)..."
    & $keytool -genkeypair -keyalg RSA -validity 9999 `
        -alias androiddebugkey -keypass android -storepass android `
        -dname "CN=Android Debug,O=Android,C=US" `
        -keystore $chave -deststoretype pkcs12 2>&1 | Out-Null
    if (-not (Test-Path -LiteralPath $chave)) { throw "Nao consegui criar $chave." }
    Bom "criada: $chave"
}

# ------------------------------------- 4. gravar nas Configuracoes do Editor
#
# AQUI ESTA O NO DO PROBLEMA. Estes tres valores nao moram no projeto:
# moram no perfil do usuario, num .tres que o editor escreve. Definir
# ANDROID_HOME no ambiente, como o script antigo fazia, nao tem efeito
# nenhum sobre a exportacao.
Passo "4. gravando nas Configuracoes do Editor do Godot"
$pastaGodot = Join-Path $env:APPDATA "Godot"
$cfg = Get-ChildItem -Path $pastaGodot -Filter "editor_settings-*.tres" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $cfg) {
    throw "Nao achei editor_settings-*.tres em $pastaGodot. Abra o Godot uma vez, feche, e rode de novo."
}
Write-Host "    $($cfg.FullName)"
Copy-Item -LiteralPath $cfg.FullName -Destination "$($cfg.FullName).bak" -Force
Bom "copia de seguranca: $($cfg.Name).bak"

# Barras PARA A FRENTE: numa string de .tres a barra invertida escapa o
# caractere seguinte, e "C:\AndroidSdk" viraria "C:<TAB>ndroidSdk".
function Barra([string]$p) { return $p.Replace('\', '/') }

$ajustes = [ordered]@{
    "export/android/android_sdk_path"   = (Barra $sdkPath)
    "export/android/java_sdk_path"      = (Barra $jdkPath)
    "export/android/debug_keystore"     = (Barra $chave)
    "export/android/debug_keystore_user" = "androiddebugkey"
    "export/android/debug_keystore_pass" = "android"
}
$texto = [System.IO.File]::ReadAllText($cfg.FullName)
foreach ($chaveCfg in $ajustes.Keys) {
    $valor = $ajustes[$chaveCfg]
    $padrao = '(?m)^' + [regex]::Escape($chaveCfg) + '\s*=\s*".*"$'
    $linha = "$chaveCfg = `"$valor`""
    if ($texto -match $padrao) {
        $texto = [regex]::Replace($texto, $padrao, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $linha })
    } else {
        # Entra logo depois de [resource], que e onde as opcoes moram.
        $texto = $texto -replace '(?m)^\[resource\]\s*$', "[resource]`r`n$linha"
    }
    Bom "$chaveCfg = $valor"
}
[System.IO.File]::WriteAllText($cfg.FullName, $texto)

# ---------------------------------------------- 5. o modelo de build
Passo "5. modelo de build Android no projeto"
$gradle = Join-Path $Projeto "android\build\build.gradle"
if (Test-Path -LiteralPath $gradle) {
    Bom "android\build\build.gradle"
} else {
    throw @"
Falta o modelo de build em $Projeto\android\build.

Com use_gradle_build=true o Godot COMPILA o aplicativo, e precisa dos
fontes do Android dentro do projeto. Abra o projeto no Godot e use:

    Projeto > Instalar modelo de compilacao Android...

Depois rode este script de novo.
"@
}

# --------------------------------------------------------- 6. exportar
if (-not $Exportar) {
    Write-Host ""
    Write-Host "PREPARADO. Agora rode com -Exportar para gerar o APK." -ForegroundColor Green
    exit 0
}

Passo "6. exportando o APK"
function Achar-Godot() {
    $c = @()
    foreach ($raiz in @((Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Documents"))) {
        if (-not (Test-Path $raiz)) { continue }
        Get-ChildItem -Path $raiz -Recurse -Depth 3 -File -Filter "Godot_v4*.exe" -ErrorAction SilentlyContinue |
            ForEach-Object { $c += $_.FullName }
    }
    # A variante de console primeiro: ela devolve codigo de saida e entrega
    # a saida na ordem em que acontece.
    $console = $c | Where-Object { $_ -like "*console*" } | Select-Object -First 1
    if ($console) { return $console }
    return ($c | Select-Object -First 1)
}
$godot = Achar-Godot
if (-not $godot) { throw "Godot 4.6.1 nao encontrado em Downloads nem Documents." }
Write-Host "    $godot"

$saida = Join-Path $Projeto "build\android"
New-Item -ItemType Directory -Force -Path $saida | Out-Null
$apk = Join-Path $saida "PunchChallenge.apk"
$logOut = Join-Path $Projeto "build\godot-android.out.log"
$logErr = Join-Path $Projeto "build\godot-android.err.log"
$modo = if ($Release) { "--export-release" } else { "--export-debug" }

$args = @("--headless", "--verbose", "--path", $Projeto, $modo, "Android", $apk) |
    ForEach-Object { '"' + $_.TrimEnd('\') + '"' }
$p = Start-Process -FilePath $godot -ArgumentList $args -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $logOut -RedirectStandardError $logErr

if (-not (Test-Path -LiteralPath $apk)) {
    Write-Host ""
    Write-Host "O APK nao foi criado (codigo $($p.ExitCode))." -ForegroundColor Red
    Write-Host "Ultimas linhas do log:" -ForegroundColor Yellow
    foreach ($arquivo in @($logErr, $logOut)) {
        if (-not (Test-Path -LiteralPath $arquivo)) { continue }
        Write-Host "  --- $(Split-Path -Leaf $arquivo)"
        Get-Content -LiteralPath $arquivo -Tail 25 | ForEach-Object { Write-Host "    $_" }
    }
    throw "Exportacao sem APK. Os logs completos estao em build\godot-android.*.log"
}

$tamanho = (Get-Item -LiteralPath $apk).Length
Write-Host ""
Write-Host "APK_OK $apk ($([math]::Round($tamanho / 1MB, 2)) MB)" -ForegroundColor Green
Write-Host ""
Write-Host "Para instalar na TV Box, com ela ligada em depuracao USB:"
Write-Host "  $sdkPath\platform-tools\adb.exe connect <ip-da-tvbox>:5555"
Write-Host "  $sdkPath\platform-tools\adb.exe install -r `"$apk`""
