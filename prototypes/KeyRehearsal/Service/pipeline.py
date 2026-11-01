"""Real audio pipeline. Imports ML packages only when a job runs."""
from pathlib import Path
import subprocess
import sys
import json
import math


def make_guide(events, duration, offset, words=None, language=None, lyrics_warning=None):
    # Defensively clamp timestamps from ASR to the same cropped timeline as notes.
    clean_words = []
    for word in words or []:
        a, b = float(word['start']), float(word['end'])
        if not math.isfinite(a) or not math.isfinite(b):
            continue
        a, b = max(0.0, a), min(duration, b)
        if b > a and word['text'].strip():
            clean_words.append(dict(start=a, end=b, text=word['text'].strip(),
                                    probability=word.get('probability', 0.0)))
    clean_words.sort(key=lambda w: (w['start'], w['end']))
    notes = []
    for event in sorted(events, key=lambda e: float(e[0])):
        start, end, pitch, amplitude = map(float, event[:4])
        if not all(map(math.isfinite, (start, end, pitch, amplitude))):
            continue
        start, end = max(0, start), min(duration, end)
        if end - start < 0.1 or amplitude < 0.2 or not 36 <= pitch <= 96:
            continue
        notes.append(dict(id=len(notes), pitch=round(pitch), start=start, end=end))
    if not notes:
        raise ValueError('Nada vokal belum cukup jelas. Coba potongan dengan vokal solo.')
    # Cut only between nonoverlapping note groups, never through held notes.
    boundaries = [0.0]
    covered_end = notes[0]['end']
    for n in notes[1:]:
        gap = n['start'] - covered_end
        if gap >= 0 and (gap >= 0.45 or covered_end - boundaries[-1] >= 8):
            boundary = (covered_end + n['start']) / 2
            # A note gap is not a phrase boundary when a sung word crosses it.
            crosses_word = any(w['start'] < boundary < w['end'] for w in clean_words)
            if boundary - boundaries[-1] >= 1 and not crosses_word:
                boundaries.append(boundary)
        covered_end = max(covered_end, n['end'])
    boundaries.append(duration)
    segments = [dict(id=i, start=a, end=b, lyrics='')
                for i, (a, b) in enumerate(zip(boundaries, boundaries[1:]))]
    for segment in segments:
        phrase = [w for w in clean_words if segment['start'] <= (w['start'] + w['end']) / 2 < segment['end']]
        segment['lyrics'] = ' '.join(w['text'] for w in phrase)
        segment['lyricsEdited'] = False
    return dict(duration=duration, sourceOffset=offset, demo=False, notes=notes, segments=segments,
                words=clean_words, language=language,
                lyricsStatus='available' if clean_words else 'unavailable',
                warnings=[lyrics_warning] if lyrics_warning else ([] if clean_words else ['Lirik belum terbaca. Kamu bisa mengisinya manual.']))


def run(folder: Path, start: float, end: float, progress):
    progress('Menyiapkan audio…')
    clip = folder / 'clip.wav'
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', str(folder / 'source'),
                    '-ss', str(start), '-t', str(end-start), '-ar', '44100', '-ac', '2', str(clip)],
                   check=True, capture_output=True, timeout=180)
    import soundfile as sf
    info = sf.info(str(clip))
    if info.duration < 0.5:
        raise ValueError('Potongan audio kosong atau terlalu pendek.')
    progress('Memisahkan vokal dan pengiring…')
    subprocess.run([sys.executable, '-m', 'demucs', '--two-stems=vocals', '-n', 'htdemucs',
                    '-d', 'cpu', '-o', str(folder / 'stems'), str(clip)],
                   check=True, capture_output=True, timeout=1200)
    import shutil
    stems = folder / 'stems' / 'htdemucs' / 'clip'
    shutil.copyfile(stems / 'vocals.wav', folder / 'vocals.wav')
    shutil.copyfile(stems / 'no_vocals.wav', folder / 'backing.wav')
    progress('Membaca nada dengan Basic Pitch…')
    from basic_pitch.inference import predict
    _, midi, events = predict(str(folder / 'vocals.wav'))
    midi.write(str(folder / 'guide.mid'))
    progress('Membaca lirik dari vokal referensi…')
    words, language, warning = [], None, None
    try:
        subprocess.run([sys.executable, str(Path(__file__).with_name('lyrics.py')),
                        str(folder / 'vocals.wav'), str(folder / 'lyrics.json')],
                       check=True, capture_output=True, timeout=600)
        transcription = json.loads((folder / 'lyrics.json').read_text())
        words, language = transcription['words'], transcription['language']
    except (subprocess.SubprocessError, OSError, ValueError, KeyError):
        import traceback
        traceback.print_exc()
        warning = 'Lirik otomatis belum berhasil. Panduan nada tetap tersedia; isi lirik manual atau coba analisis ulang setelah memeriksa model speech-to-text di Mac.'
    progress('Menyelaraskan lirik, nada, dan frasa…')
    return make_guide(events, info.duration, start, words, language, warning)
