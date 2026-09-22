#!/usr/bin/env python3
"""Gera vinhetas instrumentais sem voz para ranking e desconexão."""

from pathlib import Path
import wave
import numpy as np

TAXA = 44100
DESTINO = Path(__file__).resolve().parents[1] / "assets" / "audio" / "arcade"


def envelope(t, ataque=0.008, queda=2.8):
    return np.minimum(t / ataque, 1.0) * np.exp(-t * queda)


def tom(t, frequencia, inicio, duracao, volume, harmonicos=(1.0, 0.28, 0.12)):
    local = t - inicio
    ativo = (local >= 0.0) & (local < duracao)
    fase = np.maximum(local, 0.0)
    sinal = np.zeros_like(t)
    for indice, ganho in enumerate(harmonicos, 1):
        sinal += np.sin(2.0 * np.pi * frequencia * indice * fase) * ganho / indice
    return sinal * envelope(fase, 0.006, 3.5 / duracao) * ativo * volume


def ruido_metalico(t, inicio, duracao, volume, semente):
    rng = np.random.default_rng(semente)
    local = t - inicio
    ativo = (local >= 0.0) & (local < duracao)
    bruto = rng.normal(0.0, 1.0, t.size)
    # Diferenciação remove o grave fofo e deixa um ataque metálico/seco.
    agudo = np.concatenate(([0.0], np.diff(bruto)))
    agudo /= max(np.max(np.abs(agudo)), 1e-9)
    return agudo * envelope(np.maximum(local, 0.0), 0.002, 9.0 / duracao) * ativo * volume


def salvar(nome, mono):
    pico = max(float(np.max(np.abs(mono))), 1e-9)
    mono = np.tanh(mono / pico * 1.35)
    mono *= 10.0 ** (-1.2 / 20.0) / max(float(np.max(np.abs(mono))), 1e-9)
    # Microabertura estéreo sem alterar o centro da batida.
    atraso = 31
    direita = np.concatenate((np.zeros(atraso), mono[:-atraso]))
    stereo = np.column_stack((mono, direita))
    pcm = np.clip(stereo * 32767.0, -32768, 32767).astype("<i2")
    with wave.open(str(DESTINO / nome), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(TAXA)
        wav.writeframes(pcm.tobytes())


def ranking(nome, notas, semente):
    duracao = 1.85
    t = np.arange(int(TAXA * duracao)) / TAXA
    som = ruido_metalico(t, 0.0, 0.24, 0.26, semente)
    som += tom(t, 92.0, 0.0, 0.42, 0.42, (1.0, 0.18))
    for i, nota in enumerate(notas):
        som += tom(t, nota, 0.12 + i * 0.20, 0.62, 0.34)
    som += tom(t, notas[-1] * 2.0, 0.72, 1.0, 0.26, (1.0, 0.22))
    som += ruido_metalico(t, 0.76, 0.70, 0.16, semente + 100)
    salvar(nome, som)


def explosao_ranking():
    duracao = 1.35
    t = np.arange(int(TAXA * duracao)) / TAXA
    som = tom(t, 82.0, 0.0, 0.42, 0.50, (1.0, 0.20))
    som += ruido_metalico(t, 0.0, 0.32, 0.32, 900)
    for i, nota in enumerate((196.0, 293.66, 392.0, 587.33)):
        som += tom(t, nota, 0.06 + i * 0.105, 0.72, 0.25)
    salvar("ranking_burst.wav", som)


def desconexao():
    duracao = 1.20
    t = np.arange(int(TAXA * duracao)) / TAXA
    som = ruido_metalico(t, 0.0, 0.16, 0.22, 1200)
    # Três pulsos industriais descendentes, claros e sem subgrave cômico.
    for inicio, nota in ((0.03, 440.0), (0.34, 349.23), (0.65, 261.63)):
        som += tom(t, nota, inicio, 0.30, 0.34, (1.0, 0.35, 0.14))
        som += tom(t, nota * 1.5, inicio, 0.24, 0.14, (1.0,))
    salvar("disconnect_alert.wav", som)


def main():
    DESTINO.mkdir(parents=True, exist_ok=True)
    ranking("ranking_neutral_1.wav", (220.0, 277.18, 329.63, 440.0), 101)
    ranking("ranking_neutral_2.wav", (196.0, 246.94, 329.63, 493.88), 202)
    ranking("ranking_neutral_3.wav", (233.08, 293.66, 349.23, 466.16), 303)
    explosao_ranking()
    desconexao()
    print("Sons refinados gerados em", DESTINO)


if __name__ == "__main__":
    main()
