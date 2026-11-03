"""Shared helpers for the htdemucs → CoreML spike: paths, audio I/O, CREPE pitch and the
melody-leakage metric used in docs/test-reports/coreml-spike-2026-11-01.md."""
import os
import resource
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

REPO = Path(__file__).resolve().parents[2]
WORK = Path(os.environ.get("HTDEMUCS_WORK", Path.home() / "htdemucs-spike"))
OUT = WORK / "out"
CLIP = OUT / "clip60.wav"
CREPE_MODEL = REPO / "poc-c6" / "Resources" / "CrepeTiny.mlmodel"

SAMPLE_RATE = 44_100
# htdemucs is evaluated on fixed 39/5 s windows (its training segment).
SEGMENT_SAMPLES = int(39 / 5 * SAMPLE_RATE)
CREPE_RATE = 16_000
CREPE_HOP = 160  # 10 ms
CREPE_CONFIDENCE = 0.5  # CrepePitchDetector.confidenceThreshold
MIN_RMS = 0.001  # CrepePitchDetector.minimumRMS
SAME_NOTE_CENTS = 50


def read_stereo(path):
    x, sr = sf.read(str(path), dtype="float32", always_2d=True)
    assert sr == SAMPLE_RATE, sr
    return x.T.copy()  # (2, n)


def write_stereo(path, x):
    sf.write(str(path), np.asarray(x, dtype=np.float32).T, SAMPLE_RATE, subtype="FLOAT")


def peak_rss_mb():
    # ru_maxrss is bytes on macOS.
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 2**20


def _resample_to_16k(mono):
    import torch
    import torchaudio.functional as AF
    return AF.resample(torch.from_numpy(mono), SAMPLE_RATE, CREPE_RATE).numpy()


_crepe = None


def crepe_track(stereo):
    """Per-10 ms pitch in cents (NaN when unvoiced or quiet) of the mono mix-down."""
    global _crepe
    import coremltools as ct
    if _crepe is None:
        _crepe = ct.models.MLModel(str(CREPE_MODEL), compute_units=ct.ComputeUnit.CPU_AND_NE)
    audio = _resample_to_16k(stereo.mean(axis=0).astype(np.float32))
    audio = np.pad(audio, (512, 512))
    frames = (len(audio) - 1024) // CREPE_HOP + 1
    cents = np.full(frames, np.nan)
    bin_cents = 1997.3794084376191 + 20 * np.arange(360)
    for i in range(frames):
        w = audio[i * CREPE_HOP: i * CREPE_HOP + 1024]
        if np.sqrt(np.mean(w ** 2)) < MIN_RMS:
            continue
        w = (w - w.mean()) / max(w.std(), 1e-8)
        s = _crepe.predict({"audio": w[None, :].astype(np.float32)})["salience"].reshape(-1)
        k = int(np.argmax(s))
        if s[k] < CREPE_CONFIDENCE:
            continue
        lo, hi = max(0, k - 4), min(360, k + 5)
        cents[i] = float(np.sum(s[lo:hi] * bin_cents[lo:hi]) / np.sum(s[lo:hi]))
    return cents


def melody_leakage(reference_cents, instrumental_cents):
    """Share of voiced melody frames where the instrumental still carries the same note."""
    voiced = ~np.isnan(reference_cents)
    n = min(len(reference_cents), len(instrumental_cents))
    voiced = voiced[:n]
    same = np.abs(reference_cents[:n] - instrumental_cents[:n]) < SAME_NOTE_CENTS
    return float(np.sum(same & voiced) / max(1, np.sum(voiced)))


def log(*args):
    print(*args, flush=True)
    sys.stdout.flush()
