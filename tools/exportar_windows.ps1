<#
    EXPORTA O PUNCH CHALLENGE PARA WINDOWS, COMPLETO, NUMA LINHA SÓ.

    O QUE ESTE SCRIPT RESOLVE

    A câmera e o sensor do jogo não são código do Godot: são duas
    bibliotecas NATIVAS (GDExtension) que viajam como arquivo solto ao
    lado do executável.

        libcameraserver-extension.windows.dll  -> a webcam (Media Foundation)
        gdserial.dll                           -> o Arduino (porta serial)

    E ELAS NÃO PODEM SER EMBUTIDAS NO .EXE. Não é escolha nossa nem
    configuração que faltou marcar: o Godot carrega GDExtension com
    LoadLibrary, que exige um arquivo REAL no disco. Uma DLL dentro do
    .pck (ou dentro do .exe, com o PCK embutido) não tem caminho de
    disco, então não carrega. Com `embed_pck=true` o resultado é o mesmo:
    o EXE fica sozinho e a câmera some, sem erro nenhum na tela.

    Por isso a unidade de distribuição é a PASTA, e por isso este script
    existe: ele exporta, põe cada biblioteca no caminho exato que o
    .gdextension declara, junta o que falta do sistema, CONFERE arquivo
    por arquivo e só então fecha o pacote. Copiar só o EXE deixou de ser
    um erro possível porque o pacote é um ZIP e o ZIP é a pasta.

    USO
        powershell -ExecutionPolicy Bypass -File tools/exportar_windows.ps1

    OPÇÕES
        -Godot <caminho>   o executável do Godot 4.6 (senão, é procurado)
        -Preset <nome>     o preset de exportação (padrão: Windows Desktop)
        -SemRuntime        não copiar o VCRUNTIME do sistema
        -SemZip            parar na pasta, sem fechar o ZIP
#>
param(
    [string]$Godot = "",
    [string]$Preset = "Windows Desktop",
    [switch]$SemRuntime,
    [switch]$SemZip
)

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$saida = Join-Path $raiz "build\windows"
$zip = Join-Path $raiz "build\PunchChallenge-Windows-x64.zip"

function Passo([string]$texto) { Write-Host "==> $texto" }
function Aviso([string]$texto) { Write-Host "    AVISO: $texto" -ForegroundColor Yellow }

# ------------------------------------------------------------------ Godot
# ACHAR O GODOT SOZINHO. O caminho mudava a cada máquina e o script
# antigo assumia que `godot` estava no PATH -- que é justamente o que
# não acontece em instalação por ZIP, que é como quase todo mundo
# instala o Godot no Windows.
function Encontrar-Godot([string]$preferido) {
    $candidatos = New-Object System.Collections.Generic.List[string]
    if ($preferido) { $candidatos.Add($preferido) }
    if ($env:PUNCH_GODOT) { $candidatos.Add($env:PUNCH_GODOT) }
    $noPath = Get-Command "godot" -ErrorAction SilentlyContinue
    if ($noPath) { $candidatos.Add($noPath.Source) }
    $pastas = @(
        "$env:LOCALAPPDATA\Programs\Godot",
        "$env:LOCALAPPDATA\Godot",
        "$env:ProgramFiles\Godot",
        "${env:ProgramFiles(x86)}\Godot",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Desktop"
    )
    foreach ($pasta in $pastas) {
        if (-not (Test-Path $pasta)) { continue }
        Get-ChildItem -Path $pasta -Filter "Godot_v4*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*console*" } |
            Sort-Object Name -Descending |
            ForEach-Object { $candidatos.Add($_.FullName) }
    }
    foreach ($c in $candidatos) {
        if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return ""
}

Passo "procurando o Godot"
$godotExe = Encontrar-Godot $Godot
if (-not $godotExe) {
    throw "Godot nao encontrado. Passe -Godot C:\caminho\Godot_v4.6-stable_win64.exe ou defina PUNCH_GODOT."
}
# PREFERIR A VARIANTE .console.exe, QUANDO ELA EXISTE.
#
# O ZIP do Godot para Windows traz dois binarios: o normal, de subsistema
# grafico, e um `.console.exe`, que e um lanchador de CONSOLE. Para uso
# em linha de comando o segundo e o certo: ele espera, devolve codigo de
# saida e entrega a saida do Godot na ordem em que ela acontece, em vez
# de despeja-la depois que o prompt ja voltou.
$console = [System.IO.Path]::ChangeExtension($godotExe, $null) + ".console.exe"
if (Test-Path -LiteralPath $console) {
    $godotExe = $console
    Write-Host "    (usando a variante de console)"
} else {
    # SEM A VARIANTE DE CONSOLE, O LOG DO GODOT PODE VIR VAZIO.
    #
    # O binario grafico do Windows nem sempre escreve numa saida
    # redirecionada, e e dela que sai o diagnostico quando a exportacao
    # falha. O ZIP oficial do Godot traz as duas; quem extrai so o .exe
    # fica sem a que serve para linha de comando.
    Aviso "nao achei o Godot_*.console.exe ao lado deste binario."
    Aviso "Extraia o ZIP do Godot INTEIRO na mesma pasta: sem a variante de"
    Aviso "console, o log da exportacao pode sair vazio e o diagnostico cego."
}
Write-Host "    $godotExe"

