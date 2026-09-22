# Protocolo serial — variante óptica LM393

> Firmware em uso: `ARDUINO_SENSOR_DE_FEIXE_LM393/ARDUINO_SENSOR_DE_FEIXE_LM393.ino`.
> O jogo envia `ARM` antes de cada tentativa. O firmware aceita exatamente
> um `HIT` e só rearma ao receber outro `ARM`, garantindo primeiro e segundo
> socos independentes. As seções antigas sobre MPU abaixo ficam apenas como
> referência histórica e não descrevem a montagem desta Build 58.

Conversa entre o firmware `arduino/punch_sensor/punch_sensor.ino` e o
jogo em Godot. **115200 bps, 8N1.** Uma mensagem por linha, terminada em
`\n`, campos separados por vírgula, sem espaços.

O firmware **mede**; o jogo **pontua**. O Arduino nunca manda pontos, só
velocidade, aceleração e duração — quem transforma isso em 0 a 999 é a
Central Técnica do jogo, e é por isso que dá para recalibrar uma máquina
sem regravar a placa.

Quem faz o *parse* do lado do jogo é `scripts/arduino_protocol.gd`.
**Linha malformada é descartada ali**, antes de chegar à tela: campo
faltando, número inválido ou valor fora da faixa física viram
`{"type": ""}` e o jogo simplesmente ignora. Um cabo com ruído atrapalha
a medição, mas não faz a máquina pontuar errado.

---

## Placa → jogo

| Mensagem | Formato | Quando |
| --- | --- | --- |
| `READY` | `READY,PUNCH_MPU6050,V2` | Uma vez, no fim do `setup()`. O jogo responde mandando `CONFIG`. |
| `CALIBRATING` | `CALIBRATING,<0-100>` | Durante a medida do repouso, para a tela mostrar o progresso. |
| `CALIBRATED` | `CALIBRATED,<offX>,<offY>,<offZ>` | Fim da calibração. Offsets em g, 3 casas. |
| `PONG` | `PONG` | Resposta ao `PING`. É o sinal de vida da conexão. |
| `BUTTON` | `BUTTON,START` ou `BUTTON,CREDIT` | Botão do gabinete apertado (D2 e D3). |
| `TELEMETRY` | `TELEMETRY,ax,ay,az,gx,gy,gz,vel,pico_g` | A cada 250 ms, **fora** de um golpe. Aceleração em g, giro em °/s. |
| `HIT` | `HIT,<vel_pico>,<accel_pico>,<duracao_ms>,<eixo>` | Um golpe terminou de ser medido. |
| `SATURATION` | `SATURATION,ACCEL` ou `SATURATION,GYRO` | O golpe passou do fundo de escala (±16 g / ±2000 °/s): a medida saiu por baixo do valor real. |
| `ERROR` | `ERROR,<CÓDIGO>` | `NO_MPU`, `MPU_LEITURA`, `PARAM`, `COMANDO_DESCONHECIDO`. |
| `OK` | `OK,<COMANDO>` | Confirmação de `RESET`, `CALIBRATE` e `CONFIG`. |

### Limites aceitos em `HIT`

O jogo rejeita a linha inteira se algum campo cair fora destas faixas —
são limites do que um saco de pancadas consegue fisicamente fazer:

| Campo | Faixa aceita |
| --- | --- |
| velocidade de pico | 0 a 60 m/s |
| aceleração de pico | 0 a 17 g |
| duração | maior que 0 e até 5000 ms |
| eixo | `X`, `Y` ou `Z` |

**Um `HIT` fora da janela do soco não vira ponto.** Se o saco balançar
sozinho, ou alguém encostar nele entre uma partida e outra, a medida
aparece só na linha de diagnóstico da Central Técnica.

---

## Jogo → placa

| Comando | Formato | Efeito |
| --- | --- | --- |
| `PING` | `PING` | Pede um `PONG`. O jogo manda a cada 5 s; sem resposta por 9 s, a tela passa a `SEM RESPOSTA`. |
| `RESET` | `RESET` | Abandona a medição em andamento. |
| `CALIBRATE` | `CALIBRATE` | Remede o repouso. **O saco precisa estar parado.** |
| `TEST` | `TEST` | Devolve um `HIT` sintético (`HIT,7.50,9.20,120,<eixo>`). |
| `CONFIG` | `CONFIG,<polaridade>,<palheta>,<vmin>,<pulso_min_ms>[,<vmax>]` | Configura a medição. O 5º campo é opcional. |
| `LEDS` | `LEDS,<0..1000>` | Altura da coluna das duas fitas, em por mil. |

### `LEDS` e as duas fitas do gabinete

O gabinete tem duas fitas endereçáveis (WS2812B), uma de cada lado,
subindo. Elas são o placar que se lê do outro lado do salão: ninguém lê
`9610` a dez metros, mas todo mundo vê a coluna de luz subir até o topo e
estourar em branco.

