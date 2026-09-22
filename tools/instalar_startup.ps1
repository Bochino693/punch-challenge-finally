<#
    INSTALA O PUNCH CHALLENGE E O FAZ ABRIR SOZINHO COM O WINDOWS.

    POR QUE NAO E UM ARQUIVO SO

    O jogo nao pode ser um unico .exe. A camera e o sensor sao
    bibliotecas nativas (GDExtension) e o Godot as carrega com
    LoadLibrary, que exige arquivo real no disco -- uma DLL dentro do
    .pck ou do .exe nao tem caminho de disco e nao carrega. Marcar
    "embed PCK" nao muda isso: o EXE fica sozinho e a camera some em
    silencio.

    A saida nao e empacotar: e INSTALAR. Este script copia a pasta
    inteira para um lugar fixo da maquina e registra a abertura
    automatica apontando para la. Depois disso o gabinete liga e o jogo
    sobe direto do disco, sem extrair nada, sem tela preta de
    descompactacao e sem antivirus reclamando de auto-extraivel.

    USO (na pasta exportada, ao lado de PunchChallenge.exe)
        powershell -ExecutionPolicy Bypass -File instalar_startup.ps1

    OPCOES
        -Origem <pasta>     de onde copiar (padrao: a pasta deste script)
        -Destino <pasta>    onde instalar (padrao: %LOCALAPPDATA%\PunchChallenge)
        -SoRegistrar        nao copia nada, so registra a abertura automatica
        -Desinstalar        tira a abertura automatica (nao apaga os arquivos)
        -Apagar             com -Desinstalar, apaga tambem a pasta instalada
#>
param(
    [string]$Origem = "",
    [string]$Destino = "",
    [switch]$SoRegistrar,
    [switch]$Desinstalar,
    [switch]$Apagar
)

$ErrorActionPreference = "Stop"

$TAREFA = "PunchChallenge"
$CHAVE_RUN = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$EXE = "PunchChallenge.exe"

# AS QUATRO PECAS QUE PRECISAM ESTAR JUNTAS. O EXE sozinho abre e parece
# certo; e por isso que conferir so o EXE nunca pegou este defeito.
$ESSENCIAIS = @(
    "PunchChallenge.exe",
    "PunchChallenge.pck",
    "addons\CameraServerExtension\x86_64\libcameraserver-extension.windows.dll",
    "addons\gdserial\bin\windows-x86_64\gdserial.dll"
)

function Passo([string]$t) { Write-Host "==> $t" }
function Aviso([string]$t) { Write-Host "    AVISO: $t" -ForegroundColor Yellow }

if (-not $Destino) { $Destino = Join-Path $env:LOCALAPPDATA "PunchChallenge" }

# ----------------------------------------------------------- desinstalar
function Remover-Abertura-Automatica() {
    $tirou = $false
    $tarefa = Get-ScheduledTask -TaskName $TAREFA -ErrorAction SilentlyContinue
    if ($tarefa) {
        Unregister-ScheduledTask -TaskName $TAREFA -Confirm:$false
        Write-Host "    tarefa agendada '$TAREFA' removida"
        $tirou = $true
    }
    $run = Get-ItemProperty -Path $CHAVE_RUN -Name $TAREFA -ErrorAction SilentlyContinue
    if ($run) {
        Remove-ItemProperty -Path $CHAVE_RUN -Name $TAREFA
        Write-Host "    entrada de Run removida"
        $tirou = $true
    }
    if (-not $tirou) { Write-Host "    nao havia abertura automatica registrada" }
}

if ($Desinstalar) {
    Passo "removendo a abertura automatica"
    Remover-Abertura-Automatica
    if ($Apagar -and (Test-Path -LiteralPath $Destino)) {
        Passo "apagando $Destino"
        Remove-Item -Recurse -Force -LiteralPath $Destino
    } elseif (Test-Path -LiteralPath $Destino) {
        Write-Host "    os arquivos continuam em $Destino (use -Apagar para remover)"
    }
    Write-Host "DESINSTALADO_OK"
    exit 0
}

# --------------------------------------------------------------- conferir
if (-not $Origem) { $Origem = $PSScriptRoot }
$Origem = (Resolve-Path -LiteralPath $Origem).Path

# Tolera ser chamado da raiz do projeto: a pasta exportada e build\windows.
if (-not (Test-Path -LiteralPath (Join-Path $Origem $EXE))) {
    $alternativa = Join-Path $Origem "build\windows"
    if (Test-Path -LiteralPath (Join-Path $alternativa $EXE)) { $Origem = $alternativa }
}