# --------------------------------------------- conferencia antes de exportar
# O verificador em shell ja existia e pergunta a coisa certa (as
# extensoes estao declaradas? os binarios que elas apontam existem?).
# Se houver `sh` na maquina -- Git for Windows traz --, vale rodar.
$conferidor = Join-Path $PSScriptRoot "conferir_exportacao.sh"
$sh = Get-Command "sh" -ErrorAction SilentlyContinue
if ($sh -and (Test-Path -LiteralPath $conferidor)) {
    Passo "conferindo o projeto antes de exportar"
    # AVISO E NAO ERRO. O verificador e um script de shell; o `sh` que o
    # Git for Windows instala as vezes tropeca em caminho do Windows, e
    # um tropeco dele nao pode impedir uma exportacao que, logo adiante,
    # e conferida arquivo por arquivo por este proprio script.
    & $sh.Source $conferidor
    if ($LASTEXITCODE -ne 0) { Aviso "conferir_exportacao.sh nao passou (codigo $LASTEXITCODE)." }
}

# ---------------------------------------------------------------- exportar
#
# O GODOT NAO PODE SER CHAMADO COM `&`. AQUI ESTAVA O DEFEITO.
#
# `Godot_v4.6.1-stable_win64.exe` e um binario de SUBSISTEMA GRAFICO,
# mesmo rodando com --headless. O PowerShell NAO ESPERA um programa de
# GUI terminar quando ele e chamado com `&`: dispara e segue na hora.
#
# O resultado era exatamente o que se viu na tela: a linha seguinte
# comparava `$LASTEXITCODE`, que ainda estava VAZIO (nenhum programa de
# console havia rodado), `'' -ne 0` dava verdadeiro, e o script morria
# com "A exportacao do Godot falhou (codigo )" -- sem numero nenhum
# dentro do parenteses, que e a assinatura do defeito. Segundos depois o
# Godot terminava de exportar e despejava o log DEPOIS da mensagem de
# erro, no prompt ja devolvido.
#
# E o estrago nao era so o susto: como o script morria aqui, NADA do que
# vem depois acontecia -- nem a copia das DLLs, nem o vcruntime, nem a
# conferencia de arquitetura, nem o ZIP. A pasta ficava com o que o
# Godot tivesse escrito e mais nada, que e a origem de "levei para o
# outro PC e a camera nao funciona".
#
# `Start-Process -Wait` espera qualquer subsistema, e `-PassThru` da
# acesso ao codigo de saida de verdade.
$logSaida = Join-Path $raiz "build\godot-export.out.log"
$logErro  = Join-Path $raiz "build\godot-export.err.log"
$exeFinal = Join-Path $saida "PunchChallenge.exe"
$pckFinal = Join-Path $saida "PunchChallenge.pck"
$presetArquivo = Join-Path $raiz "export_presets.cfg"

