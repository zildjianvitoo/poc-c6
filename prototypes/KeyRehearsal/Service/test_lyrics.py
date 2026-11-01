import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace as NS
import unittest
from unittest.mock import patch

from lyrics import collect_words
from pipeline import make_guide, run


def word(text, start, end, probability=.9):
    return NS(word=text, start=start, end=end, probability=probability)


class LyricsTests(unittest.TestCase):
    def test_silence_low_confidence_and_invalid_words_filtered(self):
        segments = [NS(no_speech_prob=.9, words=[word('hallucination', 0, 1)]),
                    NS(no_speech_prob=.1, words=[word(' halo ', -.1, .6), word('no', 1, 2, .1),
                                               word('bad', float('nan'), 2), word('dunia', 2, 5)])]
        words = collect_words(segments, 3)
        self.assertEqual([w['text'] for w in words], ['halo', 'dunia'])
        self.assertEqual(words[0]['start'], 0)
        self.assertEqual(words[-1]['end'], 3)

    def test_no_phrase_split_inside_sung_word(self):
        p = make_guide([(0,1,60,.9),(2,3,64,.9)], 4, 60,
                       [dict(text='sayang', start=.5, end=2.5)], 'id')
        self.assertEqual(len(p['segments']), 1)
        self.assertEqual(p['segments'][0]['lyrics'], 'sayang')
        self.assertEqual(p['sourceOffset'], 60)
        self.assertEqual(p['words'][0]['start'], .5)

    def test_lyrics_assigned_once_in_timeline_order(self):
        words=[dict(text='dunia', start=2.1, end=2.8),dict(text='halo', start=.1,end=.8)]
        p=make_guide([(0,1,60,.9),(2,3,64,.9)],4,0,words,'id')
        self.assertEqual([s['lyrics'] for s in p['segments']], ['halo','dunia'])
        self.assertEqual(p['lyricsStatus'],'available')
        self.assertEqual(p['warnings'],[])

    def test_no_words_is_explicit_partial_result(self):
        p=make_guide([(0,1,60,.9)],2,0)
        self.assertEqual(p['lyricsStatus'],'unavailable')
        self.assertTrue(p['warnings'])
        self.assertTrue(p['notes'])

    def test_both_models_receive_separated_vocals(self):
        self.exercise_pipeline(False)

    def test_asr_timeout_keeps_note_guide(self):
        self.exercise_pipeline(True)

    def exercise_pipeline(self, timeout):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            calls=[]
            def external(command, **kwargs):
                calls.append(command)
                if command[0]=='ffmpeg':
                    (folder/'clip.wav').write_bytes(b'fixture')
                elif 'demucs' in command:
                    stems=folder/'stems'/'htdemucs'/'clip'
                    stems.mkdir(parents=True)
                    for name in ['vocals.wav','no_vocals.wav']:
                        (stems/name).write_bytes(b'fixture')
                else:
                    self.assertEqual(command[-2], str(folder/'vocals.wav'))
                    if timeout: raise subprocess.TimeoutExpired(command,600)
                    (folder/'lyrics.json').write_text(json.dumps(dict(language='id',words=[dict(start=0,end=1,text='halo',probability=.9)])))
            def predict(audio):
                self.assertEqual(audio,str(folder/'vocals.wav'))
                return None,NS(write=lambda path: Path(path).write_bytes(b'MIDI')),[(0,1,60,.9)]
            modules={'soundfile':NS(info=lambda path:NS(duration=2)),
                     'basic_pitch':NS(), 'basic_pitch.inference':NS(predict=predict)}
            with patch.dict('sys.modules',modules),patch('pipeline.subprocess.run',external),patch('traceback.print_exc'):
                result=run(folder,60,62,lambda message:None)
            self.assertEqual(result['sourceOffset'],60)
            self.assertEqual(result['lyricsStatus'],'unavailable' if timeout else 'available')
            self.assertEqual(len(calls),3)
            self.assertTrue(result['notes'])

if __name__=='__main__': unittest.main()