`LEDS,0` a `LEDS,1000` diz a altura da coluna. **Quem manda é o jogo,
enquanto o placar sobe na tela** — assim a fita acompanha o *número
subindo*, e não o golpe cru. As duas coisas no mesmo compasso é o que faz
a máquina parecer uma peça só, em vez de um monitor com uma fita
pendurada do lado. O jogo manda no máximo doze por segundo; a placa
interpola entre um comando e o seguinte, então a subida sai lisa sem
entupir a serial.

**A placa se vira sozinha quando o jogo cala.** Passados 3 s sem `LEDS`,
ela volta a mapear a própria medição entre `vmin` e `vmax` — e é por isso
que o 5º campo do `CONFIG` existe. Com o PC desligado a máquina continua
tendo fita: coluna que sobe no soco, desce devagar, e uma onda lenta de
espera quando não há ninguém. Fita apagada é máquina que parece
quebrada, e ninguém põe ficha em máquina quebrada.

Ligação, e ela importa: dado da fita esquerda em `D5`, direita em `D6`,
cada uma com 330 Ω em série. **Alimentação das fitas por fonte de 5 V
própria, nunca pelo Arduino** — trinta LEDs por fita no brilho máximo
pedem quase dois amperes, e tirar isso do regulador do Uno queima a
placa. O único fio que volta ao Arduino é o **GND**, que precisa ser
comum. Um capacitor de 1000 µF entre +5 V e GND, junto do primeiro LED,
segura o pico da ligada.

Biblioteca: **Adafruit NeoPixel**, pelo Gerenciador de Bibliotecas da IDE
do Arduino. Sem ela o sketch não compila.

### `CONFIG` em detalhe

`CONFIG,A,0.020,0.80,1.75,5.20`

| Campo | Unidade | Faixa | O que é |
| --- | --- | --- | --- |
| polaridade | `A` `H` `L` | — | Nível do sinal D0 com a fenda BLOQUEADA. `A` descobre sozinho na calibração. |
| palheta | metros | 0,005 a 0,100 | Largura da palheta que atravessa a fenda. É ela que converte duração em velocidade: `v = palheta ÷ duração`. |
| vmin | m/s | 0,2 a 20,0 | Abaixo disso a placa nem reporta o golpe. |
| pulso_min_ms | **milissegundos** | 0,15 a 20,0 | Duração mínima de bloqueio que ainda conta como soco. |

### Cuidado com o quarto campo: ele é um TETO DE VELOCIDADE ao contrário

Este é o campo que já custou uma máquina inteira, e vale entender por quê
antes de mexer nele.

A palheta atravessa a fenda, então **quanto mais forte o soco, mais curto
o pulso**. Exigir um pulso mínimo MAIOR não deixa a máquina mais
sensível: deixa-a cega para os socos rápidos. Com uma palheta de 20 mm,
um `pulso_min_ms` de 5,00 manda a placa recusar como `CURTO` tudo acima
de **4 m/s** — ou seja, justamente os melhores golpes da noite, e em
silêncio, porque a recusa não aparece para quem está jogando.

Pior: na versão do firmware para acelerômetro, este mesmo quarto campo
era um limiar em **g** (e a versão antiga deste documento o descrevia
assim). O assistente de calibração continuou mandando um número em g para
um campo que o firmware óptico lê em milissegundos, e esse número vinha
de uma medição de ruído — bastava um soco escapar no passo de REPOUSO
para a máquina se estrangular sozinha, gravar isso em disco e continuar
estrangulada depois de reinstalar o jogo.

**Hoje ele não é mais escolhido.** Sai de uma conta só,
`ArduinoProtocol.pulso_minimo_ms(palheta, vmax)`, que é a mesma regra que
o firmware já aplica sozinho (`max(8, vmax × 2,2)`), para os dois limites
tropeçarem no mesmo soco em vez de um recusar o que o outro aceita. Na
Central ele aparece como leitura, com a janela que a montagem enxerga
escrita ao lado.

**Os dois lados validam.** `ArduinoProtocol.build_config` já limita os
valores antes de enviar, e o firmware revalida ao receber, respondendo
`ERROR,PARAM` no que não servir. Uma placa gravada com firmware mais
velho, ou um cabo que corrompeu a linha, não consegue ser configurada
com um raio negativo.

O jogo envia `CONFIG` sozinho em dois momentos: ao receber `READY` e ao
fechar a Central Técnica. O botão **ENVIAR CONFIG** existe para reenviar
à mão quando se troca a placa sem reiniciar o jogo.

---

## Como a placa mede

1. O jogo manda `ARM` ao começar cada tentativa. Sem isso a placa ignora
   tudo: é o que impede o balanço do saco de virar pontuação.
2. A palheta entra na fenda → o sinal D0 muda para o nível ativo e o
   cronômetro começa, por interrupção.
3. A palheta sai → o cronômetro para. A duração do bloqueio é o dado.
4. `v = palheta ÷ duração`. Uma palheta de 20 mm bloqueada por 4 ms dá
   5 m/s.