if (-not $SoRegistrar) {
    Passo "conferindo a pasta de origem"
    Write-Host "    $Origem"
    $faltando = @()
    foreach ($relativo in $ESSENCIAIS) {
        if (-not (Test-Path -LiteralPath (Join-Path $Origem $relativo))) { $faltando += $relativo }
    }
    if ($faltando.Count -gt 0) {
        Write-Host ""
        Write-Host "PACOTE INCOMPLETO. Faltam nesta pasta:" -ForegroundColor Red
        foreach ($f in $faltando) { Write-Host "    $f" -ForegroundColor Red }
        Write-Host ""
        Write-Host "Provavelmente so o EXE foi copiado. Exporte de novo com"
        Write-Host "tools/exportar_windows.ps1 e use a pasta INTEIRA."
        exit 1
    }
    foreach ($relativo in $ESSENCIAIS) { Write-Host "    ok  $relativo" }

    # ------------------------------------------------------------- copiar
    Passo "instalando em $Destino"
    New-Item -ItemType Directory -Force -Path $Destino | Out-Null
    # /MIR deixa o destino identico a origem: uma atualizacao nao pode
    # deixar para tras a DLL de uma versao anterior.
    $log = & robocopy $Origem $Destino /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:2
    if ($LASTEXITCODE -ge 8) {
        Write-Host $log
        throw "A copia falhou (robocopy $LASTEXITCODE)."
    }
    # `-Include` junto com `-Recurse` e um caminho sem curinga devolve
    # vazio em silencio -- pegadinha classica do PowerShell. Filtrar
    # depois e o que funciona em qualquer versao.
    Get-ChildItem -Path $Destino -Recurse -File |
        Where-Object { $_.Extension -in ".dll", ".exe" } |
        ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }
    Write-Host "    copiado"
}

$alvo = Join-Path $Destino $EXE
if (-not (Test-Path -LiteralPath $alvo)) { throw "Nao ha $EXE em $Destino." }

# --------------------------------------------------- abertura automatica
#
# TAREFA AGENDADA, E NAO A CHAVE RUN, QUANDO DA.
#
# A chave Run funciona, mas o Windows aplica a ela o atraso de inicio de
# aplicativos de logon e nao tem como reabrir o jogo se ele fechar. Uma
# tarefa de logon sobe sem esse atraso e aceita "reiniciar em caso de
# falha", que e o que um gabinete de salao precisa: ninguem vai estar la
# com teclado se o jogo cair. Se a maquina recusar o agendamento (conta
# restrita, politica), cai na chave Run, que funciona em qualquer
# Windows.
Passo "registrando a abertura automatica"
Remover-Abertura-Automatica

$registrou = $false
try {
    $acao = New-ScheduledTaskAction -Execute $alvo -WorkingDirectory $Destino
    $gatilho = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    # Sem atraso: e o que o pedido de "rodar instantaneo" quer dizer.
    $gatilho.Delay = "PT0S"
    $config = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -DontStopOnIdleEnd `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -StartWhenAvailable
    $config.DisallowStartIfOnBatteries = $false
    Register-ScheduledTask -TaskName $TAREFA -Action $acao -Trigger $gatilho `
        -Settings $config -Description "Abre o Punch Challenge no logon." `
        -Force | Out-Null
    Write-Host "    tarefa agendada '$TAREFA' (logon, sem atraso, reinicia se cair)"
    $registrou = $true
} catch {
    Aviso "nao deu para criar a tarefa agendada: $($_.Exception.Message)"
}

if (-not $registrou) {
    New-Item -Path $CHAVE_RUN -Force | Out-Null
    Set-ItemProperty -Path $CHAVE_RUN -Name $TAREFA -Value ('"{0}"' -f $alvo)
    Write-Host "    entrada de Run criada (alternativa a tarefa agendada)"
}

# ---------------------------------------------------------------- conferir
Passo "conferindo o que ficou registrado"
$tarefa = Get-ScheduledTask -TaskName $TAREFA -ErrorAction SilentlyContinue
if ($tarefa) {
    Write-Host "    tarefa: $($tarefa.State)"
} else {
    $run = Get-ItemProperty -Path $CHAVE_RUN -Name $TAREFA -ErrorAction SilentlyContinue
    if ($run) { Write-Host "    Run: $($run.$TAREFA)" } else { throw "Nada ficou registrado." }
}

Write-Host ""
Write-Host "INSTALADO_OK $Destino"
Write-Host "Para testar sem reiniciar:  Start-Process '$alvo'"
Write-Host "Para desfazer:              powershell -ExecutionPolicy Bypass -File instalar_startup.ps1 -Desinstalar"