function Invocar-Godot([string[]]$argumentos) {
    # Os argumentos vao aspeados um a um: o caminho do projeto quase
    # sempre tem espaco (`C:\Users\LAZER GAMES\...`) e o nome do preset
    # tem espaco sempre ("Windows Desktop").
    # O TrimEnd e contra um caminho terminado em barra: "C:\pasta\" faria
    # a barra escapar a propria aspa e engolir o argumento seguinte.
    $aspeados = $argumentos | ForEach-Object { '"' + $_.TrimEnd('\') + '"' }
    # A SAIDA VAI PARA ARQUIVO, e nao para a tela.
    #
    # Nao e so arrumacao: sem capturar, o unico registro do que o Godot
    # disse eram duzentas linhas de "Armazenando Arquivo" rolando no
    # console, e a UNICA linha que importava -- o erro -- se perdia no
    # meio delas ou nem aparecia. Guardada, ela pode ser procurada.
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logSaida) | Out-Null
    $p = Start-Process -FilePath $godotExe -ArgumentList $aspeados `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $logSaida -RedirectStandardError $logErro
    return $p.ExitCode
}

## O QUE O GODOT RECLAMOU. Devolve so as linhas que parecem erro.
function Erros-Do-Godot() {
    $tudo = @()
    foreach ($arquivo in @($logSaida, $logErro)) {
        if (Test-Path -LiteralPath $arquivo) {
            $tudo += Get-Content -LiteralPath $arquivo -ErrorAction SilentlyContinue
        }
    }
    return $tudo | Where-Object {
        $_ -match "ERROR|ERRO|error:|Erro|falh|fail|not found|nao encontrad|n.o encontrad|rcedit|template|Cannot|Unable"
    }
}

## A EXPORTACAO, COM OU SEM GRAVAR ICONE E VERSAO NO EXECUTAVEL.
##
## POR QUE ISTO PRECISA SER OPCIONAL. O preset tem
## `application/modify_resources=true`, que manda o Godot gravar icone,
## nome do produto e numero de versao DENTRO do .exe. Ele nao faz isso
## sozinho: chama uma ferramenta externa, o **rcedit**, que precisa
## estar apontada em Editor > Configuracoes do Editor > Export >
## Windows. Numa instalacao nova do Godot ela NAO esta.
##
## E o modo de falhar e traicoeiro: o Godot exporta o .pck para o
## destino, monta o .exe num arquivo temporario, tenta o rcedit, falha,
## e NAO MOVE o temporario para o destino. Resultado: a pasta fica com
## o .pck e sem o .exe, e o processo termina com codigo 0 -- "terminou
## sem erro e nao produziu nada", que foi exatamente o que apareceu.
##
## Sem gravar os recursos, o executavel sai com o icone padrao do Godot
## e funciona igual. Para um gabinete que abre em tela cheia no logon,
## o icone do .exe nao e visto por ninguem.
function Exportar([bool]$comRecursos) {
    $original = $null
    if (-not $comRecursos) {
        $original = [System.IO.File]::ReadAllText($presetArquivo)
        $texto = $original -replace 'application/modify_resources=true', 'application/modify_resources=false'
        # WriteAllText do .NET grava UTF-8 SEM BOM. Um BOM aqui faria o
        # Godot tropecar na primeira linha do proprio preset.
        [System.IO.File]::WriteAllText($presetArquivo, $texto)
    }
    try {
        return Invocar-Godot @("--headless", "--path", $raiz, "--export-release", $Preset)
    } finally {
        if ($null -ne $original) {
            [System.IO.File]::WriteAllText($presetArquivo, $original)
        }
    }
}

## O ANTIVIRUS COMEU O EXECUTAVEL?
##
## E a outra causa classica de "o Godot disse que exportou e nao ha
## .exe": o Defender apaga o arquivo no instante em que ele e escrito.
## Binario de template de motor de jogo, recem-criado, sem assinatura --
## e o retrato do que a heuristica marca.
function Antivirus-Reclamou() {
    try {
        $achados = Get-MpThreatDetection -ErrorAction SilentlyContinue |
            Where-Object { "$($_.Resources)" -match "PunchChallenge|punch-challenge" } |
            Sort-Object InitialDetectionTime -Descending |
            Select-Object -First 3
        return $achados
    } catch { return $null }
}

function Mostrar-Diagnostico() {
    $erros = Erros-Do-Godot
    if ($erros) {
        Write-Host "    o Godot reclamou disto:" -ForegroundColor Yellow
        foreach ($linha in ($erros | Select-Object -First 12)) { Write-Host "      $linha" }
    } else {
        Write-Host "    o Godot nao imprimiu erro nenhum (log em $logSaida)."
    }
    Write-Host "    o que existe na pasta agora:"
    $existe = Get-ChildItem -Path $saida -Recurse -File -ErrorAction SilentlyContinue
    if ($existe) {
        foreach ($f in $existe) { Write-Host ("      {0,12:N0}  {1}" -f $f.Length, $f.Name) }
    } else {
        Write-Host "      (nada)"
    }
    $praga = Antivirus-Reclamou
    if ($praga) {
        Write-Host ""
        Write-Host "    O ANTIVIRUS APAGOU O EXECUTAVEL:" -ForegroundColor Red
        foreach ($d in $praga) { Write-Host "      $($d.ThreatID) em $($d.InitialDetectionTime)" }
        Write-Host "    Libere a pasta (num PowerShell COMO ADMINISTRADOR):"
        Write-Host "      Add-MpPreference -ExclusionPath '$raiz'"
    }
}

Passo "exportando com o preset '$Preset'"
if (Test-Path $saida) { Remove-Item -Recurse -Force $saida }
New-Item -ItemType Directory -Force -Path $saida | Out-Null
$codigo = Exportar $true

if (-not (Test-Path -LiteralPath $exeFinal)) {
    Aviso "o Godot terminou (codigo $codigo) e nao escreveu PunchChallenge.exe."
    Mostrar-Diagnostico
    if (Test-Path -LiteralPath $pckFinal) {
        # O .pck NO LUGAR e o .exe AUSENTE e a assinatura do rcedit: o
        # Godot chegou a empacotar tudo e so tropecou na hora de gravar
        # icone e versao no executavel.
        Passo "tentando de novo SEM gravar icone e versao no .exe (dispensa o rcedit)"
        $codigo = Exportar $false
    }
}

if (-not (Test-Path -LiteralPath $exeFinal)) {
    Mostrar-Diagnostico
    throw @"
A exportacao nao produziu PunchChallenge.exe (codigo $codigo).

As tres causas possiveis, na ordem em que valem ser conferidas:

  1. MODELOS DE EXPORTACAO ausentes ou de outra versao. No Godot:
     Editor > Gerenciar modelos de exportacao > Baixar e instalar.
     Tem de ser exatamente 4.6.1-stable.
  2. ANTIVIRUS apagando o .exe recem-criado. Veja o diagnostico acima;
     se houver deteccao, libere a pasta com Add-MpPreference.
  3. RCEDIT nao configurado -- esta tentativa ja tentou contornar
     desligando application/modify_resources. Se ainda falhou, nao era
     isso.

O log completo do Godot esta em:
  $logSaida
  $logErro
"@
}
if (-not (Test-Path -LiteralPath $pckFinal)) {
    throw "O executavel saiu mas nao ha PunchChallenge.pck. O pacote estaria incompleto."
}
Write-Host "    exportou: $exeFinal"

# ------------------------------------------------------- bibliotecas nativas
# Nao depende do exportador adivinhar onde por as bibliotecas. Copia cada
# backend para o mesmo caminho declarado no .gdextension, preservando a
# estrutura que o carregador resolve a partir de res://.
Passo "copiando as bibliotecas nativas"
$nativas = @(
    "addons\CameraServerExtension\x86_64\libcameraserver-extension.windows.dll",
    "addons\gdserial\bin\windows-x86_64\gdserial.dll"
)
foreach ($relativo in $nativas) {
    $origem = Join-Path $raiz $relativo
    if (-not (Test-Path -LiteralPath $origem)) { throw "Biblioteca ausente no projeto: $relativo" }
    $destino = Join-Path $saida $relativo
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destino) | Out-Null
    Unblock-File -LiteralPath $origem -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $origem -Destination $destino -Force
    Unblock-File -LiteralPath $destino -ErrorAction SilentlyContinue
    Write-Host "    $relativo"
}

# ------------------------------------------------ o runtime do Visual C++
# POR QUE ISTO ENTROU, E POR QUE SO PARA UMA DAS DUAS DLLS.
#
# Lendo a tabela de importacoes das duas bibliotecas:
#
#   libcameraserver-extension.windows.dll  ->  MF, MFPlat, MFReadWrite,
#       ole32, advapi32, kernel32, shlwapi.  TUDO do proprio Windows.
#       Ou seja: a CAMERA NAO PRECISA do Visual C++ Redistributable, ao
#       contrario do que a documentacao do projeto dizia. Quem exigia era
#       a outra.
#   gdserial.dll  ->  VCRUNTIME140.dll, alem de api-ms-win-crt-* (que sao
#       o UCRT, ja incluido no Windows 10 e 11).
#
# Entao o que falta numa maquina limpa e UM arquivo, e a Microsoft
# permite entrega-lo ao lado do executavel (app-local deployment). Com
# ele na pasta, instalar o redistributable deixa de ser pre-requisito --
# e "o sensor nao funciona nesse PC" deixa de depender de um instalador
# que ninguem lembra de rodar.
if (-not $SemRuntime) {
    Passo "copiando o runtime do Visual C++ ao lado do executavel"
    $sistema = Join-Path $env:SystemRoot "System32"
    $obrigatorio = @("vcruntime140.dll")
    $opcionais = @("vcruntime140_1.dll", "msvcp140.dll")
    foreach ($nome in ($obrigatorio + $opcionais)) {
        $origem = Join-Path $sistema $nome
        if (Test-Path -LiteralPath $origem) {
            Copy-Item -LiteralPath $origem -Destination (Join-Path $saida $nome) -Force
            Write-Host "    $nome"
        } elseif ($obrigatorio -contains $nome) {
            Aviso "$nome nao esta em System32 desta maquina."
            Aviso "O pacote sai sem ele e o PC de destino vai precisar do"
            Aviso "Visual C++ 2015-2022 Redistributable x64 para o sensor."
        }
    }
}

# --------------------------------------------------------------- conferir
# CONFERIR E ARQUITETURA, E NAO SO PRESENCA.
#
# Um .dll de 32 bits ou de ARM64 na pasta passa em qualquer teste de
# "o arquivo esta la" e falha exatamente igual a um arquivo ausente:
# LoadLibrary recusa em silencio e a camera some sem erro na tela.
function Get-MaquinaPE([string]$caminho) {
    $fs = [System.IO.File]::OpenRead($caminho)
    try {
        $buf = New-Object byte[] 4
        $fs.Position = 0x3C
        [void]$fs.Read($buf, 0, 4)
        $fs.Position = [BitConverter]::ToInt32($buf, 0) + 4
        [void]$fs.Read($buf, 0, 2)
        return [BitConverter]::ToUInt16($buf, 0)
    } finally { $fs.Dispose() }
}

Passo "conferindo o pacote"
$X64 = 0x8664
$obrigatorios = @(
    "PunchChallenge.exe",
    "PunchChallenge.pck",
    "gdserial.dll",
    "libcameraserver-extension.windows.dll"
)
$inventario = @()
foreach ($nome in $obrigatorios) {
    $achado = Get-ChildItem -Path $saida -Recurse -File -Filter $nome | Select-Object -First 1
    if (-not $achado) { throw "Pacote incompleto: faltou $nome" }
    $relativo = $achado.FullName.Substring($saida.Length).TrimStart('\')
    if ($nome -like "*.dll" -or $nome -like "*.exe") {
        $maquina = Get-MaquinaPE $achado.FullName
        if ($maquina -ne $X64) {
            throw ("$relativo nao e x86_64 (machine 0x{0:X}). O jogo e x86_64: essa DLL nunca vai carregar." -f $maquina)
        }
    }
    $hash = (Get-FileHash -LiteralPath $achado.FullName -Algorithm SHA256).Hash
    $inventario += ("{0}  {1}  {2:N0} bytes" -f $hash.Substring(0, 16), $relativo, $achado.Length)
    Write-Host "    ok  $relativo"
}
$sobras = Get-ChildItem -Path $saida -Recurse -File -Filter "~*.dll" -ErrorAction SilentlyContinue
if ($sobras) { throw "Ha copias '~' de DLL na pasta exportada. Feche o editor do Godot e exporte de novo." }

# ------------------------------------------------------- o que vai na pasta
$instalador = Join-Path $PSScriptRoot "instalar_startup.ps1"
if (Test-Path -LiteralPath $instalador) {
    Copy-Item -LiteralPath $instalador -Destination (Join-Path $saida "instalar_startup.ps1") -Force
}

$leia = @"
PUNCH CHALLENGE - WINDOWS x64

1. Extraia este ZIP INTEIRO em uma pasta.
2. Execute PunchChallenge.exe de dentro da pasta extraida.

NAO MOVA SO O EXE. A camera e o sensor sao bibliotecas nativas e o Godot
so consegue carrega-las como arquivo separado, ao lado do executavel --
nao ha como embuti-las dentro do .exe. Sem elas o jogo abre normalmente,
sem camera e sem sensor, e SEM MENSAGEM DE ERRO. E o motivo numero um de
"funciona na sua maquina e na minha nao".

PARA DEIXAR O JOGO ABRINDO SOZINHO COM O WINDOWS:

    powershell -ExecutionPolicy Bypass -File instalar_startup.ps1

Ele copia a pasta para um lugar fixo, registra a abertura automatica no
logon e confere as bibliotecas antes de registrar. Para desfazer:

    powershell -ExecutionPolicy Bypass -File instalar_startup.ps1 -Desinstalar

INVENTARIO DESTE PACOTE (SHA256 abreviado)
$($inventario -join "`r`n")
"@
Set-Content -LiteralPath (Join-Path $saida "LEIA-ANTES-DE-EXECUTAR.txt") -Value $leia -Encoding UTF8

Passo "o que ficou na pasta"
Get-ChildItem -Path $saida -Recurse -File |
    Sort-Object FullName |
    ForEach-Object {
        Write-Host ("    {0,10:N0}  {1}" -f $_.Length, $_.FullName.Substring($saida.Length).TrimStart('\'))
    }

if (-not $SemZip) {
    Passo "fechando o ZIP"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Compress-Archive -Path (Join-Path $saida "*") -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "PACOTE_OK $zip"
} else {
    Write-Host "PACOTE_OK $saida"
}