5. Um `HIT` por `ARM`, e mais nada: depois de reportar, a placa fecha a
   janela e só outro `ARM` a reabre. Somados o tempo morto de 1,2 s do
   firmware e os 900 ms do jogo, o retorno do saco não tem como pontuar.

O sensor mede **velocidade**, não força em newtons nem em
quilogramas-força. A pontuação de 0 a 9999 é uma escala de arcade
calibrada, não uma medição de física.

### A nota, no jogo

A velocidade vira nota em `scripts/score_curve.gd`, por uma curva de
**três âncoras**, e não mais por uma potência única:

| Âncora | O que é | Paga |
| --- | --- | --- |
| `vmin` | abaixo disso não é soco | 0 |
| `vref` | o soco do cliente médio | **5000, sempre** |
| `vmax` | o teto da máquina | 9999 |

As três valem com qualquer contraste — o segundo ajuste, que só decide
quanto a nota se espalha ENTRE elas. Quem regula a dificuldade é o
`vref`: exigir mais velocidade para pagar meio placar é, literalmente, a
máquina ficar mais difícil, e isso se explica para o dono da máquina sem
falar em expoente.

A versão anterior usava `9999 × x^2,20`, e uma potência acima de 1 esmaga
o meio da escala — que é onde está quase todo mundo. Um soco a 35 % da
faixa calibrada pagava **974 pontos**; com as âncoras, paga cerca de
2700. "Mil" lê como máquina que não registrou, e é por isso que a curva
mudou de forma.

---

## Diagnóstico rápido

| Sintoma | Onde olhar |
| --- | --- |
| Tela em `PROCURANDO ARDUINO…` | Nenhuma porta serial visível. Cabo, driver CH340/FTDI, ou a extensão `gdserial` não carregou. |
| `AGUARDANDO READY` e não sai dali | Porta abriu, mas nada chega. Confira a velocidade (115200) e se o `.ino` gravado é o V10. |
| `SEM RESPOSTA` depois de funcionar | A placa travou ou o cabo soltou. O jogo continua tentando sozinho. |
| `ERROR,NO_MPU` | O MPU-6050 não respondeu no I2C. Confira SDA em A4, SCL em A5 e a alimentação. |
| `SATURATION` a cada golpe forte | O sensor está no fundo de escala. A medida sai menor que a real: afaste o sensor do ponto de impacto. |
| `TEST` aparece na tela mas o soco real não | O caminho placa → jogo está bom. O problema é o sensor, o alinhamento da palheta com a fenda, ou a `vmin` alta demais. |

## O Arduino não manda pontos

O firmware manda **medida**, o Godot faz a **nota**:

```
HIT,<velocidade_m_s>,<pico_g>,<duracao_ms>,<eixo>
```

Só a velocidade entra na pontuação. O pico de aceleração e a duração
servem para decidir se aquilo foi um soco — validam, não inflam.

Isso não é preciosismo de arquitetura. Com a nota calculada no firmware,
mudar a dificuldade da casa exigiria regravar o Arduino; a curva não
poderia ser desenhada na tela antes de salvar; e duas máquinas com
firmwares de épocas diferentes dariam notas diferentes para o mesmo soco.

### O que o jogo recusa, e por quê

| Recusa | Motivo |
| --- | --- |
| Fora do estado `ARMED` | Abertura, foto, contagem e resultado não pontuam. |
| Segundo `HIT` na mesma rodada | Um soco por rodada. |
| Menos de 900 ms desde o último aceito | O saco balança depois do impacto, e o MPU lê o balanço como uma sequência de eventos menores. |
| Duração abaixo de 12 ms | Um toque, um esbarrão ou um tranco no gabinete duram muito menos que um soco. |
| `REJECT,CURTO` num soco forte de verdade | O pulso ficou mais curto que `pulso_min_ms`. Confira na Central se a largura da palheta cadastrada bate com a real: é dela que sai o limite. |

### `SATURATION` não vira 9999

Quando o acelerômetro chega ao fim da escala, ele **parou de medir**. A
máquina não sabe quanto aquele golpe valeu, e chutar o teto seria
inventar um número. A saturação fica registrada na Central Técnica, na
página GOLPE, com a hora — é lá que alguém aumenta a faixa do MPU-6050.

### `BUTTON,START` e `BUTTON,CREDIT`

Os dois botões do gabinete podem chegar pela serial **ou** pela placa
Zero Delay como controle USB. Os dois caminhos passam pelo mesmo
antirrepique de 250 ms e pelas mesmas ações `cabinet_start` e
`cabinet_credit`.

---

## Quando o Arduino "não faz nada"

Quatro problemas dão exatamente o mesmo sintoma — START e CRÉDITO mortos.
A aba **DADOS** da Central (`F9`) separa os quatro em um segundo. Aperte o
botão do gabinete e olhe a linha **`Arduino (D2/D3)`**:

