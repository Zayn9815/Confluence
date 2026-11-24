#!/usr/bin/env python3
"""
Deterministic Apple Core Audio Format (.caf) alert sound generator for Confluence.
Produces studio-clean, short (<1.5s), Linear PCM 16-bit little-endian 44.1 kHz mono .caf files
ready for top-level bundling in Confluence.app (UNNotificationSound + AVAudioPlayer).
Uses pure Python standard library only.
"""

import math
import os
import struct
from pathlib import Path

SAMPLE_RATE = 44100


def write_caf_le_i16(path: Path, samples: list[float]) -> None:
    """Write mono 16-bit little-endian Linear PCM into a valid CAF v1.0 container."""
    pcm = bytearray()
    for s in samples:
        clamped = max(-0.98, min(0.98, s))
        pcm.extend(struct.pack("<h", int(round(clamped * 32767.0))))

    # CAFFileHeader: 'caff', version=1, flags=0
    header = struct.pack(">4sHH", b"caff", 1, 0)

    # Audio Description chunk ('desc', 32 bytes payload)
    # mFormatFlags = 2 -> kCAFLinearPCMFormatFlagIsLittleEndian (signed int)
    desc_payload = struct.pack(
        ">d4sIIIII",
        float(SAMPLE_RATE),
        b"lpcm",
        2,   # little-endian signed integer PCM
        2,   # bytes per packet
        1,   # frames per packet
        1,   # channels per frame
        16,  # bits per channel
    )
    desc_chunk = struct.pack(">4sq", b"desc", len(desc_payload)) + desc_payload

    # Audio Data chunk ('data', 4-byte editCount + PCM bytes)
    data_payload = struct.pack(">I", 0) + bytes(pcm)
    data_chunk = struct.pack(">4sq", b"data", len(data_payload)) + data_payload

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + desc_chunk + data_chunk)


def env_ad(t: float, attack: float, decay: float) -> float:
    if t < 0.0:
        return 0.0
    if t < attack:
        return t / max(attack, 1e-6)
    return math.exp(-(t - attack) / max(decay, 1e-6))


def synth_note(total_sec: float, notes: list[tuple[float, float, float, float, list[tuple[float, float]]]]) -> list[float]:
    """
    Synthesize additive bell/chime notes.
    Each note: (start_sec, base_freq, amp, decay_sec, [(harmonic_mult, rel_amp), ...])
    """
    n = int(total_sec * SAMPLE_RATE)
    buf = [0.0] * n
    for start_s, freq, amp, decay_s, harmonics in notes:
        start_idx = int(start_s * SAMPLE_RATE)
        for i in range(start_idx, n):
            t = (i - start_idx) / SAMPLE_RATE
            e = env_ad(t, 0.004, decay_s)
            if e < 1e-4:
                continue
            val = 0.0
            for mult, h_amp in harmonics:
                # Subtle upper-harmonic faster decay for warm metallic timbre
                h_decay = math.exp(-t * (mult - 1.0) * 3.5)
                val += h_amp * h_decay * math.sin(2.0 * math.pi * (freq * mult) * t)
            buf[i] += amp * e * val

    # Smooth fade-out tail (last 20ms) to guarantee zero clicks
    fade_n = int(0.02 * SAMPLE_RATE)
    for k in range(fade_n):
        idx = n - fade_n + k
        if idx >= 0:
            buf[idx] *= 1.0 - (k / fade_n)
    return buf


def generate_all(output_dir: Path) -> None:
    bell_harmonics = [(1.0, 1.0), (2.0, 0.34), (3.0, 0.14), (4.2, 0.06)]
    glass_harmonics = [(1.0, 1.0), (2.0, 0.22), (2.76, 0.12)]

    # 1. Terminal Chime — refined ascending champagne-gold major-9th institutional chime
    terminal_chime = synth_note(
        0.95,
        [
            (0.00, 587.33, 0.38, 0.28, bell_harmonics),   # D5
            (0.11, 880.00, 0.42, 0.34, bell_harmonics),   # A5
            (0.23, 1318.51, 0.36, 0.44, bell_harmonics),  # E6
        ],
    )
    write_caf_le_i16(output_dir / "terminal_chime.caf", terminal_chime)

    # 2. Sonar Pulse — crisp dual radar ping
    sonar_pulse = synth_note(
        0.85,
        [
            (0.00, 1046.50, 0.42, 0.16, glass_harmonics),  # C6
            (0.22, 1396.91, 0.38, 0.32, glass_harmonics),  # F6
        ],
    )
    write_caf_le_i16(output_dir / "sonar_pulse.caf", sonar_pulse)

    # 3. Vault Lock — low authoritative mechanical click + metallic confirm harmonic
    vault_lock = synth_note(
        0.75,
        [
            (0.00, 220.00, 0.45, 0.08, [(1.0, 1.0), (1.5, 0.45), (2.5, 0.2)]),
            (0.09, 440.00, 0.38, 0.18, bell_harmonics),
            (0.18, 659.25, 0.36, 0.32, bell_harmonics),
        ],
    )
    write_caf_le_i16(output_dir / "vault_lock.caf", vault_lock)

    # 4. Trap Warning Tone — distinct descending minor-second caution cadence
    trap_warning = synth_note(
        0.85,
        [
            (0.00, 783.99, 0.42, 0.14, [(1.0, 1.0), (2.0, 0.35), (3.0, 0.18)]),  # G5
            (0.15, 622.25, 0.42, 0.16, [(1.0, 1.0), (2.0, 0.35), (3.0, 0.18)]),  # Eb5
            (0.32, 587.33, 0.40, 0.28, [(1.0, 1.0), (2.0, 0.28), (3.0, 0.12)]),  # D5
        ],
    )
    write_caf_le_i16(output_dir / "trap_warning.caf", trap_warning)

    # 5. News Release Ping — bright high-clarity double telegraph ping
    news_ping = synth_note(
        0.80,
        [
            (0.00, 1174.66, 0.38, 0.13, glass_harmonics),  # D6
            (0.12, 1174.66, 0.36, 0.13, glass_harmonics),  # D6
            (0.25, 1760.00, 0.40, 0.30, glass_harmonics),  # A6
        ],
    )
    write_caf_le_i16(output_dir / "news_release_ping.caf", news_ping)

    print(f"Generated 5 deterministic .caf alerts in {output_dir}")


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parent.parent
    out = repo_root / "Confluence" / "Resources" / "Sounds"
    generate_all(out)
