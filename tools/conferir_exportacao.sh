#!/bin/sh
# CONFERE O QUE PRECISA ESTAR NO EXECUTAVEL -- antes de exportar.
#
# POR QUE ISTO EXISTE. A conversa com o Arduino depende de uma extensao
# NATIVA (gdserial), um .dll que viaja junto do executavel. No computador
# de quem desenvolve ele esta sempre la, entao o defeito nunca aparece
# ali: ele aparece no PC novo, no notebook levado para a festa, e o
# sintoma e "nao funciona nada" -- START morto, CREDITO morto, sensor
# mudo. Horas procurando fio solto por causa de um arquivo.
#
# Uso:  sh tools/conferir_exportacao.sh
set -e
raiz=$(dirname "$0")/..
extensoes="
$raiz/addons/gdserial/gdserial.gdextension
$raiz/addons/CameraServerExtension/CameraServerExtension.gdextension
"

echo "--- as extensoes da serial e da camera estao declaradas? ---"
for ext in $extensoes; do
  [ -f "$ext" ] || { echo "FALTA $ext"; exit 1; }
  printf '    ok   %s\n' "$ext"
done

echo "--- os binarios que ela aponta existem? ---"
# Cada linha `plataforma = "res://..."` da secao [libraries].
# O `_` PRECISA ESTAR NA CLASSE DE CARACTERES.
#
# Sem ele o padrao nao casa com `linux.debug.x86_64` nem com
# `windows.release.x86_64` -- e o binario que este verificador existe
# para conferir, o .dll do Windows de 64 bits, era justamente um dos que
# escapavam. Um verificador com um furo no meio e pior do que nenhum:
# ele da OK e a pessoa confia.
for ext in $extensoes; do
  alvos=$(sed -n 's/^[a-z0-9._]* *= *"res:\/\/\(.*\)"$/\1/p' "$ext" | sort -u)
  for alvo in $alvos; do
    if [ -f "$raiz/$alvo" ]; then
      printf '    ok   %s\n' "$alvo"
    else
      printf '    FALTA %s\n' "$alvo"
      echo "Binario de extensao faltando: a distribuicao sai incompleta."
      exit 1
    fi
  done
done

echo "--- caminhos declarados que nao existem (doc, icones) ---"
for ext in $extensoes; do
  if grep -q '^\[documentation\]' "$ext"; then
    echo "    HA uma secao [documentation] em $ext."
    exit 1
  fi
done
echo "    nenhum."

echo "--- sobrou lixo VERSIONADO no pacote? ---"
# PERGUNTA AO GIT, E NAO AO DISCO.
#
# `~gdserial.dll` NASCE sozinho na maquina de quem desenvolve: no Windows
# nao da para sobrescrever uma DLL carregada, entao o editor do Godot
# copia a atual para um nome com `~` na frente. Olhar o disco reprovaria
# toda maquina com o projeto aberto -- e, pior, sugeriria apagar um
# arquivo que o Windows nao deixa apagar, que foi como um `git pull`
# entrou num laco infinito de "Unlink failed. Should I try again?".
#
# O que nao pode e ele estar VERSIONADO. E isso que se pergunta aqui.
lixo=$(cd "$raiz" && git ls-files 'addons/**/~*' '**/*.tmp' 2>/dev/null | head -5)
if [ -n "$lixo" ]; then
  echo "    LIXO VERSIONADO: $lixo"
  echo "    (no disco tudo bem: o Godot recria. So nao pode entrar no git.)"
  exit 1
fi
echo "    nao."

echo "--- a exportacao cai numa pasta transportavel? ---"
grep -q '^export_path="build/windows/PunchChallenge.exe"$' "$raiz/export_presets.cfg" || {
  echo "    Caminho de exportacao inseguro: use build/windows/PunchChallenge.exe"
  exit 1
}
echo "    ok   build/windows/PunchChallenge.exe"
grep -q '^binary_format/embed_pck=false$' "$raiz/export_presets.cfg" || {
  echo "    PCK embutido esta ativo e pode corromper o cabecalho do EXE."
  exit 1
}
echo "    ok   PCK separado do executavel"
echo "EXPORTACAO_OK"