| O que acontece | O que é |
| --- | --- |
| O número **sobe** | Fio, pino e placa certos. Se o crédito não entra, o problema é o modo de operação (LIVRE × 1 FICHA), não o botão. |
| O número **não sobe** e a linha diz `CONECTADO` | O fio ou o pino. START é **D2**, CRÉDITO é **D3**, o outro lado de cada botão vai ao **GND**. |
| Diz `SEM RESPOSTA EM COMx` | Porta errada, e o jogo já está tentando a próxima sozinho. |
| Diz `NÃO ABRIU EM COMx` | A porta não chegou a abrir: ou não existe, ou outro programa está com ela. O jogo passa para a próxima. |
| Diz `PROCURANDO ARDUINO… (busca 7, nenhuma porta à vista)` | Ninguém está anunciando porta nenhuma. O número da busca subindo prova que a máquina **está** procurando. Passada a primeira volta, ela deixa de perguntar e tenta COM1 a COM32 uma por uma. |

A linha **`portas vistas`**, logo abaixo, mostra todas as COM que o
Windows anuncia. Se a do Nano não estiver ali, ainda assim o jogo vai
achá-la na varredura cega — mas o driver CH340 continua valendo a pena
instalar, porque com ele tudo é mais rápido.

### Por que o jogo procura em qualquer porta, sozinho

Um PC de gabinete quase nunca tem uma porta COM só: o Windows inventa
COM3 e COM4 para o Bluetooth, o leitor de cartão traz a dele. O jogo
abria **a primeira da lista** e ficava esperando um `READY` que nunca
chegava — a noite inteira, com os botões mortos.

Hoje a busca tem quatro camadas, e cada uma cobre a falha da anterior:

1. **A porta escolhida à mão**, se houver, ganha duas tentativas
   exclusivas — mas só duas. Ver a seção seguinte.
2. **As portas anunciadas pelo sistema**, com as de conversor conhecido
   (CH340, FTDI, CP210x, Arduino oficial) na frente da fila.
3. **A varredura cega**: fechada uma volta sem achar, o jogo passa a
   tentar `COM1` … `COM32` (no Linux, `/dev/ttyACM0-7` e
   `/dev/ttyUSB0-7`) mesmo que ninguém os tenha anunciado. Porta que não
   existe recusa na hora, então a varredura inteira custa poucos
   segundos.
4. **A troca de caminho**: passada uma volta inteira e 40 s sem uma única
   linha válida, o jogo troca a extensão nativa pela ponte do sistema (ou
   o contrário) e recomeça. Ver "Os dois caminhos até a placa".

Aberta uma porta, o jogo espera **8 segundos** pela primeira linha da
placa — contados de quando a porta **confirmou** que abriu, e não de
quando o jogo pediu. A diferença importa: pela ponte, entre o pedido e a
porta aberta há um cano, um PowerShell e um driver, e num PC lento isso
sozinho passava dos cinco segundos que a paciência antiga tinha inteira.
A paciência acabava antes de a porta existir, e a máquina varria a lista
sem dar a placa nenhuma chance de responder. Era este o "funciona no meu
PC, não funciona no outro, com a mesma porta".

**Qualquer linha válida serve de apresentação** — não só o `READY`. O
`READY` sai uma vez, no arranque da placa; quando o jogo reinicia e o
Arduino não, esse `READY` já passou há muito, e a porta certa ficava em
"AGUARDANDO READY" para sempre com a placa despejando `TELEMETRY` e
`PINS` quatro vezes por segundo nela. Hoje a primeira linha que o
protocolo entender já vale por `CONECTADO`.

### A porta fixada é preferência, não cadeado

**PORTA SERIAL**, na aba GOLPE, fixa uma porta — e isso é gravado em
disco, atravessando reinicializações e atualizações do jogo. Se essa
porta estiver errada nesta máquina (um `COM5` escolhido noutro dia, num
PC onde o Nano é `COM3`), a máquina ficava morta com a placa espetada e
funcionando do lado.

Hoje ela ganha **duas tentativas exclusivas** e depois volta para o fim
da história: a varredura passa a incluir todas as portas, com a
preferência ainda na frente da fila. A Central mostra o estado exato na
linha `porta escolhida:`. Para voltar ao automático, gire a opção até
**AUTO**, ou aperte **RECONECTAR** na aba DADOS — que refaz a escolha
inteira do zero, caminho e tudo.

### O sketch compila sem a biblioteca das fitas

O `#include` da Adafruit NeoPixel é condicional (`__has_include`). Numa
IDE sem ela instalada o sketch **compila e grava assim mesmo**: o sensor
mede, os botões respondem, e só as fitas ficam apagadas — com um aviso na
compilação dizendo o que instalar.

Isto não é conveniência, é a lição de um defeito real: enquanto o
`#include` era incondicional, a IDE sem a biblioteca **não gerava upload
nenhum**, a placa ficava com o firmware velho, e o sintoma não era "as
fitas não acendem" — era "o Arduino não faz nada".

