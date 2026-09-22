# A arena e o lutador

Esta é a única diferença entre `punch-challenge-animated` e
`punch-challenge`. O resto do jogo — sensor, ponte serial, câmera,
ranking, Central Técnica, exportação — é o mesmo código, e deve continuar
sendo: correção que entra num repositório precisa poder entrar no outro
sem tradução.

## O que mudou na tela do soco

Antes, o meio da tela do soco era um alvo desenhado (na espera) e um
medalhão redondo com o número (no resultado). Os dois ocupavam o mesmo
retângulo escuro que o fundo do jogo já reservava, e os dois eram
desenho 2D plano.

Agora esse retângulo é uma **janela 3D com moldura**: um ringue de
verdade, com câmera, luz e perspectiva, e um lutador dentro dele que
**recua na medida do soco** e vai à lona quando não aguenta mais.

    ┌──────────────────────────────────────┐
    │              PUNCH CHALLENGE         │
    │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓    │
    │ █┃  ADVERSÁRIO · ABALADO 46%    ┃█   │  ← as colunas de dano
    │ █┃ ┌──────────────────────────┐ ┃█   │
    │ █┃ │                          │ ┃█   │
    │ █┃ │    a arena em 3D         │ ┃█   │  ← o SubViewport
    │ █┃ │                          │ ┃█   │
    │ █┃ └──────────────────────────┘ ┃█   │
    │  ┗━━━━━━━┏━━━━━━━━━━━━┓━━━━━━━━━┛    │
    │          ┃    8420    ┃              │  ← a plaqueta do placar
    │          ┗━━━━━━━━━━━━┛              │
    │              NOCAUTE                 │
    │        DIRETO NO QUEIXO!             │  ← a frase
    │   ┌───────────┐  ┌───────────┐       │
    │   │  SOCO 1   │  │  SOCO 2   │       │
    └──────────────────────────────────────┘

As medidas moram todas em `ArenaQuadro` (`scripts/arena/quadro.gd`),
como constantes públicas, porque três coisas dependem delas: o desenho,
o tamanho da janela 3D (que precisa da mesma proporção, senão a imagem
chega esticada) e os testes.

## As peças

| arquivo | o que faz |
|---|---|
| `assets/personagem/sprites/` | a folha de nove poses e o `SpriteFrames` |
| `scripts/arena/lutador.gd` | as poses, o movimento por cima delas e as reações |
| `scripts/arena/arena3d.gd` | o mundo 3D dentro do `SubViewport` |
| `scripts/arena/quadro.gd` | a moldura e as colunas de dano, em 2D |
| `scripts/arena/frases.gd` | o que a máquina grita a cada nível |
| `scripts/ranking_celebration.gd` | quatro cerimônias, conforme a colocação |
| `tests/test_arena.gd` | o que não pode voltar a quebrar |

## O lutador é desenhado, e o movimento é código

O adversário são **nove ilustrações** numa folha 3×3
(`assets/personagem/sprites/lutador_folha_3x3.png`, 410 × 426 px por
pose), montadas num `AnimatedSprite3D` **dentro** da arena 3D — e não
numa camada 2D por cima dela. A diferença importa: assim o lutador
continua no ringue, com a perspectiva real, a câmera que recua no
impacto, o tremor, as partículas, a luz ciano e magenta e o
enquadramento do nocaute. Nada disso precisou ser reescrito.

### Por que o corpo procedural saiu

Ele era construído em GDScript: anéis torneados, músculo modelado,
sombreador de desenho com brilho por material e contorno por casca
invertida. Tecnicamente funcionava e custava onze chamadas de desenho.
Visualmente nunca chegou onde precisava — a queixa final foi "grosso,
cabelo mal definido, sem profundidade, o antebraço parece colado ao
tórax", e as quatro estavam certas. **Geometria feita de elipsoides
somados tem um teto de qualidade, e esse teto fica bem abaixo de uma
ilustração.** Quem mantém isto depois de mim: não tente atravessar esse
teto outra vez.

