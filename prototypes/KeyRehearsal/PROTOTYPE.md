# KeyRehearsal reference prototype

Standalone experimental app retained for testing the preparation flow: vocal-range test → manual audio import → Mac analysis → automatic/manual transposition → piano-roll and lyric preview.

Open `KeyRehearsal.xcodeproj` in this directory, not the root C6 project. Start the Mac service according to `README-PRE.md`. This prototype is separate from the C6 production architecture and shared Domain contracts. Its Indonesian UI, legacy models and local service are experimental reference code, not implementations of additional C6 backlog items.

Included: app source, local-service source, setup commands and tests. Excluded: audio/video, models, runtime environments, tokens, job data, screenshots, Xcode user settings and build output. The app requires your signing team; the service prints a fresh local token at startup.

Latest verification: iPhone build without signing passed after adding manual transposition. Existing preparation tests cover 16 service/segmentation cases; five shift-selection checks and legacy JSON decoding also passed. Physical-device sound quality still requires review. See README-PRE.md for setup.