Antes de qualquer entrega, `sh tools/conferir_firmware.sh` compila o
sketch nas duas situações, fora da IDE, e confere que ele é ASCII puro.

### Por que a calibração não pode mais congelar aos 70%

Em alguns cores AVR, uma chamada da biblioteca Wire pode esperar para
sempre se SDA ou SCL ficarem presos. Nesse instante o Arduino para junto:
não responde `PING`, o jogo fecha a COM, a reabertura reinicia a placa e a
calibração começa novamente.

O firmware V10 usa um mestre I2C pequeno nos mesmos pinos A4/A5, a cerca
de 100 kHz. Toda espera tem prazo de 3 ms. Se o barramento prender, a
leitura falha, a placa envia pulsos de recuperação e continua atendendo a
serial e os botões. Essa proteção não depende da versão da IDE ou da
biblioteca Wire instalada no computador.

---

## A placa nunca trava, nem sem sensor

Isto foi o defeito mais caro que o firmware teve, e explica de uma vez
START morto, CRÉDITO morto e o jogo trocando de porta a noite inteira.

O `setup()` estava assim:

```cpp
if (!mpuVivo()) {
  Serial.println(F("ERROR,NO_MPU"));
  while (true) { pisca o LED; }     // <- para sempre
}
...
Serial.println(F("READY,..."));     // <- nunca chegava aqui
```

Sem o MPU-6050 respondendo, a placa entrava num laço infinito **antes de
chegar ao `loop()`**. `processarBotoes()` nunca rodava — e um problema no
sensor derrubava junto os botões, a serial e as fitas, três coisas que
não dependem dele para nada. O `READY` também nunca saía, então o jogo
nunca reconhecia a porta.

Agora:

- o **`READY` sai primeiro**, antes de tocar no sensor;
- sem sensor a placa **continua no ar** — botões, crédito, serial, fitas;
- ela **tenta o sensor de novo a cada 2 s** e manda `OK,MPU` tanto no
  arranque bem-sucedido quanto quando ele reaparece, então um fio de I2C
  encaixado de volta volta a funcionar sem desligar nada;
- o LED de D13 pisca enquanto faltar sensor.

E o sensor é procurado nos **dois endereços** (0x68 e 0x69 — o AD0 solto
de muitos clones flutua) aceitando **qualquer `WHO_AM_I`** que não seja
0x00 nem 0xFF. Metade dos módulos vendidos como MPU-6050 é MPU-6500,
MPU-9250 ou ICM-20608, devolve 0x70/0x71/0x73/0x98 e mede igual: exigir
0x68 era reprovar hardware bom.

### `READY` não quer mais dizer "sensor presente"

São duas coisas diferentes agora, e a aba **DADOS** mostra as duas
separadas. O START só libera depois de **`CALIBRATED`** ou de uma leitura
completa (`TELEMETRY`/`NOISE`) — nunca apenas por `READY` ou `OK,MPU`. A porta pode continuar viva
para diagnóstico e botões sem vender uma partida que não conseguirá
medir.

O jogo guarda, no arquivo local daquele Windows, a última COM e o último
backend que chegaram ao sensor. Eles entram primeiro no próximo boot,
mas são apenas preferência: três quedas em dois minutos revogam o
caminho e fazem a máquina experimentar automaticamente o outro backend.

---

## "Funciona no meu PC e não no outro"

Este sintoma quase nunca é o fio. São três causas, em ordem de
frequência, e a aba **DADOS** da Central separa as três:

**1. A extensão nativa da serial não carregou** — e isso **deixou de
derrubar a máquina**. Veja a seção seguinte: hoje existe um segundo
caminho até a placa, e ele não depende de arquivo nenhum que possa
faltar. A Central diz qual dos dois está em uso na linha
`caminho até a placa:` e, logo abaixo, se a extensão carregou ou não na
linha `extensão nativa:`.

Ela não carrega por **dois** motivos, e os dois são silenciosos — o
Windows recusa o `.dll` sem escrever nada em lugar nenhum:

- **O `.dll` não viajou junto.** A `gdserial` é exportada **ao lado** do
  executável, não dentro dele (uma biblioteca nativa não roda de dentro
  de um `.pck`). Copiar só o `PunchChallenge.exe` para o outro PC deixa a
  extensão para trás. **Leve a pasta inteira**, não o `.exe` sozinho.
- **Falta o runtime do Visual C++.** Mesmo indo junto, o `gdserial.dll`
  importa `VCRUNTIME140.dll` e o UCRT — o *Microsoft Visual C++
  2015-2022 Redistributable (x64)*, que **não vem numa instalação limpa
  do Windows**. No PC de quem desenvolve ele está sempre lá (o Visual
  Studio, o Godot, meia dúzia de programas o instalam); no PC do cliente,
  quase nunca. É a explicação mais comum para "funciona no meu PC" —
  literalmente a mesma pasta, o mesmo cabo, a mesma placa, e um PC usa a
  extensão e o outro não.

