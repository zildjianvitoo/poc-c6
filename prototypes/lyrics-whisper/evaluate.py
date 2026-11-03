"""Scores a WhisperKit transcription of a vocal stem against reference lyrics.

  python evaluate.py <whisperkit report.json> <reference lyrics.txt> <vocals.wav> [song seconds]

Prints the language, word error rate (WER) and how much of each word's time span the vocal stem
is actually voiced (a sanity check for word timestamps). Vocal fillers (oh/uh/ah) are ignored
and "biar pun"/"biarpun" count as the same word; segments starting after the song ends
(hallucinations on trailing silence) are dropped. Songs and lyrics stay in local-songs/.
"""
import json
import re
import sys

import numpy as np
import soundfile as sf

FILLERS = {"oh", "uh", "ho", "ooh", "ah"}


def words_of(text):
    text = text.lower().replace("♪", " ").replace("biar pun", "biarpun")
    text = re.sub(r"[-–]", " ", text)
    text = re.sub(r"[^\w\s]", " ", text)
    return [w for w in text.split() if w not in FILLERS]


def wer(reference, hypothesis):
    row = np.arange(len(hypothesis) + 1)
    for i, r in enumerate(reference, 1):
        previous, row[0] = row.copy(), i
        for j, h in enumerate(hypothesis, 1):
            row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (r != h))
    return row[-1] / len(reference)


def voiced_mask(path, frame=0.02, range_db=35):
    x, sr = sf.read(path, always_2d=True)
    x = x.mean(axis=1)
    hop = int(frame * sr)
    rms = np.array([np.sqrt(np.mean(x[i:i + hop] ** 2)) for i in range(0, len(x) - hop, hop)])
    db = 20 * np.log10(rms + 1e-9)
    return db > db.max() - range_db, frame, len(x) / sr


if __name__ == "__main__":
    report, lyrics, vocals = sys.argv[1:4]
    voiced, frame, duration = voiced_mask(vocals)
    duration = float(sys.argv[4]) if len(sys.argv) > 4 else duration
    data = json.load(open(report))
    segments = [s for s in data["segments"] if s["start"] < duration]
    words = [w for s in segments for w in (s.get("words") or []) if "♪" not in w["word"]]
    t = np.arange(len(voiced)) * frame
    inside = [voiced[(t >= w["start"]) & (t < w["end"])].mean() for w in words
              if np.any((t >= w["start"]) & (t < w["end"]))]
    reference = words_of(open(lyrics).read())
    hypothesis = words_of(" ".join(w["word"] for w in words))
    print(f"language {data['language']} | segments {len(segments)} "
          f"(dropped {len(data['segments']) - len(segments)} after the song) | words {len(hypothesis)} "
          f"vs reference {len(reference)} | WER {wer(reference, hypothesis):.0%} | "
          f"voiced share inside word spans {np.mean(inside):.2f}")
