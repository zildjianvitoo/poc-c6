"""Local singing transcription with estimated word timestamps, not forced alignment.
Executed in a separate process so the parent can enforce a timeout.
"""
import json
import math
import os
from pathlib import Path
import sys


def collect_words(segments, duration):
    words = []
    for segment in segments:
        if getattr(segment, 'no_speech_prob', 0) > 0.6:
            continue
        for word in segment.words or []:
            if word.start is None or word.end is None:
                continue
            start, end = float(word.start), float(word.end)
            probability = float(word.probability)
            if not all(map(math.isfinite, (start, end, probability))):
                continue
            start, end = max(0.0, start), min(duration, end)
            text = word.word.strip()
            if text and end > start and probability >= 0.3:
                words.append(dict(start=start, end=end, text=text, probability=probability))
    words.sort(key=lambda w: (w['start'], w['end']))
    return words


def transcribe(audio, output):
    from faster_whisper import WhisperModel
    import soundfile as sf
    model = WhisperModel(os.environ.get('COVER_LYRICS_MODEL', 'small'), device='cpu', compute_type='int8')
    language = os.environ.get('COVER_LYRICS_LANGUAGE') or None
    segments, info = model.transcribe(str(audio), language=language, beam_size=5,
                                     word_timestamps=True, condition_on_previous_text=False,
                                     vad_filter=False)
    # Iterate generator here: this is where inference actually runs.
    words = collect_words(segments, sf.info(str(audio)).duration)
    Path(output).write_text(json.dumps(dict(language=info.language, words=words), ensure_ascii=False))


if __name__ == '__main__':
    transcribe(Path(sys.argv[1]), Path(sys.argv[2]))