Conferir na máquina do cliente, num terminal:

```
where VCRUNTIME140.dll
```

Nada listado quer dizer runtime ausente. Instalar o
*VC++ 2015-2022 Redistributable x64* devolve o caminho rápido. **Nada
disso é obrigatório**: sem a extensão o jogo funciona igual pela ponte —
mas quem cuida da máquina precisa saber em qual dos dois ela está.

Antes de exportar, `sh tools/conferir_exportacao.sh` confere que todos os
binários declarados existem — a extensão continua sendo o caminho
preferido quando está inteira.

**2. O driver da placa não está instalado.** Clones de Nano usam o
conversor **CH340**, que o Windows não traz de fábrica. Sem o driver a
porta COM nem aparece — e a Central mostra `portas vistas: nenhuma`.

**3. O Nano reinicia ao apertar o botão** (o Windows toca o som de
desconexão). Isto é elétrico, não é software: ou o botão está fechando
**5 V no GND** em vez de **D2 no GND**, ou o 5 V do Nano está ligado ao
5 V da fonte das fitas e as duas fontes brigam. Num PC de mesa a USB
aguenta e o defeito não aparece; num notebook, não aguenta.

---

## Os dois caminhos até a placa

O Godot não abre uma porta COM sozinho. Durante muito tempo quem fazia
isso era **só** a extensão nativa `gdserial` (um `.dll` ao lado do
executável) — e num gabinete real ela não carregou. O resultado foi a
máquina inteira morta: START morto, CRÉDITO morto, sensor mudo, fitas
apagadas, e na tela apenas "SIMULAÇÃO".

Depender de um único caminho era o defeito. Hoje há dois, e o jogo desce
a escada sozinho, sem perguntar nada:

| Ordem | Caminho | Precisa de quê |
| --- | --- | --- |
| 1º | **extensão nativa** (`gdserial`) | o `.dll`/`.so` da extensão |
| 2º | **ponte do sistema** | nada — só o que o SO já tem |
| 3º | nenhum | (o jogo explica na tela o porquê) |

### Como a ponte funciona

O jogo sobe um processo ajudante e conversa com ele por linhas de texto
pelos canos padrão (`OS.execute_with_pipe`):

- **Windows** — `tools/ponte_serial.ps1`, rodando no **PowerShell que já
  vem no Windows**, usando `System.IO.Ports.SerialPort`. Não há Python
  para instalar, não há binário para o antivírus apagar, não há
  arquitetura errada.
- **Linux / macOS** — `tools/ponte_serial.sh`, usando `stty` e `cat`.

O protocolo entre o jogo e o ajudante é o mesmo nos dois:

| Sentido | Linha | O que quer dizer |
| --- | --- | --- |
| jogo → ponte | `@LISTAR` | reenumera as portas |
| jogo → ponte | `@ABRIR,COM5,115200` | abre |
| jogo → ponte | `@FECHAR` / `@SAIR` | fecha / encerra |
| jogo → ponte | qualquer outra | vai **crua** para o Arduino |
| ponte → jogo | `#PONTE,V1` | apresentação |
| ponte → jogo | `#PORTAS,COM3,COM5` | lista, já em ordem de suspeita |
| ponte → jogo | `#ABERTA,` / `#FECHADA,` / `#FALHA,` / `#ERRO,` | estado |
| ponte → jogo | qualquer outra | veio **crua** do Arduino |

Ou seja: `PING`, `CONFIG,…`, `LEDS,…`, `HIT,…`, `BUTTON,START` — todo o
protocolo V2 desta página atravessa a ponte sem mudar uma vírgula. Quem
está acima não sabe por qual caminho a linha veio.

### O método que sempre funciona

A pergunta prática — *o que eu faço para o Arduino pegar em qualquer PC?*
— tem uma resposta curta: **nada**. O jogo faz sozinho. O que segue é o
que ele tenta, em ordem, e por que nenhuma das etapas pode ficar presa:

| Etapa | O que o jogo faz | Que falha ela cobre |
| --- | --- | --- |
| 1 | Extensão nativa, se carregou | o caminho rápido |
| 2 | Ponte do sistema (PowerShell / `stty`) | `.dll` ausente, runtime do VC++ ausente, antivírus |
| 3 | Ponte por `-EncodedCommand` | política de grupo que proíbe arquivos `.ps1` |
| 4 | Três fontes de enumeração, em união | registro cego, driver que registrou a porta noutro lugar |
| 5 | Varredura cega de `COM1`…`COM32` | enumeração que não devolve nada |
| 6 | Troca de caminho a cada volta perdida | um caminho que não presta nesta máquina |
| 7 | Ressurreição do ajudante, sem limite | ajudante morto, cabo com soluço, PowerShell derrubado |

