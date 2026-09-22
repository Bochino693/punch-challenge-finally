<#
    POR QUE O GODOT RECUSA O EXPORT DO ANDROID -- as seis causas, separadas.

    O SINTOMA QUE TRAZ ALGUEM ATE AQUI:

        ERROR: Cannot export project with preset "Android" due to
        configuration errors:
        ERROR: Project export for preset "Android" failed.

    Repare que depois dos dois pontos NAO VEM NADA. Nao e a sua copia
    que cortou: pela linha de comando o Godot imprime o cabecalho e
    engole a lista. As mensagens so aparecem na janela Projeto >
    Exportar, dentro do editor -- que e justamente o que ninguem abre
    quando esta automatizando.

    Este script pergunta, uma por uma, as seis coisas que aquela lista
    poderia estar dizendo. Ele NAO MUDA NADA: so olha e responde.

    USO
        powershell -ExecutionPolicy Bypass -File tools\conferir_android.ps1 `
            -Projeto "C:\caminho\do\projeto\android"

        -Projeto   a pasta que tem o project.godot (padrao: a deste
                   repositorio)
        -Versao    a versao do Godot (padrao: 4.6.1)
#>
param(
    [string]$Projeto = "",
    [string]$Versao = "4.6.1"
)

$ErrorActionPreference = "Stop"
if (-not $Projeto) { $Projeto = Split-Path -Parent $PSScriptRoot }
$Projeto = (Resolve-Path -LiteralPath $Projeto).Path

$problemas = @()
function Passo([string]$t) { Write-Host "==> $t" }
function Bom([string]$t)   { Write-Host "    ok   $t" }
function Mau([string]$t, [string]$comoResolver) {
    Write-Host "    FALTA $t" -ForegroundColor Red
    if ($comoResolver) { Write-Host "         $comoResolver" }
    $script:problemas += $t
}
function Talvez([string]$t) { Write-Host "    ?    $t" -ForegroundColor Yellow }

Write-Host "PROJETO: $Projeto"
Write-Host "GODOT:   $Versao"
Write-Host ""

# ---------------------------------------------------------------- 1. preset
Passo "1. o preset Android do projeto"
$presetArquivo = Join-Path $Projeto "export_presets.cfg"
if (-not (Test-Path -LiteralPath $presetArquivo)) {
    Mau "export_presets.cfg" "Abra o projeto no Godot e crie o preset Android em Projeto > Exportar."
    $preset = ""
} else {
    $preset = [System.IO.File]::ReadAllText($presetArquivo)
    if ($preset -match 'platform="Android"') { Bom "existe um preset Android" }
    else { Mau "preset Android" "Projeto > Exportar > Adicionar > Android." }
}

$usaGradle = $preset -match 'gradle_build/use_gradle_build\s*=\s*true'
if ($usaGradle) { Bom "gradle_build/use_gradle_build=true" }
else { Write-Host "    -    gradle_build/use_gradle_build=false (APK pre-compilado)" }

# ------------------------------------------------------ 2. plugins x gradle
#
# ESTA E A CAUSA NUMERO UM quando alguem acabou de instalar um addon
# nativo. Um plugin Android do Godot 4 e codigo JAVA/KOTLIN que precisa
# ser COMPILADO junto com o aplicativo. O APK pre-compilado que vem nos
# modelos de exportacao nao tem como receber isso -- ele ja veio pronto.
# Por isso o Godot recusa a combinacao "ha plugin + use_gradle_build
# esta desligado", e essa recusa e uma das linhas que a lista engoliu.
Passo "2. ha plugin nativo Android no projeto?"
$plugins = @()
$addons = Join-Path $Projeto "addons"
if (Test-Path -LiteralPath $addons) {
    $plugins = Get-ChildItem -Path $addons -Recurse -File -Filter "*.gdap" -ErrorAction SilentlyContinue
    $plugins += Get-ChildItem -Path $addons -Recurse -File -Filter "export_plugin.gd" -ErrorAction SilentlyContinue
}
if ($plugins.Count -gt 0) {
    foreach ($p in $plugins) { Write-Host "    -    $($p.FullName.Substring($Projeto.Length).TrimStart('\'))" }
    if ($usaGradle) {
        Bom "ha plugin e o build por Gradle esta ligado"
    } else {
        Mau "use_gradle_build=true (ha plugin nativo no projeto)" @"
Plugin Android e codigo Java/Kotlin: precisa ser COMPILADO junto.
O APK pre-compilado dos modelos nao aceita isso, e o Godot recusa.
    Projeto > Exportar > Android > marque 'Use Gradle Build'.
"@
    }
} else {
    Bom "nenhum plugin nativo (o APK pre-compilado serve)"
}

# --------------------------------------------- 3. modelo de build no projeto
Passo "3. o modelo de build Android esta instalado NO PROJETO?"
$buildGradle = Join-Path $Projeto "android\build\build.gradle"
if (Test-Path -LiteralPath $buildGradle) {
    Bom "android\build existe"
} elseif ($usaGradle -or $plugins.Count -gt 0) {
    Mau "android\build (modelo de build)" @"
No Godot: Projeto > Instalar modelo de build do Android.
Ele cria a pasta android/build dentro do projeto. Sem ela o Gradle
nao tem o que compilar.
"@
} else {
    Write-Host "    -    nao e necessario sem Gradle"
}

# ------------------------------------------------ 4. modelos de exportacao
Passo "4. os modelos de exportacao do Godot $Versao"
$modelos = Join-Path $env:APPDATA "Godot\export_templates\$Versao.stable"
if (Test-Path -LiteralPath $modelos) {
    Bom "pasta $modelos"
    foreach ($nome in @("android_debug.apk", "android_release.apk", "android_source.zip")) {
        if (Test-Path -LiteralPath (Join-Path $modelos $nome)) { Bom $nome }
        else { Mau $nome "Editor > Gerenciar modelos de exportacao > Baixar e instalar ($Versao.stable)." }
    }
} else {
    Mau "modelos de exportacao $Versao.stable" "Editor > Gerenciar modelos de exportacao > Baixar e instalar."
}

# --------------------------------------------------- 5. SDK, JDK, keystore
#
# Os tres vivem nas CONFIGURACOES DO EDITOR, e nao no projeto -- por
# isso um projeto que exporta numa maquina falha noutra sem nada ter
# mudado no repositorio.
Passo "5. Android SDK, JDK e keystore de depuracao (Configuracoes do Editor)"
$cfgEditor = Join-Path $env:APPDATA "Godot\editor_settings-4.6.tres"
if (-not (Test-Path -LiteralPath $cfgEditor)) {
    $achado = Get-ChildItem -Path (Join-Path $env:APPDATA "Godot") -Filter "editor_settings-*.tres" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($achado) { $cfgEditor = $achado.FullName }
}
if (Test-Path -LiteralPath $cfgEditor) {
    Write-Host "    -    $cfgEditor"
    $cfg = [System.IO.File]::ReadAllText($cfgEditor)
    function Valor([string]$chave) {
        if ($cfg -match [regex]::Escape($chave) + '\s*=\s*"([^"]*)"') { return $Matches[1] }
        return ""
    }
    $sdk = Valor 'export/android/android_sdk_path'
    $jdk = Valor 'export/android/java_sdk_path'
    $key = Valor 'export/android/debug_keystore'
    if ($sdk -and (Test-Path -LiteralPath $sdk)) { Bom "Android SDK: $sdk" }
    elseif ($usaGradle -or $plugins.Count -gt 0) {
        Mau "Android SDK" "Editor > Configuracoes do Editor > Export > Android > Android Sdk Path."
    } else { Talvez "Android SDK nao configurado (so e exigido com Gradle)" }

    if ($jdk -and (Test-Path -LiteralPath $jdk)) { Bom "JDK: $jdk" }
    elseif ($usaGradle -or $plugins.Count -gt 0) {
        Mau "JDK 17" "Editor > Configuracoes do Editor > Export > Android > Java Sdk Path. O Godot 4.6 pede JDK 17."
    } else { Talvez "JDK nao configurado (so e exigido com Gradle)" }

    if ($key -and (Test-Path -LiteralPath $key)) { Bom "keystore de depuracao: $key" }
    else { Talvez "keystore de depuracao nao configurado (o Godot costuma gerar um sozinho)" }
} else {
    Talvez "nao achei o editor_settings-*.tres -- abra o Godot uma vez"
}

# ---------------------------------------------------- 6. release x keystore
#
# --export-release EXIGE keystore de RELEASE. Sem ela a lista de erros
# que a CLI engole diz exatamente isso -- e a saida mais rapida, para
# quem so quer ver o jogo rodando na TV Box, e exportar em DEBUG.
Passo "6. exportando em release, ha keystore de release?"
if ($preset -match 'keystore/release\s*=\s*"([^"]+)"' -and $Matches[1]) {
    Bom "keystore de release no preset"
} else {
    Talvez "sem keystore de release no preset"
    Write-Host "         Para instalar numa TV Box sua, DEBUG basta e dispensa keystore:"
    Write-Host "           --export-debug ""Android"" ""<caminho>\PunchChallenge.apk"""
}

# ----------------------------------------------------- 7. a TV Box e arm64?
Passo "7. arquiteturas marcadas no preset"
foreach ($arq in @("armeabi-v7a", "arm64-v8a", "x86_64")) {
    if ($preset -match "architectures/$([regex]::Escape($arq))\s*=\s*true") { Bom $arq }
    else { Write-Host "    -    $arq desligado" }
}
if ($preset -notmatch 'architectures/armeabi-v7a\s*=\s*true') {
    Write-Host "         TV Box barata as vezes roda userspace de 32 bits. Marcar TAMBEM"
    Write-Host "         armeabi-v7a custa tamanho de APK e evita 'app nao instalado'."
}

Write-Host ""
if ($problemas.Count -eq 0) {
    Write-Host "ANDROID_OK - nenhum pre-requisito faltando." -ForegroundColor Green
    Write-Host "Se o export ainda recusar, abra Projeto > Exportar no editor: a janela"
    Write-Host "mostra a lista de erros que a linha de comando engole."
} else {
    Write-Host "ANDROID_INCOMPLETO - $($problemas.Count) item(ns):" -ForegroundColor Red
    foreach ($p in $problemas) { Write-Host "  - $p" }
}
