# Punch Challenge — versão ARENA

> **BUILD 58 — VARIANTE PARA SENSOR DE FEIXE LM393.** O firmware que deve
> ser gravado está, de propósito, numa pasta própria na raiz:
> `ARDUINO_SENSOR_DE_FEIXE_LM393/ARDUINO_SENSOR_DE_FEIXE_LM393.ino`.
> Não grave o firmware MPU que permanece em `arduino/punch_sensor`.
> Ligações e configuração estão em `LEIA_SENSOR_OPTICO.txt`.

Esta é a **versão animada** da máquina de soco da
**Lazer & Sport Brinquedos**. É o mesmo jogo de
[`punch-challenge`](https://github.com/Bochino693/punch-challenge) —
mesmo sensor, mesma ponte serial, mesma câmera, mesmo ranking, mesma
Central Técnica — com **uma** diferença, na tela do soco:

> No lugar do alvo desenhado, há uma **arena 3D emoldurada como um
> quadro**, com um **lutador** que leva o impacto na medida do golpe, vai
> à lona quando não aguenta mais, e tem o estado mostrado nas **colunas
> de dano** das laterais. A cada soco a máquina grita uma frase.

## O lutador é uma folha de nove poses

O adversário da arena são **nove ilustrações** em
`assets/personagem/sprites/`, montadas dentro do mundo 3D — com o
ringue, a perspectiva, o tremor, as partículas e a câmera do nocaute
continuando a valer. O que transforma nove desenhos parados num lutador
que se mexe é o movimento procedural de `scripts/arena/lutador.gd`:
respiração, recuo do golpe, cambaleio, tombo e o clarão do impacto.

Antes disso o corpo era construído por código — anéis torneados, músculo
modelado, sombreador de desenho. Funcionava e custava onze chamadas de
desenho; hoje custa uma. Mas o motivo de ter saído não foi custo:
**geometria feita de elipsoides somados tem um teto de qualidade, e esse
teto fica bem abaixo de uma ilustração.**

Como trocar a arte, o que cada pose faz e as duas armadilhas de
enquadramento que isso trouxe: **[`docs/ARENA.md`](docs/ARENA.md)**.

## Tela em pé

O jogo é desenhado para **1080 × 1920 (vertical)**. A máquina é um
armário alto com o saco na frente: quem joga olha para cima, não para os
lados. Numa tela deitada, metade da largura seria moldura vazia e o
número da pontuação ficaria pequeno justamente para quem está a três
metros de distância. Em pé, a leitura desce em coluna — saco, número,
veredito — que é a ordem em que a pessoa procura.

Para montar:

1. Gire o monitor fisicamente (suporte VESA em retrato).
2. No Windows: **Configurações → Sistema → Vídeo → Orientação da tela →
   Retrato**. Confira qual dos dois retratos deixa a imagem na posição
   certa para o seu suporte.
3. O jogo abre em tela cheia; nada mais a ajustar.

Para testar no PC do escritório, sem girar o monitor, a janela abre em
540 × 960 (`window_width_override` no `project.godot`) — a proporção é a
mesma, só menor.

### Tema arena neon

O jogo combina o azul e vermelho da Lazer & Sport com uma arena
marinho/preta, painéis tecnológicos e luzes azul, vermelho, verde e âmbar.
O contraste mantém o placar legível a distância e aproxima a apresentação
das máquinas modernas de boxe com câmera e ranking visual.

Todas as cores moram em `scripts/paleta.gd`. Fundo, alvo, placar,
moldura e textos leem de lá, então o tema é uma coisa só — mudar a cara
do jogo é mexer num arquivo, e não caçar hexadecimal em seis.

Dois detalhes que só existem porque o tema é claro:

- **Lâmpada em vez de ponto de luz.** Um LED desenhado como brilho
  difuso some num fundo claro. Cada bulbo tem corpo pintado e aro
  escuro, então a apagada também se vê — e é a fieira inteira que faz o
  olho ler "letreiro".
- **Clarão em âmbar, com as bordas escurecendo.** Lavar a tela de branco
  não funciona sobre quase-branco. O golpe acende em âmbar e escurece as
  bordas ao mesmo tempo: o que o olho lê como flash é o contraste.

### Acabamento de fliperama

A referência é máquina de salão de verdade (PUNCH & KICK, KUNG FU): o que
faz aquilo parecer equipamento caro, e não desenho, são três coisas — e
as três estão aqui.

**A entrada abre com o selo da casa.** Um quadrado pequeno com o
logotipo da Lazer & Sport, placa vermelha, borda de ouro e um brilho
atravessando — e só depois vem o soco que faz nascer o emblema do jogo.
Antes a máquina abria com o logotipo comprido sobre um fundo azul-marinho
que não tinha parentesco nenhum com o resto, e a troca para o emblema
parecia defeito. Agora a tela de arranque do Godot usa o mesmo selo e o
mesmo chão escuro, então o arranque e a entrada são a mesma coisa
continuando.

**No impacto, o que voa não é confete.** Um retângulo girando é festa de
aniversário; o que sai de uma pancada é brasa, e brasa tem rastro. A
comemoração do golpe é feita de brasas explodindo do ponto do impacto, raios
girando junto e anéis em sequência — mais um ESTRELÃO de história em
quadrinhos que abre no lugar do golpe, com rachaduras e riscos
convergindo. Ele dura quatro décimos de segundo e é o desenho que diz
"bateu" antes de qualquer número aparecer. O papel picado fica reservado
à premiação do ranking, onde campeão, pódio, Top 10 e Top 20 recebem
cerimônias e torcidas diferentes.

**A tela de jogo tem três papéis de texto, e só três.** Título (letreiro
com contorno, o mesmo da abertura), rótulo (26 px, o que nomeia um
número) e apoio (22 px, a letra miúda de quem quiser conferir). Antes
cada linha escolhia o próprio corpo na hora — 25, 26, 30, 32, 34, 46 — e
metade era texto cru, sem contorno, sobre um painel que muda de cor a
cada faixa.

**O visor é UM SÓ, o jogo inteiro.** Uma máquina de fliperama tem um
painel, e é para ele que a pessoa olha do começo ao fim. Aqui é a mesma
peça em todos os momentos, e só muda o que está escrito dentro: traços
piscando enquanto a máquina espera o soco, os pontos da carga enquanto se
segura a barra, e a pontuação subindo no fim. O anel de sessenta marcas
em volta muda de papel junto: corre em três marcas quando está esperando,
enche com a carga quando alguém simula pelo teclado, e enche com a
PONTUAÇÃO na contagem — nunca com o relógio.

**Não há saco de pancadas desenhado.** O saco é a peça física que a
pessoa tem na frente do corpo; um segundo saco na tela dividia a atenção
entre dois alvos, e o de pixel não é o que se acerta. No lugar dele, a
tela de espera acende um FAROL: anéis saindo do visor, sempre para fora,
chamando o punho para onde o número vai nascer.

**O visor de sete segmentos** (`scripts/visor_led.gd`). Não é fonte: é
segmento a segmento. O que faz o olho reconhecer um painel de LED não é
o formato do algarismo, é o **segmento apagado** — num visor de verdade
os sete traços estão sempre lá, e os que não fazem parte do número ficam
visíveis, escuros. Nenhuma fonte dá isso. Cada traço aceso ainda leva um
miolo quase branco, porque um LED aceso estoura no centro e guarda a cor
só na borda.

**A letra de fliperama** (`_letreiro`). Três passadas sobre a mesma
palavra: um contorno grosso quase preto, que segura a letra sobre
qualquer fundo; a palavra alguns pixels acima num tom claro, cujo
resquício virando por cima da borda faz o brilho do topo (o Godot
desenha texto de uma cor só, então o degradê é simulado assim); e o
preenchimento. Com halo, entra antes um contorno largo e transparente na
cor de destaque.

### Como a tela se organiza

A tela é dividida em **bandas horizontais fixas**, declaradas no topo de
`scripts/main.gd` (`BANDA_TOPO`, `PALCO_*`, `LEITURA_*`, `CARTOES_Y`,
`RODAPE_Y`). Cada coisa desenhada mora dentro da sua banda:

```
  0 –  150   cabeçalho: marca do jogo e modo de operação
168 – 1104   alvo: o visor, o farol e o campo de força
1124 – 1580  leitura: número, veredito e convite
1608 – 1740  cartões: recorde, partidas, créditos
1876         rodapé: assinatura da casa
```

Enquanto tudo respeitar a sua banda, nada se sobrepõe. Textos que podem
crescer (o veredito, valores de configuração) passam por
`_texto_cabendo`, que **mede a palavra e encolhe o corpo até caber** —
`PESO-PESADO` e `FRACO!` ocupam o mesmo lugar sem um estourar a tela nem
o outro ficar pequeno.

## Como a máquina se comporta

```
ABERTURA → (START) → ENTRADA → 3, 2, 1 → SENSOR ARMADO → IMPACTO → RESULTADO
```

**Abertura: quatro telas, alternando sozinhas.** Uma máquina parada não
fica repetindo o mesmo cartaz — ela conta o jogo em capítulos, e é o
rodízio que segura quem passa no corredor por tempo suficiente para
decidir jogar. A cada sete segundos troca entre:

1. **A marca** — a logo da casa montada como letreiro, o nome do jogo e
   o recorde a bater, no mesmo medalhão que o jogo usa.
2. **Melhores da casa** — as cinco marcas, com ouro, prata e bronze.
3. **Como jogar** — os três passos, do tamanho de quem lê de longe.
4. **Você no ranking** — prévia da câmera e explicação das fotos locais.

O convite e os números da máquina ficam FIXOS nas três, porque não podem
depender de a pessoa ter chegado na página certa. Sem crédito no modo
ficha, o convite troca de texto em vez de sumir — quem chegou perto
precisa saber o que fazer.

**START entra no jogo.** Em modo ficha, o crédito é debitado aqui; em
modo livre, START entra direto.

**A máquina ESPERA o soco, e não cobra a espera.** Não há relógio na
tela nem barra esvaziando: o jogo fica armado, com o farol chamando, até
o golpe chegar. Existe um limite de noventa segundos, para a máquina não
passar a tarde armada se a pessoa foi embora — e, ao fim dele, **o
crédito é devolvido**. Nos últimos quinze segundos a tela avisa que vai
voltar e diz, na mesma linha, que a ficha volta junto. Antes a janela era
de oito segundos e a rodada morria com o crédito já debitado: quem
hesitou pagou e não jogou.

**O GOLPE VEM DO SENSOR, E DE MAIS NADA.** O MPU-6050 mede e manda
`HIT,<velocidade>,<pico_g>,<duração_ms>,<eixo>`; o Godot valida e calcula
a nota. O Arduino nunca manda pontos. A barra de espaço é um **simulador
de bancada** com chave própria na Central: em salão ela não pontua e a
tela nem a menciona — anunciar um atalho que, se existisse, seria fraude
é pior do que não ter o atalho.

**O resultado tem OITO NÍVEIS**, de 0000 a 9999, e cada um tem
apresentação própria — cor, animação, partículas, tremor e som:

| Pontos | Nível | O que a tela faz |
| --- | --- | --- |
| 0–1799 | `IMPACTO LEVE` | pulso pequeno, poucas faíscas, som seco, sem tremor |
| 1800–3999 | `BOM GOLPE` | dois anéis vermelhos, riscos e som de couro com grave leve |
| 4000–6499 | `GOLPE FORTE` | explosão radial amarela, brasas, tremor médio, grave encorpado |
| 6500–7999 | `EXPLOSIVO` | flash branco, rachaduras no ponto do golpe, onda dupla e subgrave |
| 8000–8999 | `NOCAUTE` | hit-stop de 95 ms, zoom de impacto, três ondas e sirene curta |
| 9000–9699 | `PESO-PESADO` | túnel de luz, brasas densas, câmera sacudindo e fanfarra |
| 9700–9998 | `LENDÁRIO` | o palco inteiro reage, raios dourados e música de vitória |
| 9999 | `SOCO PERFEITO` | congelamento de 360 ms, explosão branca e dourada, coro |

As faixas são **fixas** e moram numa tabela só (`scripts/fx/score_tier.gd`).
Elas descrevem o espetáculo, não a dificuldade: quem decide quanta gente
chega a cada nível é a **curva**, pela velocidade mínima, máxima e pelo
expoente. Um teste recusa duas receitas de efeito iguais — oito níveis
escritos como oito blocos de `if` viram dois níveis com a mesma animação
e só o texto mudando, e é isso que a pessoa que joga duas vezes seguidas
percebe.

**A contagem é o suspense.** O número sobe de zero até a pontuação em
cerca de dois segundos, com tique a cada passo e a coluna de potência
acompanhando. O veredito só entra quando a contagem termina — é o
momento pelo qual o cliente pagou.

## O que já está pronto

- Interface vertical em 1080 × 1920, adaptável para outras resoluções.
- Abertura com a marca da casa, efeito de luz, partículas, convite
  piscando e os três passos de como jogar.
- Saco de pancadas desenhado em código, com volume de cilindro, corrente
  de elos até o teto do gabinete, amassado no impacto e balanço limitado
  a 20° — o saco reage ao soco sem sair do enquadramento.
- Medidor de potência com escala numerada, as três zonas coloridas da
  máquina e o traço do recorde da casa.
- Tema de arena neon inteiro num arquivo só (`scripts/paleta.gd`).
- Medalhão com visor de sete segmentos, anel-relógio e rótulo curvo,
  compartilhado por todos os momentos da partida.
- Letras de fliperama com contorno grosso, brilho de topo e halo.
- Ícones desenhados em código (`scripts/icones.gd`): troféu, luva, ficha,
  raio, alvo, botão e estrela. Sem arquivo de imagem — não somem se
  faltar um PNG, não serrilham em outra resolução e mudam de cor junto
  com a faixa do golpe.
- A marca da casa montada como letreiro de parque: placa creme, moldura
  marinho e lâmpadas correndo em volta.
- Contagem regressiva animada `3, 2, 1` e tela de espera que aguarda o soco sem consumir a ficha.
- Pontuação de 0000 a 9999 por uma curva de **três âncoras**: a
  velocidade mínima paga 0, o soco de referência paga 5000 e a máxima
  paga 9999 — as três valem com qualquer contraste. Ver *Calibração da
  pontuação*.
- Oito níveis de golpe, cada um com cor, animação, partículas, tremor e som próprios.
- Ranking das cinco melhores marcas, persistente, com foto local do
  jogador quando a câmera está disponível e com a posição
  conquistada anunciada no fim da rodada. Cinco e não uma: com recorde
  único, quem não bate o recorde não ganha nada, e o recorde de uma
  máquina movimentada fica inalcançável em uma semana — entrar em quinto
  ainda é entrar, e é essa vitória pequena que vende a segunda ficha.
  Quem já tinha um recorde salvo não o perde: ele vira a primeira linha.
- Número total de partidas e saldo de créditos persistentes.
- Estatísticas diárias locais: partidas, média, melhor marca, faixas de
  força e entradas no Top 5.
- Modo Livre ou 1 Ficha selecionável na Central Técnica.
- `START`: entra no jogo e joga de novo depois do resultado.
- `SELECT`: adiciona um crédito.
- `F9`: abre e fecha a Central Técnica.
- `ESC`: fecha a configuração ou cancela uma rodada sem travar a interface.
- Seleção de porta serial, teste do sensor e envio de configuração ao firmware.
- Ícone, abertura e identificação próprios — sem símbolo padrão do Godot.

## Hardware

- Arduino Nano ou Uno (ATmega328P).
- **MPU-6050** (acelerômetro + giroscópio) fixado no saco, no I2C.
- Placa USB Zero Delay para os botões arcade, ou os botões direto na placa.

### Ligação

| MPU-6050 | Arduino |
| --- | --- |
| VCC | 5 V (ou 3,3 V, conforme o módulo) |
| GND | GND |
| SDA | A4 |
| SCL | A5 |
| AD0 | GND (endereço 0x68) |

| Botão do gabinete | Arduino |
| --- | --- |
| START | D2 → GND |
| CREDIT / SELECT | D3 → GND |

Os botões usam o `INPUT_PULLUP` interno: ligam direto no GND, sem
resistor externo. Quem preferir uma placa USB Zero Delay em vez dos
pinos do Arduino tem o caminho alternativo pronto: as ações
`input_start` e `input_credito` do `project.godot` já respondem a botões
de controle (por padrão, os índices 6 e 4). Cada placa numera os botões
de um jeito, então confira o índice da sua em **Projeto → Configurações
do Projeto → Mapa de Entrada**. O cabo do sensor deve ficar afastado de motor,
solenoide e cabos de potência. Em máquina com ruído elétrico, use fonte
estabilizada, aterramento correto e cabo de sinal blindado.

## Instalação

1. Grave `arduino/punch_sensor/punch_sensor.ino` no Arduino a 115200 bps.
2. Abra `project.godot` no Godot 4.4 ou mais recente (a extensão serial
   `gdserial` exige 4.4).
3. Execute o projeto e pressione `F9`.
4. **Não escolha porta nenhuma** — deixe em `AUTO`. O jogo varre as
   portas anunciadas pelo sistema, e depois `COM1`…`COM32` uma por uma,
   até a placa responder. Fixar uma porta à mão só faz sentido para
   depurar, e a porta certa num PC é a errada no outro.
5. Balance o saco: a linha de diagnóstico deve mostrar telemetria.

Sem a extensão serial, ou sem Arduino, o jogo continua funcionando em
**modo simulação** — nada trava por falta de hardware.

### Câmera no Windows

O projeto inclui `CameraServerExtension`, que captura a webcam diretamente
pelo **Windows Media Foundation**. Não é preciso instalar Python, OpenCV,
driver virtual ou serviço separado: conecte uma câmera USB e abra o jogo.
Se ela for conectada depois, a busca automática a encontra; o botão
**PROCURAR DE NOVO** força uma nova enumeração imediatamente.

O feed fica aberto e a prévia usa a textura nativa continuamente. Só o
retrato capturado é congelado por um instante; a câmera não é fechada nem
reaberta a cada foto. As imagens ficam somente em `user://ranking_photos`;
não há envio para internet nem reconhecimento facial. O PowerShell é usado
apenas pelo diagnóstico de dispositivos e privacidade do Windows.

## Central Técnica (F9)

| Seção | Para quê |
| --- | --- |
| **Modo de operação** | Livre ou 1 ficha por partida. |
| **Botões do gabinete** | Mapeamento da placa Zero Delay: aperte o botão de verdade e o jogo grava controle, índice e nome. Um contador por botão prova que pegou. |
| **Simulação de bancada** | A chave que libera a barra de espaço. Desligada de fábrica. |
| **A régua do soco** | Velocidade mínima, máxima e o **soco de referência** (a que paga 5000), mais o contraste — com a curva desenhada. |
| **Os oito níveis** | Régua de leitura. Mostra a desproporção real: os quatro níveis de cima ocupam um quinto da escala. |
| **Assistente de calibração** | Mede a máquina em quatro passos em vez de regular por tentativa e erro. |
| **Sensor e firmware** | Porta serial, polaridade do sinal, largura da palheta e envio de configuração. O **pulso mínimo** aparece como leitura: ele é calculado, não escolhido. |
| **Câmera e som** | Prévia ao vivo, troca de câmera, foto de teste, volumes de trilha e efeitos, soco de teste. |
| **Dados** | Ranking, estatísticas, telemetria, contadores dos botões e o que apagar. |

A Central tem **quatro páginas**, e um controle só responde na página
aberta: os retângulos continuam existindo quando não estão desenhados, e
botão invisível que responde é a pior espécie de defeito.

Cada par `−` / `+` sai da tabela `PASSOS` no topo de `scripts/main.gd`: o
mesmo retângulo desenha o botão e confere o clique, e o valor é
desenhado **no espaço livre entre os dois** — não há como um número
cobrir uma área de toque.

## Calibração da pontuação

Use o **assistente**, na Central Técnica → GOLPE → *Assistente de
calibração*. Quatro passos:

1. **Repouso** — não encoste no saco por quatro segundos. Mede o nível de
   sinal do sensor parado (no LM393 é a leitura de A0, de 0 a 1 — não é
   uma aceleração, e não entra em conta nenhuma: serve para conferir a
   olho se o sensor está enxergando).
2. **Cinco golpes fracos** — bata de leve, como quem testa.
3. **Cinco golpes fortes** — bata com tudo, como o melhor cliente da noite.
4. **Sugestão** — as três âncoras e o pulso mínimo, cada um com o motivo
   escrito ao lado, e a curva **desenhada** antes de salvar.

A conta usa **percentis**, não mínimo e máximo: em cinco socos, um
escorrega no saco e outro pega de raspão, e com o extremo a calibração
inteira dependeria do pior e do melhor golpe do dia. O piso desce 15 %
abaixo do percentil 20 dos fracos, para quem bate de leve ver *algum*
ponto; o teto sobe 22 % acima do percentil 80 dos fortes, para 9999
continuar raro — se o teto fosse o golpe mais forte já medido, o primeiro
cliente forte zeraria o desafio na primeira noite. O **soco de
referência** cai entre o fraco típico e o forte típico, mais perto do
forte: quem calibra dá o golpe fraco de propósito mais fraco do que
qualquer cliente daria.

Salvando, os valores vão para a máquina **e** para o firmware do sensor.

### A curva tem três âncoras, e não um expoente

A nota sai de `scripts/score_curve.gd`, por três pontos que valem sempre:

| Âncora | O que é | Paga |
| --- | --- | --- |
| **Velocidade mínima** | abaixo disso não é soco | `0000` |
| **Soco de referência** | o golpe do cliente médio | **`5000`, sempre** |
| **Velocidade máxima** | o teto da máquina | `9999` |

O **contraste** é o segundo ajuste e é ortogonal ao primeiro: ele decide
quanto a nota se espalha *entre* as âncoras e não mexe em nenhuma delas.
Dá para mexer nele com o salão cheio sem medo — um soco médio continua
pagando 5000.

Quem regula a **dificuldade** é o soco de referência: exigir mais
velocidade para pagar meio placar é, literalmente, a máquina ficar mais
difícil, e isso se explica ao dono da máquina sem falar em expoente.

A versão anterior usava uma potência única, `9999 × x^2,20`. Uma potência
acima de 1 esmaga o meio da escala — que é onde está quase todo mundo. Um
soco a 35 % da faixa calibrada, aceito pela placa, pagava **974 pontos**;
com as âncoras, paga cerca de **2700**. "Mil" lê como máquina que não
registrou, e era essa a reclamação.

Parâmetros de fábrica: mínima `0,30 m/s`, máxima `5,20 m/s`, referência em
55 % da faixa e contraste `1,15`. Para cada montagem, prefira o
assistente acima.

### A régua aprende sozinha — e é ela que resolve o "não passo de mil"

O sintoma mais comum de uma máquina recém-montada é todo mundo tirar a
mesma nota baixa. Quase nunca é o cliente batendo fraco: é a **régua**
estar descrevendo a bancada em vez do gabinete.

A faixa de fábrica vai de `0,30` a `5,20 m/s` porque foi assim que a
bancada mediu. Dependendo de onde a palheta foi parafusada, de quanto o
braço cede e da largura real da fenda, a mesma montagem entrega no máximo
`1,2 m/s` — e aí a máquina inteira vive no primeiro quinto da escala:

| velocidade | com a régua de fábrica | com a régua aprendida |
| --- | --- | --- |
| 0,6 m/s | 246 | 1525 |
| 1,0 m/s | 782 | 5550 |
| 1,2 m/s | 1105 | 7739 |

Mesmo sensor, mesmo soco, mesma curva. Só a régua mudou.

Com o **aprendizado ligado** (padrão), a máquina guarda a velocidade de
cada soco aceito e move as três âncoras, um passo por rodada, para os
percentis do que ela de fato mede: a mediana vira o soco de referência.
Isso quer dizer que **metade do salão fica acima de 5000 e metade abaixo,
em qualquer gabinete**, sem ninguém configurar nada.

Quatro travas impedem que aprender sozinha vire um problema: nada
acontece com menos de 12 socos na memória; cada ajuste anda no máximo 12 %
da distância até o alvo (uma criança batendo dez vezes não derruba a
régua); a janela é de 240 socos; e o resultado passa pelo mesmo
saneamento de qualquer outro ajuste. Na Central dá para **desligar** o
aprendizado e congelar a régua, ou **apagar a memória** e recomeçar.

### Regular com um soco e um toque

Na Central → GOLPE, a leitura ao vivo mostra o último soco em **m/s**, a
nota que ele pagou e **onde ele caiu dentro da régua**. Quando todo mundo
tira mil pontos, a barra fica colada na esquerda — e aí a resposta deixa
de ser "o pessoal bate fraco".

Abaixo dela, três botões: **É O MÍNIMO**, **É O SOCO MÉDIO**, **É O
MÁXIMO**. Bata uma vez e toque no que aquele soco deve valer; a régua se
ajusta na hora e vai para o firmware junto. É o caminho para usar com a
fila esperando — o assistente de dez golpes continua sendo o jeito certo
de calibrar do zero.

### Nunca regule o pulso mínimo à mão

Ele não tem mais `−` e `+`, e isso é proposital. A palheta atravessa a
fenda, então **quanto mais forte o soco, mais curto o pulso**: exigir um
pulso mínimo maior não deixa a máquina mais sensível, deixa-a cega para
os socos rápidos. Com palheta de 20 mm, um pulso mínimo de 5 ms manda a
placa recusar tudo acima de 4 m/s — em silêncio.

Hoje ele sai da largura da palheta e do teto calibrado, pela mesma regra
que o firmware já aplica sozinho. Na Central aparece como leitura, com a
janela que a montagem enxerga escrita ao lado — se a régua de pontuação
não couber dentro dela, a linha fica vermelha.

## Teste sem Arduino

Ligue a chave **SIMULAÇÃO DE BANCADA** na Central (página OPERAÇÃO), ou
rode o jogo com `PUNCH_SIMULACAO=1` no ambiente. Com ela ligada:

- **segure a barra de espaço para carregar e solte para socar** — o visor
  mostra, a cada instante, exatamente quantos pontos sairão;
- `1` / `Enter` fazem o papel do START e `5` / `C` adicionam crédito.

Desligada — que é como ela sai de fábrica — nada disso responde, e a tela
não menciona teclado nenhum. Num salão, a barra de espaço ligada é
qualquer pessoa tirando 9999 sem encostar no equipamento, e um teclado
esquecido no armário vira crédito de graça.

A Central mostra a chave em **vermelho** quando está ligada, com o aviso
`DESLIGUE ANTES DE ABRIR O SALÃO`.

Com o Arduino ligado, o botão **TESTAR SENSOR** (ou a tecla `T` na
Central) pede um golpe sintético à placa: se ele aparece na tela e o
soco real não, o problema é o sensor, e não o software.

## Conferir a tela sem abrir o editor

```
godot --path . --script tools/capturar_telas.gd
```

Percorre todos os momentos do jogo — abertura, contagem, sensor armado,
carga, impacto, contagem do placar, os três vereditos e a Central
Técnica — e salva um PNG de cada um em `.telas/` (ou na pasta apontada
por `PUNCH_SHOTS`). É como se confere que nada saiu da sua banda depois
de mexer no traçado.

## Exportação Windows

O preset já está incluído. A entrega recomendada é feita por
`tools/exportar_windows.ps1`: ele exporta para
`build/windows/PunchChallenge.exe`, confere o PCK e as DLLs da câmera e da serial e
só então cria `build/PunchChallenge-Windows-x64.zip`.

**Leve e extraia o ZIP inteiro na outra máquina, não só o `.exe`.** O pacote
do jogo fica em `PunchChallenge.pck`, separado para evitar falhas de
incorporação; as extensões nativas da serial e da câmera também precisam
acompanhar a exportação. O Godot coloca `gdserial.dll` e
`libcameraserver-extension.windows.dll` ao lado da distribuição. Copiando
só o `.exe`, o Arduino ou a câmera podem não funcionar.

Pela mesma razão vale instalar, uma vez por máquina, o **Microsoft
Visual C++ 2015-2022 Redistributable (x64)**: o `gdserial.dll` depende
dele (`VCRUNTIME140.dll`) e o Windows limpo não o traz. Sem ele o
Windows recusa a extensão em silêncio — é a causa número um de
"funciona no meu PC e não no outro". Confira com `where VCRUNTIME140.dll`
num terminal da máquina; nada listado quer dizer que falta.

## De que este jogo depende

A resposta curta: para JOGAR, de nada além do próprio executável, da
pasta que o acompanha e do Windows. Não há linguagem para instalar, nem
interpretador, nem biblioteca de cálculo. A tabela é a resposta longa.

| o que | onde entra | é preciso instalar? |
|---|---|---|
| **Godot 4.6** | o motor; gera o `.exe` e o `.pck` na exportação | não — vai no pacote |
| **`gdserial.dll`** | abre a porta COM do Arduino | não — sai na exportação, **ao lado** do `.exe` |
| **`libcameraserver-extension.windows.dll`** | a webcam, por Media Foundation | não — idem |
| **Visual C++ 2015-2022 Redistributable (x64)** | as duas DLLs acima dependem dele | **sim, uma vez por máquina** |
| `reg.exe`, `tasklist.exe`, `pnputil.exe` | diagnóstico da câmera (F9) | não — são do Windows |
| `powershell.exe` | **só** o plano B da serial, quando a DLL não carrega | não — é do Windows |

O empacotador reprova a entrega se qualquer DLL estiver ausente. Assim, a
unidade transportável do jogo é sempre o ZIP verificado, e a Central mostra
"PACOTE INCOMPLETO" quando uma instalação foi desmontada.

**O PowerShell fica, de propósito.** Ele não é uma dependência no sentido
que incomoda: já vem no Windows, não se instala, não se atualiza. E ele é
o plano B da porta serial — quando a `gdserial.dll` não carrega (e no
gabinete do operador ela NÃO carregou), é o que mantém START, CRÉDITO e o
sensor vivos em vez de deixar a máquina inteira em "SIMULAÇÃO". Tirá-lo
seria trocar uma dependência que não custa nada por uma máquina morta na
noite em que a DLL falhar.

**O que saiu.** Python (o lutador, o banco de áudio inteiro e o ícone),
NumPy, Blender, o `lutador.glb` e o `camera_windows.ps1` do diagnóstico
da câmera. Resta um único uso de Python no repositório —
`tools/conferir_ponte.sh`, um teste de desenvolvimento que roda só em
Linux e usa Python para abrir um par de pseudo-terminais. Ele não vai
para a exportação e o jogo nunca o chama; existe porque é o único teste
que põe o `ponte_serial.ps1` de verdade para conversar com uma porta
serial de verdade.

## Refazer o som e o ícone

Nada disso é preciso para JOGAR — os arquivos viajam prontos no
repositório. É preciso para MUDAR um som ou o ícone, e é aqui que estava
a última dependência de linguagem do projeto: o banco de áudio inteiro e
o ícone eram sintetizados por scripts em Python, dois deles exigindo
NumPy. Hoje é o próprio Godot que faz as duas coisas:

```
godot --headless --path . --script tools/gerar_audio.gd
godot --headless --path . --script tools/gerar_icone.gd
```

O primeiro reescreve os 37 arquivos de `assets/audio/arcade/` em cerca
de vinte segundos: efeitos, os oito níveis, avisos de operação, os dois
loops, a música da abertura e os sons da arena. Para conferir um banco
novo contra o que já está no repositório sem sobrescrevê-lo:

```
godot --headless --path . --script tools/gerar_audio.gd -- /tmp/audio_novo
godot --headless --path . --script tools/conferir_audio.gd -- /tmp/audio_novo
```

A conferência compara duração, pico, volume percebido e a energia em três
faixas — e não amostra por amostra, porque metade de cada som é ruído e
ruído branco não tem forma, só estatística.

O segundo rasteriza o emblema oficial
`assets/branding/punch_emblem.svg` em `assets/icon.png` e
`assets/icon-android.png` (512 × 512), sem redesenhar a marca. O Windows usa
o próprio `assets/icon.png`: no Godot 4, o exportador Windows converte PNG
para o recurso nativo do executável com mais segurança que um ICO produzido
externamente. O preset Android usa explicitamente `assets/icon-android.png`.

## Documentação

- `docs/PROTOCOLO_SERIAL.md` — todas as mensagens entre placa e jogo,
  os limites aceitos e um guia de diagnóstico.

## Segurança mecânica

Instale batentes, proteções e amortecimento adequados para impedir que o
mecanismo alcance o operador. O sensor e o Arduino não substituem
proteções físicas, parada de emergência nem projeto mecânico seguro.