Nenhuma dessas etapas tem um estado final: se todas falharem, o ciclo
recomeça pela primeira. **A máquina nunca desiste** — não existe mais
combinação em que a busca "acaba" e a tela fica parada.

Três coisas que o jogo **não** consegue resolver sozinho, e que valem a
visita de quem cuida da máquina:

1. **Cabo USB só de carga.** Não tem os fios de dados. Nenhum software
   resolve; o PC nem chega a ver a placa.
2. **Driver CH340 ausente.** Sem ele o Windows não cria porta nenhuma, e
   nem a varredura cega tem o que abrir. Instalar o driver é de graça e
   leva um minuto.
3. **Alimentação.** Se o 5 V do Nano está ligado junto com o 5 V da fonte
   das fitas, as duas fontes brigam e a placa reinicia sozinha. Num PC de
   mesa a USB aguenta e o defeito não aparece; num notebook, não aguenta —
   e aí é "funciona num PC e no outro não" de novo, mas por eletricidade.

### As três regras que fazem a ponte não estragar o jogo

1. **Nada bloqueia.** Ler de um cano trava até a linha chegar; feito no
   laço do jogo, isso é a máquina congelada esperando um Arduino que
   talvez nem esteja ligado. A leitura mora numa *thread* própria, e o
   laço do jogo só recolhe o que já chegou.
2. **Nada acumula.** Do lado Unix o repasse é `cat`, e não `tr`: `tr`
   escreve por *stdio*, que guarda 4 KB antes de soltar — a placa falaria
   e o jogo ficaria surdo por minutos. `cat` copia com `read`/`write`
   direto.
3. **Nada insiste sem pausa.** Porta que recusa espera 0,7 s antes da
   próxima tentativa, e ajudante que morre só é ressuscitado a cada
   2,5 s. Sem isso, uma porta ocupada viraria sessenta tentativas por
   segundo.
4. **Nada desiste.** `poll()` — o batimento do backend — é chamado a cada
   quadro **sempre**, inclusive quando o backend responde que não está
   disponível. Era o contrário, e era fatal: a ponte responde
   "indisponível" justamente enquanto está caída, então o batimento
   parava no instante em que passava a ser necessário. Um ajudante que
   caísse uma única vez nunca mais voltava.
5. **A morte do ajudante é perguntada ao sistema, não ao cano.** Medido:
   depois de o processo filho morrer, o cano do Godot devolve
   `eof_reached() == false` **para sempre**, e `get_line()` passa a
   voltar vazio na hora, com erro. Quem confiasse no fim-de-arquivo
   nunca perceberia a morte — e ainda giraria em vazio queimando um
   núcleo. Quem responde de verdade é `OS.is_process_running()`.

### Forçar um caminho

Somente para diagnóstico, defina `PUNCH_SERIAL_DIAGNOSTICO=1` junto com
`PUNCH_SERIAL=ponte` ou `PUNCH_SERIAL=nativa`. Sem a primeira chave, o
jogo ignora uma preferência antiga esquecida no Windows e mantém a
seleção adaptativa. No modo de diagnóstico a escolha é forçada para
permitir comparar os dois caminhos no mesmo gabinete.

### Como isto é conferido

`sh tools/conferir_ponte.sh` — e ele não é um teste de mentira. Ele abre
um par de pseudo-terminais (uma porta serial de verdade, para o sistema
operacional), põe um Arduino de mentira de um lado e cobra três coisas:

1. o `ponte_serial.sh` conversando com a porta;
2. o **jogo inteiro** — backend, thread, cano, ajudante de verdade —
   chegando até essa porta;
3. o `ponte_serial.ps1` **de verdade**, rodando no PowerShell, contra a
   mesma porta.

A terceira etapa existe porque o arquivo que roda no gabinete era também
o único que nunca tinha rodado em lugar nenhum antes de chegar lá. Ela
prova que a apresentação vem sem lixo antes dela (o BOM do console do
Windows entrando dentro do `#PONTE,V1` bastaria para o jogo concluir que
não há ponte), que uma rajada de 30 linhas chega inteira e em ordem, e
que o caminho de volta entrega `LEDS,640` na porta.

---

## O jogo NÃO precisa de Python

Só a **ponte de câmera** precisa, e ela é a segunda opção. O jogo tenta
primeiro o caminho **nativo**, que não exige nada instalado; a ponte só
entra se esse caminho não provar que entrega imagem de verdade (há uma
checagem de contraste: feed preto é reprovado em dois segundos e meio).

Num PC recém-formatado, sem Python e sem nada:

| O que | Funciona? |
| --- | --- |
| START, CRÉDITO, sensor de soco, fitas de LED | **Sim**, sempre — pela extensão nativa ou pela ponte do sistema |
| Ranking, pontuação, som, todas as telas | **Sim**, sempre |
| Foto pela câmera nativa | Sim, se o Windows entregar imagem |
| Foto da câmera | Nativa via Windows Media Foundation, sem Python |

