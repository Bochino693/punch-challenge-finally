# Câmera nativa no Windows

O jogo captura webcams USB diretamente pelo **Windows Media Foundation**,
através do addon `CameraServerExtension`. O pacote já contém a DLL x86_64;
não há Python, OpenCV, serviço ou driver virtual para instalar.

## Uso

1. Conecte a câmera USB.
2. Abra o jogo.
3. Pressione F9 para ver a prévia e usar **TESTAR FOTO**.

Se a câmera for conectada depois da abertura, a descoberta é repetida a cada
2,5 segundos somente enquanto não existe um feed. **PROCURAR DE NOVO** força
a enumeração imediatamente. Depois que o vídeo abre, o jogo mantém o mesmo
feed ativo; ele não reinicia a câmera por atraso ou por foto.

## Vídeo e fotografia

- A prévia é uma `CameraTexture`, atualizada diretamente pelo backend nativo.
- O formato preferido é 1280×720 a 30 fps; 4K recebe baixa prioridade para
  evitar carga USB/GPU desnecessária.
- Durante a pose, o obturador escolhe o melhor quadro recebido.
- Somente o retrato escolhido fica congelado brevemente. O feed ao vivo não é
  fechado e a gravação JPEG do ranking ocorre fora da linha principal.

## Diagnóstico

`scripts/camera_doctor.gd` separa os quatro casos possíveis, em ordem:

1. **falta a extensão nativa ao lado do jogo** — a primeira pergunta,
   porque sem ela todo o resto é irrelevante;
2. **o Windows também não vê a câmera** — cabo, porta USB ou driver;
3. **a privacidade está fechada** para aplicativos de área de trabalho;
4. **outro programa está com a câmera aberta** — só um por vez pode.

Ele pergunta isso ao `reg.exe`, ao `tasklist.exe` e ao `pnputil.exe`, que
já estão em qualquer Windows. Nada abre o fluxo de vídeo e nada disputa a
webcam com o jogo. **RESOLVER ACESSO** grava, no ramo do usuário, o mesmo
valor que o aplicativo Configurações grava quando alguém move o
interruptor à mão — não pede elevação e é reversível pelo mesmo caminho.

Antes isto era um `.ps1` que o jogo precisava desembrulhar do pacote para
o AppData e executar com `-ExecutionPolicy Bypass`. Era um arquivo a mais
para o antivírus examinar, uma política a mais para uma máquina
corporativa barrar — justamente na tela em que o operador foi pedir
socorro — e quase um segundo só para o PowerShell subir.

## Exportação

Execute `tools/exportar_windows.ps1`. Ele exporta para Windows x86_64,
confere `libcameraserver-extension.windows.dll` e `gdserial.dll` e cria um
ZIP único para transporte. Na outra máquina, extraia o ZIP inteiro e execute
o jogo dentro da pasta. `sh tools/conferir_exportacao.sh` também valida o
projeto antes da exportação.

## Arduino

A câmera e a serial são addons independentes. Nenhum arquivo em `arduino/`,
`scripts/serial/` ou `addons/gdserial/` é alterado por esta integração.

## Origem e licença

`CameraServerExtension` é distribuído sob licença MIT. A licença original
está em `addons/CameraServerExtension/LICENSE`.