### As nove poses, e o que cada uma faz

| pose | papel no jogo |
|---|---|
| `guarda`, `idle` | alternam na respiração e na guarda |
| `preparado` | o agachamento, segundo quadro da guarda |
| `jab`, `direto` | o **desdém**: ele devolve dois socos no ar |
| `impacto_corpo` | golpe leve e médio |
| `impacto_forte` | golpe pesado e cambaleio |
| `nocaute` | na lona |
| `recuperacao` | levantando |

Nove papéis e nove desenhos, mas a correspondência **não é um para um**,
e é de propósito: `hit_light` e `hit_medium` partilham a mesma
ilustração porque a diferença entre um e outro não está no desenho, está
no quanto o corpo recua e em quanto tempo volta.

### O movimento é tudo o que a folha não tem

Cada pose é UM desenho parado. O que transforma nove desenhos num
lutador é o movimento procedural de `scripts/arena/lutador.gd`:

* a **respiração**, um balanço de um centímetro e meio que nunca para —
  sem ela o desenho denuncia que é um desenho no primeiro segundo;
* o **recuo**, que anda para trás, tomba e desliza para o lado conforme
  a tabela `RECUO`, e volta com uma curva que sai depressa e assenta
  devagar, que é como um corpo que levou um soco se recompõe;
* o **cambaleio**, que balança de lado enquanto volta — é o que separa
  "levou um soco" de "perdeu a base";
* o **tombo**, que desce o corpo até a lona com um repique curtíssimo no
  fim, e é a única coisa que não volta sozinha: ela espera o `get_up`;
* o **clarão** do impacto e o tom que puxa para o vermelho conforme o
  dano acumula.

É a técnica de um jogo de luta 2D clássico — poucos quadros, muita
física por cima —, e é ela que faz um soco leve e um soco que derruba
parecerem coisas diferentes mesmo quando a ilustração de fundo é a
mesma. A escada entre as reações (`DURACAO` e `RECUO`) é conferida por
teste: uma reação mais forte tem de durar mais e empurrar mais.

### Duas armadilhas que o render ensinou

**O tamanho vem do `pixel_size`.** A folha não sabe de metros: são 426
pixels de altura, e é `pixel_size` que decide se aquilo vira um lutador
de 1,80 m ou um gigante que estoura o quadro. Estourou na primeira
montagem, e é um erro que teste nenhum pega olhando só para o código —
por isso `tests/test_arena.gd` confere a escala em metros.

**No nocaute a câmera AFASTA, não aproxima.** Um corpo em pé é alto e
estreito; um corpo caído é baixo e largo, e o desenho do nocaute ocupa a
largura inteira do quadro. Chegando perto — que é o instinto, e o que a
versão 3D fazia certo — a imagem corta os dois braços e sobra um torso
gigante sem contexto. E ela continua **de frente**: o desenho já mostra
o corpo do ângulo certo, e dar a volta nele mostraria um plano de
perfil, ou seja, uma lâmina.

### O custo

Uma chamada de desenho, contra as onze do corpo procedural. Medido com
o jogo rodando, o quadro fica em 6,92 ms de mediana e 7,14 no pior caso
— idêntico a antes da troca.

### Trocar a arte

Substitua a folha e o `lutador_sprite_frames.tres`, mantendo os nove
nomes de pose da tabela acima. `Lutador3D.PAPEIS` é o mapa entre papel
do jogo e desenho; `tests/test_arena.gd` falha se faltar qualquer um.


## Premiação e torcida

A colocação escolhe uma receita própria em `RankingCelebration`:

- **1º lugar:** selo de campeão, três canhões, chuva cheia e torcida longa;
- **2º–3º:** cerimônia de pódio, dois canhões e torcida própria;
- **4º–10º:** entrada no Top 10, um canhão e comemoração média;
- **11º–20º:** reconhecimento curto, sem fingir que foi recorde.