Sem foto, o ranking mostra a silhueta desenhada e o jogo segue inteiro.

---

## Se o `git pull` entrar num laço "Unlink failed"

```
Unlink of file 'addons/gdserial/bin/windows-x86_64/~gdserial.dll' failed.
Should I try again? (y/n)
```

Responder `y` não resolve nunca — o arquivo está **travado**, e vai
continuar travado enquanto quem o travou estiver no ar.

**Saída:**

1. digite `n` e Enter (ou `Ctrl+C`) para abortar;
2. **feche o editor do Godot** e qualquer `PunchChallenge.exe` rodando;
3. `git pull` de novo.

**Por que acontece.** No Windows não dá para sobrescrever uma DLL que
está carregada. Quando o editor do Godot precisa recarregar uma extensão,
ele copia a atual para um nome com `~` na frente e usa a cópia — então
`~gdserial.dll` **nasce sozinho** ao abrir o projeto e fica preso ao
processo do editor. O `git` tenta apagá-lo, o Windows recusa, e o git
pergunta em laço.

O arquivo está no `.gitignore` desde a BUILD 43: ele continua nascendo na
máquina de quem desenvolve, mas não entra mais no repositório e não
atrapalha mais nenhum `pull`.

---

# O MOTOR DO SACO

O saco desce quando a rodada começa e sobe quando ela acaba. Quem liga e
desliga o motor é **sempre o firmware**; o jogo apenas diz onde o saco
deve estar.

## Ligação

Duas saídas digitais comandam uma ponte H (L298N: `IN1`/`IN2`; BTS7960:
`RPWM`/`LPWM`) ou um par de relés com intertravamento mecânico.

| pino | função |
|---|---|
| `D7` | DESCE |
| `D8` | SOBE |
| `D10` | fim de curso de baixo — para GND, **opcional** |
| `D11` | fim de curso de cima — para GND, **opcional** |

As duas saídas **nunca** ficam altas ao mesmo tempo: numa ponte H isso é
condução cruzada e o componente queima; num par de relés é um curto entre
as duas polaridades. Só existe um lugar no firmware que desliga as duas
(`motorParar`), e toda mudança de sentido passa por ele.

## Comandos (jogo → placa)

| linha | o que faz |
|---|---|
| `MOTOR,DESCE` | começa a descida |
| `MOTOR,SOBE` | começa a subida |
| `MOTOR,PARA` | desliga as duas saídas na hora |
| `MOTOR,ESTADO` | pede o relato sem mexer em nada |
| `MOTOR,CONFIG,<curso_ms>,<pausa_ms>,<fim_de_curso>` | ajusta o curso |

`DESCE` e `SOBE` são **idempotentes**: mandar `DESCE` enquanto já desce
não reinicia o cronômetro, e mandar `DESCE` com o saco já embaixo não faz
nada. É isso que impede o jogo de manter o motor ligado à força de
repetir o comando.

`curso_ms` vai de 200 a **15000** e `pausa_ms` de 50 a 2000 — os mesmos
limites dos dois lados do cabo, conferidos por teste. Um valor que o jogo
aceita e a placa recusa vira uma configuração que parece ter sido gravada
e não foi.

## Relato (placa → jogo)

```
MOTOR,<estado>,<posicao>,<resta_ms>
```

| campo | valores |
|---|---|
| `estado` | 0 parado · 1 descendo · 2 subindo |
| `posicao` | 0 desconhecida · 1 em cima · 2 em baixo |
| `resta_ms` | quanto falta do curso atual |

A placa manda esta linha a **cada mudança**, e nunca em repetição: quem
a recebe sabe o que o motor está fazendo sem precisar perguntar.
`resta_ms` é o que permite à Central desenhar uma barra que anda de
verdade em vez de um "aguarde" parado.

`posicao` nasce **desconhecida** e só deixa de ser depois do primeiro
curso completo. No arranque o firmware não tem como saber onde o saco
está, e fingir que sabe seria pior do que admitir.

## As três garantias

**O curso é por tempo, e o tempo é o teto.** Um saco de pancada não tem
encoder e não precisa de um: o curso é sempre o mesmo. Os fins de curso,
quando existem, param antes; o tempo é o limite que vale mesmo se um
deles falhar, se o cabo soltar ou se a correia patinar. Acima de tudo:
**é o firmware que desliga**, inclusive se o jogo travar, fechar ou o
cabo cair.

**Não há laço nenhum.** Nada de `while` esperando chegar: o estado avança
em `motorAtualizar`, chamada uma vez por volta do `loop`. Um firmware
preso esperando um motor é um firmware que parou de ler o sensor e de
responder — e aí ninguém consegue nem mandar parar.
`sh tools/conferir_firmware.sh` falha se alguém reintroduzir um.

**Sem motor, o jogo é o mesmo.** Um gabinete sem motor ligado (ou com ele
desligado na Central) joga exatamente igual. É a diferença entre um
recurso e uma dependência.
