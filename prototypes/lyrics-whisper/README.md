# Lyrics transcription spike (WhisperKit)

Phase A of the lyrics feature: transcribe the htdemucs vocal stem of a whole song with WhisperKit
(the CoreML Whisper runtime the app would use) and score it. Results:
`docs/test-reports/lyrics-whisper-spike-2026-11-03.md`.

Songs, reference lyrics, stems and models live in `local-songs/` and `~/lyrics-spike/`; never commit
them (copyrighted).

## Run
```bash
brew install whisperkit-cli
whisperkit-cli transcribe --model small_216MB --language id --word-timestamps \
  --download-model-path ~/lyrics-spike/models --download-tokenizer-path ~/lyrics-spike/models \
  --audio-path ~/lyrics-spike/abadi_vocals.wav --report --report-path ~/lyrics-spike/report
~/umx-spike/venv/bin/python evaluate.py ~/lyrics-spike/report/abadi_vocals.json \
  ~/lyrics-spike/abadi_lyrics.txt ~/lyrics-spike/abadi_vocals.wav
```
`--model` takes the WhisperKit name without the `openai_whisper-` prefix (`small_216MB`, `small`,
`large-v3-v20240930_547MB`). The first run downloads and compiles the model (minutes); later runs
are warm. The vocal stem comes from the app's `HTDemucsStemSeparationRepository` run on the whole song.
