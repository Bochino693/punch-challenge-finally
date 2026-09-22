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
        -Conferir           so diagnostica a CAMERA nesta maquina e sai
#>
param(
    [string]$Origem = "",
    [string]$Destino = "",
    [switch]$SoRegistrar,
    [switch]$Desinstalar,
    [switch]$Apagar,
    [switch]$Conferir
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

# ----------------------------------------------------------- a camera
#
# POR QUE ISTO VIVE AQUI, E NAO SO DENTRO DO JOGO.
#
# "A camera nao funciona nessa maquina" e o defeito que mais custou
# tempo neste projeto, e ele tem cinco causas possiveis -- quatro delas
# do WINDOWS da maquina de destino, nenhuma do cabo. Descobrir qual e
# DEPOIS de montar o gabinete, pelo F9 do jogo, e tarde: a conferencia
# tem de caber antes, na mesma pasta que acabou de ser copiada, sem
# abrir o jogo.
function Conferir-Camera([string]$pasta) {
    $ok = $true
    Passo "conferindo a camera nesta maquina"

    # 1. A DLL veio junto? E o caso numero um: copiaram so o EXE.
    $dll = Join-Path $pasta "addons\CameraServerExtension\x86_64\libcameraserver-extension.windows.dll"
    if (Test-Path -LiteralPath $dll) {
        Write-Host "    ok   a DLL da camera esta na pasta"
    } else {
        Write-Host "    FALTA a DLL da camera" -ForegroundColor Red
        Write-Host "         $dll"
        Write-Host "         O jogo abre igual, SEM camera e SEM erro. Copie a pasta INTEIRA."
        return $false
    }

    # 2. Ela e x86_64? Um binario de outra arquitetura falha exatamente
    #    como um arquivo ausente: LoadLibrary recusa em silencio.
    $fs = [System.IO.File]::OpenRead($dll)
    try {
        $buf = New-Object byte[] 4
        $fs.Position = 0x3C; [void]$fs.Read($buf, 0, 4)
        $fs.Position = [BitConverter]::ToInt32($buf, 0) + 4
        [void]$fs.Read($buf, 0, 2)
        $maquina = [BitConverter]::ToUInt16($buf, 0)
    } finally { $fs.Dispose() }
    if ($maquina -eq 0x8664) {
        Write-Host "    ok   a DLL e x86_64"
    } else {
        Write-Host ("    RUIM a DLL nao e x86_64 (machine 0x{0:X})" -f $maquina) -ForegroundColor Red
        $ok = $false
    }
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        Write-Host "    RUIM este Windows e ARM64 e a extensao so traz x86_64" -ForegroundColor Red
        $ok = $false
    }

    # 3. O Windows tem Media Foundation? As edicoes N e KN da Europa e o
    #    Windows Server sem o recurso de midia nao tem -- e a DLL da
    #    camera chama MF.dll, MFPlat.dll e MFReadWrite.dll diretamente.
    $faltaMF = @()
    foreach ($nome in @("MF.dll", "MFPlat.dll", "MFReadWrite.dll")) {
        if (-not (Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32\$nome"))) { $faltaMF += $nome }
    }
    if ($faltaMF.Count -eq 0) {
        Write-Host "    ok   Media Foundation presente"
    } else {
        Write-Host "    RUIM falta Media Foundation: $($faltaMF -join ', ')" -ForegroundColor Red
        Write-Host "         Edicao N/KN ou Windows Server: instale o Media Feature Pack."
        $ok = $false
    }

    # 4. A privacidade da webcam esta aberta para programas de area de
    #    trabalho? O jogo libera isso sozinho, mas dizer aqui evita a
    #    caca ao tesouro.
    $consent = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam\NonPackaged"
    $valor = (Get-ItemProperty -Path $consent -Name Value -ErrorAction SilentlyContinue).Value
    if ($valor -eq "Deny") {
        Aviso "a privacidade da webcam esta BLOQUEADA para programas de area de trabalho."
        Aviso "O jogo tenta liberar sozinho no arranque; se nao conseguir, abra"
        Aviso "Configuracoes > Privacidade > Camera e ligue o interruptor."
    } else {
        Write-Host "    ok   privacidade da webcam liberada ($(if ($valor) { $valor } else { 'padrao' }))"
    }

    # 5. O Windows enxerga alguma camera? Se nao enxerga, ai sim e cabo,
    #    porta USB ou driver -- e so aqui essa acusacao e honesta.
    $cams = @()
    try {
        $saida = & pnputil.exe /enum-devices /class Camera /connected 2>$null
        foreach ($linha in $saida) {
            if ($linha -match "Instance ID:\s*(.+)$" -or $linha -match "Inst.ncia:\s*(.+)$") {
                $cams += $Matches[1].Trim()
            }
        }
    } catch { }
    if ($cams.Count -gt 0) {
        Write-Host "    ok   o Windows ve $($cams.Count) camera(s):"
        foreach ($c in $cams) {
            $barramento = if ($c -like "USB\*") { "USB" } else { "outro barramento" }
            Write-Host "         $barramento  $c"
        }
        if ($cams.Count -gt 1) {
            Write-Host "         Ha mais de uma. O jogo prefere a externa; se ele pegar a"
            Write-Host "         errada, espete a USB com o jogo JA ABERTO -- a que nasce"
            Write-Host "         depois vence qualquer nome."
        }
    } else {
        Aviso "o Windows nao enumerou camera nenhuma (ou este Windows nao tem pnputil)."
        Aviso "Se o Gerenciador de Dispositivos tambem nao mostra, ai e cabo, porta ou driver."
    }
    return $ok
}

if ($Conferir) {
    $alvo = if ($Origem) { $Origem } else { $PSScriptRoot }
    if (-not (Test-Path -LiteralPath (Join-Path $alvo $EXE))) {
        $alt = Join-Path $alvo "build\windows"
        if (Test-Path -LiteralPath (Join-Path $alt $EXE)) { $alvo = $alt }
    }
    if (Conferir-Camera $alvo) { Write-Host "CAMERA_OK" } else { Write-Host "CAMERA_COM_PROBLEMA" }
    exit 0
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

# A CONFERENCIA DA CAMERA FECHA A INSTALACAO. E o momento certo: a
# pasta acabou de ser copiada para esta maquina, e e desta maquina que
# se trata a pergunta.
Write-Host ""
Conferir-Camera $Destino | Out-Null

Write-Host ""
Write-Host "INSTALADO_OK $Destino"
Write-Host "Para testar sem reiniciar:  Start-Process '$alvo'"
Write-Host "Para desfazer:              powershell -ExecutionPolicy Bypass -File instalar_startup.ps1 -Desinstalar"
