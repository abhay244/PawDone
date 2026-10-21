"""Generates the light background track for the Shorts: plucked chords (C, Am, F, G), a soft
bass and a gentle beat, 96 BPM. Made from scratch, so there are no music rights to worry about.

Usage: python3 make-music.py out.wav [seconds]
"""
import math
import random
import struct
import sys
import wave

RATE = 44100
BPM = 96
BEAT = 60 / BPM
BAR = 4 * BEAT
CHORDS = [  # (root, third, fifth) as MIDI notes
    (60, 64, 67),  # C
    (57, 60, 64),  # Am
    (53, 57, 60),  # F
    (55, 59, 62),  # G
]


def freq(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def pluck(f, seconds, rng, decay=0.996):
    """Karplus-Strong plucked string."""
    period = max(2, int(RATE / f))
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    out = []
    for i in range(int(seconds * RATE)):
        j = i % period
        value = buf[j]
        buf[j] = decay * 0.5 * (value + buf[(j + 1) % period])
        out.append(value)
    return out


def add(mix, start, samples, gain):
    offset = int(start * RATE)
    for i, s in enumerate(samples):
        if offset + i >= len(mix):
            break
        mix[offset + i] += s * gain


def main():
    path = sys.argv[1]
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 60
    rng = random.Random(7)
    mix = [0.0] * int(seconds * RATE)
    bars = int(seconds / BAR) + 1
    for bar in range(bars):
        t0 = bar * BAR
        root, third, fifth = CHORDS[bar % len(CHORDS)]
        # Arpeggio in eighth notes: root, fifth, octave, third, fifth, octave, third, fifth.
        pattern = [root, fifth, root + 12, third + 12, fifth, root + 12, third + 12, fifth + 12]
        for k, note in enumerate(pattern):
            add(mix, t0 + k * BEAT / 2, pluck(freq(note), 0.9, rng), 0.22)
        # Bass: a soft sine on the root, two octaves down, fading over the bar.
        f = freq(root - 24)
        n = int(BAR * RATE)
        bass = [math.sin(2 * math.pi * f * i / RATE) * min(1, i / 800) * math.exp(-2.2 * i / n) for i in range(n)]
        add(mix, t0, bass, 0.35)
        for beat in range(4):
            t = t0 + beat * BEAT
            if beat in (0, 2):  # soft kick
                kick = []
                phase = 0.0
                for i in range(int(0.18 * RATE)):
                    x = i / RATE
                    phase += 2 * math.pi * (50 + 70 * math.exp(-x * 30)) / RATE
                    kick.append(math.sin(phase) * math.exp(-x * 18))
                add(mix, t, kick, 0.45)
            # A light shaker on the off-beat.
            shaker = [rng.uniform(-1, 1) * math.exp(-i / (0.012 * RATE)) for i in range(int(0.06 * RATE))]
            add(mix, t + BEAT / 2, shaker, 0.05)
    # Fade in, then normalise to leave headroom under the voice.
    for i in range(int(0.5 * RATE)):
        mix[i] *= i / (0.5 * RATE)
    peak = max(abs(s) for s in mix) or 1
    scale = 0.7 / peak
    with wave.open(path, "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        frames = bytearray()
        for s in mix:
            v = int(max(-1, min(1, s * scale)) * 32767)
            frames += struct.pack("<hh", v, v)
        out.writeframes(bytes(frames))


main()