Os quatro sons são estéreo e combinam massa vocal, canto de arquibancada,
palmas, assobios e reverberação de ginásio. O confete é atualizado no lugar
e desenhado como uma fita de uma chamada, evitando a alocação e a
triangulação que faziam a chuva engasgar.

Abaixo de **6.000 pontos**, o adversário baixa a guarda, nega com a cabeça
e desdenha, acompanhado por vaias e assobios próprios. Com 6.000 ou mais
ele reconhece o golpe e reage fisicamente; caído na lona, nunca desdenha.

## O dano

Cada soco tira `forca × 0,62` do adversário (`Lutador3D.DANO_POR_GOLPE`),
onde `forca` é a posição da velocidade real dentro da faixa calibrada.
A nota continua usando o expoente competitivo, mas ele não achata a
animação: golpe físico médio parece médio, mesmo com pontuação difícil.
Na prática:

- dois socos perfeitos derrubam;
- um soco leve quase não mexe no medidor (e abaixo de 2% não conta,
  senão o ruído do sensor encheria a barra sozinho ao longo da noite);
- os níveis com *hit-stop* na tabela do `ScoreTier` — NOCAUTE,
  PESO-PESADO, LENDÁRIO e SOCO PERFEITO — derrubam **no primeiro golpe**,
  independentemente do medidor.

Quem cai permanece visível na lona e completa queda/levantamento em cerca
de 5 s, com o medidor voltando a 72%: a
rodada tem dois socos, e o segundo precisa ter para onde ir.

**Cada rodada começa com o adversário inteiro.** Herdar o dano faria a
segunda pessoa da fila derrubar alguém que já estava caindo, e as
colunas laterais mentiriam sobre o que ela fez.

## O custo, que é o que interessa numa TV Box

Esta versão vai para o mesmo aparelho que a original, então a arena foi
construída para custar pouco, não para impressionar em benchmark:

- **uma malha só** para todo o ringue (lona, borda, quatro postes, nove
  cordas, fundo), com cor por vértice — um desenho em vez de trinta;
- **três luzes**, nenhuma com sombra;
- **flashes e silhuetas da plateia em `MultiMesh`** — dois desenhos, com
  reação proporcional à força;
- **dois emissores GPU reutilizados** para faíscas e poeira da lona;
- **sem antisserrilhado, sem brilho, sem TAA**;
- **a janela encolhe** quando o vigia de desempenho aperta
  (`Desempenho.qualidade < 0,55`), mas continua atualizando em todo quadro;
- **a janela só desenha nas telas da rodada.** Liga no 3–2–1, permanece
  até o resultado e desliga na abertura, na tabela e na Central
  (`main.gd::_arena_no_ar`).

Para medir na máquina de destino:

```
godot --path . --script tools/medir_arena.gd
```

Ele roda a mesma tela duas vezes, com e sem a janela 3D, e imprime a
diferença. Não use `--headless`: sem rasterizador o custo do 3D não
aparece. Num PC de desenvolvimento com vídeo por software (llvmpipe), a
arena custou **0,77 ms por quadro** — menos de 4% de um quadro que já
levava 21 ms só com o 2D. Com GPU de verdade a diferença é menor ainda.

## Conferir

```
godot --headless --path . --script tests/test_arena.gd
godot --path . --script tools/capturar_telas.gd   # PNG de cada tela
```

`tests/test_arena.gd` guarda, entre outras coisas, os dois erros que a
arena cometeu de verdade durante a construção:

- **o nocaute afundava o lutador.** A queda baixava o corpo 62 cm além
  de tombá-lo; como o nó raiz fica na altura da lona, o boneco saía por
  baixo do ringue e a moldura mostrava um ringue vazio no momento mais
  importante do jogo;
- **a janela 3D e o buraco da moldura tinham proporções diferentes**, e
  a imagem chegava esticada.

As capturas ficam em `.telas/` (ignorado pelo Git) e são o jeito mais
rápido de conferir a tela inteira sem montar o gabinete.
