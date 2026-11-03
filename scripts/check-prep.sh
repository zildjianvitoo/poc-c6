#!/bin/zsh
# Runs the song-preparation pipeline on the Mac: htdemucs (CoreML) and center-channel separation
# with the fallback, CREPE guide
# extraction, transposition rendering, trim-screen lyrics (LRC parsing, LRCLIB matching), and
# PrepareSongUseCase end to end.
# Run before opening a PR that touches poc-c6/Data/Separation or poc-c6/Data/Audio.
set -euo pipefail

ROOT="${0:A:h:h}"
WORK="$(mktemp -d)"

xcrun coremlcompiler compile "$ROOT/poc-c6/Resources/CrepeTiny.mlmodel" "$WORK" > /dev/null
xcrun coremlcompiler compile "$ROOT/poc-c6/Resources/HTDemucs.mlpackage" "$WORK" > /dev/null

xcrun swiftc -O -D DEBUG \
  $(find "$ROOT/poc-c6/Domain" -name '*.swift') \
  "$ROOT/poc-c6/Shared/DSP/CrepePitchDetector.swift" \
  "$ROOT/poc-c6/Shared/DSP/CrepeEstimate.swift" \
  "$ROOT/poc-c6/Shared/DSP/PitchMath.swift" \
  "$ROOT/poc-c6/Data/Audio/CrepeAnalysisRepository.swift" \
  "$ROOT/poc-c6/Data/Audio/AudioTranspositionRepositoryImpl.swift" \
  "$ROOT/poc-c6/Data/Separation/CenterChannelStemRepository.swift" \
  "$ROOT/poc-c6/Data/Separation/CoreMLSeparationError.swift" \
  "$ROOT/poc-c6/Data/Separation/HTDemucsStemSeparationRepository.swift" \
  "$ROOT/poc-c6/Data/Separation/SelectingStemSeparationRepository.swift" \
  "$ROOT/poc-c6/Shared/DSP/ShortTimeFourierTransform.swift" \
  "$ROOT/poc-c6/Shared/DSP/DemucsSpectrogram.swift" \
  "$ROOT/poc-c6/Presentation/Import/LyricsProviding.swift" \
  $(find "$ROOT/poc-c6/Data/Lyrics" -name '*.swift') \
  $(find "$ROOT/scripts/prep-checks" -name '*.swift') \
  -o "$WORK/prep-check"

"$WORK/prep-check" "$WORK/CrepeTiny.mlmodelc" "$WORK/HTDemucs.mlmodelc"
