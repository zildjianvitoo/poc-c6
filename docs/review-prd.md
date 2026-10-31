# Review PRD — PoC C6 (Song Cover Recording & Auto-Comping)

Tanggal review: 31 Oktober 2026
Dokumen yang direview: `poc-c6/prd.md` (versi 202 baris)

---

## 1. Ringkasan

PRD ini **sudah kuat di sisi visi dan arsitektur**: alur 6 langkah jelas, entity domain terdefinisi, use case punya rumus, dan ada guardrail teknis (master clock, orientasi portrait, demo mode).

Tapi requirement-nya **belum cukup untuk langsung dieksekusi**. Ada 3 hal besar yang belum ada sama sekali di PRD padahal sudah dikonfirmasi sebagai kebutuhan:

1. **Final video = vokal user + instrumental** → PRD tidak menyebut instrumental sama sekali (sumbernya, cara mix, sinkronisasi timing).
2. **Vocal range test + transpose semitone** → tidak ada di PRD (flow, UI, entity, use case, dampak ke audio & export).
3. **Export sebagian kalau user berhenti di tengah** → perilakunya belum didefinisikan.

Selain itu ada beberapa **masalah teknis yang akan bikin hasil cut/sync meleset** kalau diimplementasikan persis seperti tertulis (detail di bagian 4).

| Kategori | Jumlah |
|---|---|
| Blocker (harus diputuskan sebelum coding) | 6 |
| Penting (harus ada di PRD, bisa diputuskan sambil jalan) | 12 |
| Minor / kerapian | 8 |

---

## 2. Keputusan yang sudah dikonfirmasi (perlu ditulis ke PRD)

| Topik | Keputusan |
|---|---|
| Audio final | Vokal user **+ musik tanpa vokal asli** (instrumental hasil pemisahan stem). Lagu full dengan vokal asli tetap boleh diputar di earphone sebagai panduan saat rekam |
| Referensi Phase 1 | **Lagu full-mix** (mis. MP3 hasil konversi), akurasi rendah diterima, **wajib ada disclaimer di UI** |
| Oktaf / range | Ada **vocal range test** di awal, referensi **di-transpose per semitone** sesuai range user |
| Berhenti di tengah | **Export sebagian** (hanya segmen yang sudah SUDAH) |
| Stem separation | **Dua jalur**: (A) demo track dengan stem dipisah offline di Mac lalu di-bundle; (B) spike CoreML on-device 3–5 hari untuk lagu import, fallback L−R + disclaimer |
| Target platform | **iOS 18.0, iPhone only, portrait** (project Xcode sudah saya sesuaikan, lihat bagian 8) |
| Roadmap akurasi | Didokumentasikan terpisah di [`roadmap-akurasi.md`](roadmap-akurasi.md) |

---

## 3. Jawaban: perlu pisahkan vokal & instrumental sendiri, atau langsung pakai model bagus?

**Rekomendasi: masukkan pemisahan stem (vocal/instrumental) ke scope PoC, tapi dengan dua jalur.**

Alasannya: karena final video butuh instrumental **tanpa vokal asli**, pemisahan stem bukan lagi "upgrade Phase 2" — ini syarat agar output PoC bisa dipakai. Dan cara native (tanpa ML) hasilnya jelek:

- **Center-channel cancellation (L−R)** bisa dilakukan native, tapi vokal sering masih tersisa, bass & kick ikut hilang (karena juga di tengah), dan hasilnya mono. Untuk demo, ini akan terdengar "murahan".
- Bonusnya: kalau sudah punya **vocal stem**, ekstraksi pitch (YIN) jadi jauh lebih akurat dibanding di full-mix. Jadi pemisahan stem adalah **satu pengungkit terbesar** untuk dua masalah sekaligus (instrumental + akurasi guide).

Usulan dua jalur:

| Jalur | Isi | Tujuan |
|---|---|---|
| **A — Demo dijamin bagus** | Lagu demo bawaan dengan stem yang **sudah dipisahkan offline di Mac** (mis. pakai Demucs via Python), lalu di-bundle: `mix`, `vocal`, `instrumental`, + guide notes hasil ekstraksi dari vocal stem | Presentasi PoC pasti jalan end-to-end dan terdengar bagus, tanpa risiko |
| **B — Spike on-device (timebox, mis. 3–5 hari)** | Coba model separasi CoreML di iPhone untuk lagu yang di-import user. Ukur: ukuran model, waktu proses untuk klip 60 detik, memori, kualitas | Membuktikan apakah fitur import lagu bebas bisa jalan di device. Kalau gagal → fallback L−R + disclaimer |

Yang **tidak** saya sarankan untuk PoC: API separasi cloud (butuh biaya, network, dan upload lagu ber-copyright ke pihak ketiga).

> Catatan copyright: lagu seperti *A Whole New World* (Disney) boleh dipakai untuk testing internal, tapi **jangan di-bundle ke repo/app sebagai demo track**. Untuk demo bawaan pakai lagu royalty-free atau lagu yang hak ciptanya kalian punya.

**Ini perlu keputusanmu** — lihat pertanyaan terbuka #1 di bagian 7.

---

## 4. Gap BLOCKER (harus diputuskan sebelum coding)

### B1. Instrumental & sinkronisasi timing tidak ada di PRD
- `CompingCompositionPlan` tidak punya `instrumentalURL`, gain vokal/instrumental, atau transposisi.
- `VideoCompositionRepositoryImpl` menyusun take **berurutan** dengan `insertionCursor`. Ini OK untuk acapella, tapi **salah kalau ada instrumental**: durasi tiap take dan jeda antar segmen tidak persis sama dengan lagu, sehingga vokal makin lama makin meleset dari beat.
- **Usulan:** setiap take ditempatkan di `segment.audioStartTime` pada timeline komposisi (bukan ditumpuk berurutan), dan segmen harus **menutup seluruh timeline tanpa celah** (batas segmen diletakkan di tengah jeda/silence). Instrumental jadi track terpisah dari detik 0.

### B2. Master clock di Section 5.1 tidak presisi
- Mengambil host time di callback `fileOutput(_:didStartRecordingTo:)` **tidak sama** dengan waktu frame pertama di file. Selisihnya bisa puluhan sampai ratusan ms → titik cut meleset, vokal off-beat terhadap instrumental.
- `AVAudioPlayer.play()` juga punya latency start yang tidak diketahui.
- **Usulan:**
  - Ganti `AVCaptureMovieFileOutput` → `AVCaptureVideoDataOutput` + `AVCaptureAudioDataOutput` + `AVAssetWriter`, dengan `startSession(atSourceTime: firstPTS)`. Waktu di file = `PTS − firstPTS`, pasti.
  - Reference audio diputar via `AVAudioPlayerNode` yang di-schedule di `AVAudioTime(hostTime:)` tertentu, sehingga waktu mulai bunyi diketahui.
  - Konversi antar clock pakai `captureSession.synchronizationClock` + `CMSyncConvertTime`.
  - Kompensasi `AVAudioSession.outputLatency` (waktu user *mendengar* referensi ≠ waktu dijadwalkan).

### B3. Konflik mikrofon: `AVCaptureSession` vs `AVAudioEngine`
- PRD memakai mic di dua tempat sekaligus (audio input capture session + input tap `AVAudioEngine`). `AVCaptureSession` secara default juga **mengubah konfigurasi audio session** milik app.
- **Usulan:** pitch detection diambil dari sample buffer `AVCaptureAudioDataOutput` (timestamp-nya sudah di clock yang sama dengan video — sekaligus menyelesaikan B2). `AVAudioEngine` hanya untuk playback. Set `captureSession.automaticallyConfiguresApplicationAudioSession = false`.

### B4. Konfigurasi audio session bertentangan dengan requirement earphone
- Opsi `.defaultToSpeaker` → kalau earphone tidak terpasang, referensi keluar dari speaker, masuk ke mic, merusak pitch detection dan ikut terekam.
- Opsi `.allowBluetooth` (HFP) → mic pindah ke AirPods dengan kualitas telepon (narrowband), pitch detection & kualitas vokal turun.
- Bluetooth A2DP punya latency ~150–250 ms dan angka `outputLatency` sering tidak akurat.
- **Usulan:** hapus `.defaultToSpeaker` dan `.allowBluetooth`, sisakan `.allowBluetoothA2DP`; paksa input ke **built-in mic** (`setPreferredInput`); **blok tombol Record** kalau output = speaker; rekomendasikan earphone kabel di Phase 1, Bluetooth boleh dengan peringatan (+ opsional kalibrasi latency manual). Pilih satu mode: `.videoRecording` (bukan "`.measurement` or `.videoRecording`").

### B5. Vocal range test + transpose semitone belum ada
Perlu ditambahkan: flow, UI, entity, use case, dan dampak ke audio. Detail usulan di bagian 6.2. Poin teknis penting:
- Kalau transpose, **instrumental di final video juga harus di-transpose dengan nilai yang sama**, kalau tidak vokal akan fals terhadap musik.
- Pecah transposisi jadi `oktaf × 12 + sisa semitone`. Geser oktaf cukup di target MIDI (audio tidak perlu diubah — cowok nyanyi 1 oktaf di bawah penyanyi cewek itu natural). Hanya **sisa semitone** yang butuh pitch-shift audio.
- Rekomendasi: render file referensi & instrumental yang sudah di-pitch-shift **di tahap prep** (offline, `AVAudioEngine` manual rendering + `AVAudioUnitTimePitch`), bukan realtime. Saat rekam & export tinggal pakai file hasil render.
- Batasi pergeseran audio maksimal ±5/6 semitone; di atas itu kualitas pitch-shift turun drastis.

### B6. Rumus akurasi belum terdefinisi tegas
`Accuracy = Count(isHit) / Total Active Frames` — "active frame" ambigu:
- Kalau yang dihitung hanya frame saat user bersuara (lolos noise gate), user yang **cuma nyanyi 1 nada dengan benar lalu diam** bisa dapat 100%.
- **Usulan definisi:** penyebut = frame di mana **ada target note aktif**; frame target aktif tapi user diam = miss; frame tanpa target (jeda di dalam segmen) tidak dihitung. Abaikan ~100 ms pertama tiap note (attack/onset). Tambahkan toleransi timing (mis. ±100 ms) karena latency.
- Definisikan juga **"missed note"** untuk highlight merah (mis. note dengan hit ratio < 50%).

---

## 5. Gap PENTING (harus masuk PRD)

1. **Export sebagian** — karena progres sekuensial, segmen yang lulus selalu prefix (1..N). Usulan: export segmen 1..N + instrumental dipotong di akhir segmen N dengan fade-out ±1 detik. Kalau 0 segmen lulus → tampilkan pesan, tidak ada export. Ubah teks mekanisme #4 di Section 1 supaya konsisten.
2. **Algoritma segmentasi bentrok** — split di gap > 0.8 s **dan** min 3 s / max 8 s. Belum jelas: segmen > 8 s tanpa gap 0.8 s dipotong di mana? Segmen < 3 s digabung ke mana? Lagu tanpa jeda sama sekali? Usulan: gabung segmen pendek ke tetangga dengan gap terkecil (selama ≤ 8 s); potong segmen panjang di gap internal terbesar atau batas note terdekat ke tengah; titik potong di tengah silence.
3. **Segmen tanpa note** (intro/interlude instrumental) — auto-SUDAH tanpa evaluasi, atau dibuang dari trim?
4. **Pre-roll / count-in** — saat rewind, referensi mulai persis di awal segmen tanpa konteks → user sulit masuk nada & tempo. Usulan: putar 1.5–2 detik audio sebelum segmen sebagai pre-roll (tidak masuk `videoTimeRange`).
5. **Timing countdown & transisi** — durasi `3..2..1` (3 detik?), apakah audio diam selama countdown, apakah ada jeda setelah SUDAH sebelum segmen berikutnya ("smoothly transitions" belum jelas). Evaluasi juga harus menunggu `outputLatency` + tail sedikit setelah akhir segmen.
6. **Crossfade 30 ms tidak bisa dibuat dengan 1 audio track** — `setVolumeRamp` di satu track hanya menghasilkan fade-out lalu fade-in (dip), bukan crossfade. Butuh 2 track audio bergantian (A/B) dengan overlap + handle 30 ms di tiap sisi take. Video tetap hard cut — tulis eksplisit bahwa itu diterima untuk PoC.
7. **Interupsi** — telepon masuk, Siri, app ke background, earphone dicabut, kamera dipakai app lain. Usulan: stop sesi + tawarkan export sebagian.
8. **Batas sesi** — retry tanpa batas → file raw membesar & HP panas. Tentukan maks durasi sesi (mis. 15 menit) dan cek storage sebelum mulai.
9. **Spesifikasi video/audio** — resolusi (1080×1920?), fps (30?), codec rekam (HEVC?) & export (H.264 + AAC 48 kHz untuk kompatibilitas sosmed), front camera **mirror atau tidak** di hasil akhir, level mix vokal vs instrumental.
10. **Spesifikasi Piano Roll** — range pitch lane (auto-fit ke note di segmen ± beberapa semitone?), kecepatan scroll, posisi playhead, look-ahead, label nama note. Tulis eksplisit: **overlay tidak ikut terekam** ke video.
11. **Acceptance criteria / success metrics PoC** — belum ada sama sekali. Contoh usulan:
    - Sinkron vokal vs instrumental di hasil akhir: drift < 40 ms
    - Akurasi titik cut: ±1 frame
    - Latency pitch trail di layar: < 100 ms
    - Waktu export: < 2× durasi klip
    - Demo track: alur import → rekam → retry → export jalan tanpa crash di device fisik
12. **Out of scope** — belum ada daftar. Usulan: lirik, edit manual note, multi-take selection, efek vokal (reverb/autotune), landscape, iPad, akun/backend, upload langsung ke sosmed.

---

## 6. Usulan tambahan isi PRD

### 6.1 Flow baru (update Section 3)
0. **Vocal Range Test** (sekali, disimpan, bisa diulang dari settings)
1. Import & Trim (+ **disclaimer akurasi Phase 1**)
2. Offline Extraction & Slicing (+ **stem separation** sesuai keputusan + **hitung & render transposisi**)
3. Preview guide (opsional: dengar hasil transpose, lihat jumlah segmen)
4. Rekam (cek earphone dulu) → loop evaluasi
5. Comping + mix instrumental → Export (penuh atau sebagian)

### 6.2 Vocal Range Test
- **UI:** user menyanyikan "aaa" dari nada paling rendah ke paling tinggi yang nyaman; tiap nada harus stabil ≥ 1 detik agar dihitung.
- **Entity:** `VocalRange { lowestMIDI, highestMIDI }`, `TranspositionPlan { octaveShift, semitoneShift }`.
- **Use case:** `DetectVocalRangeUseCase`, `ComputeTranspositionUseCase` — pilih shift −12…+12 yang meminimalkan jumlah note di luar range user, prioritaskan |shift audio| terkecil.

### 6.3 Disclaimer Phase 1 (usulan teks UI)
Di layar proses ekstraksi dan sebagai badge kecil di layar rekam:
> **Mode Eksperimental (Phase 1)** — Panduan nada diambil langsung dari lagu asli, jadi bisa kurang akurat terutama di bagian yang musiknya ramai. Akurasi akan ditingkatkan di versi berikutnya.

### 6.4 Perbaikan model domain
- `LivePitchFrame` mencampur hasil deteksi mentah (frekuensi) dengan hasil evaluasi (`centDeviation`, `isHit`) — padahal repository tidak tahu target note. Pisah jadi `PitchSample` (timestamp, frekuensi **optional** untuk unvoiced, RMS/confidence) dari repository, dan `PitchEvaluation` dari use case.
- `CaptureAndPlaybackRepository` mengekspos `AVCaptureSession` di layer Domain (framework bocor ke domain, sulit di-mock untuk test) dan memegang 3 tanggung jawab. Usulan pecah: `CaptureRepository`, `ReferencePlaybackRepository`, `PitchDetector`; preview layer kamera disediakan adapter di layer presentation/infrastructure.
- `pitchFrameStream` sebagai property `AsyncStream` hanya bisa punya **satu consumer** → lebih aman jadi fungsi yang mengembalikan stream baru.
- `CompingCompositionPlan` perlu tambahan: `instrumentalURL`, `segments` (untuk penempatan di timeline), `transposition`, `vocalGain`/`instrumentalGain`, `endTime` (untuk export sebagian).
- `ExtractGuideAndSliceUseCase` menulis "convert frekuensi → MIDI", padahal repository sudah mengembalikan `[TargetMIDINote]`. Tentukan konversi ada di mana (satu tempat saja).

### 6.5 Catatan tentang BasicPitch
PRD menyebut BasicPitch untuk "polyphonic full-song to MIDI". BasicPitch menghasilkan note **semua instrumen**, bukan melodi vokal saja — tetap butuh langkah memilih melodi. Untuk guide vokal, kombinasi **vocal stem + model pitch monofonik** lebih tepat. Detail di `roadmap-akurasi.md`.

---

## 7. Pertanyaan terbuka untukmu

> **Status: semua sudah dijawab** — (1) dua jalur, (2) Bluetooth boleh + peringatan, (3) mirror seperti selfie, (4) UI full Inggris, (5) Swift 5 mode + kode realtime `nonisolated`, (6) threshold bisa diatur dari Debug Settings (default rekomendasi). Semua sudah dimasukkan ke `prd.md` versi 2.

1. **Stem separation:** setuju dengan dua jalur (A: demo dengan stem yang dipisah offline; B: spike CoreML on-device dengan timebox)? Atau mau langsung commit ke on-device?
2. **Earphone Bluetooth:** boleh dipakai di Phase 1 (dengan risiko vokal agak telat terhadap musik), atau Phase 1 wajib earphone kabel?
3. **Mirror kamera depan:** hasil akhir dibiarkan seperti preview (mirror, seperti selfie) atau tidak di-mirror (seperti yang dilihat orang lain)?
4. **Bahasa UI:** status pakai `SUDAH`/`BELUM` tapi teks lain bahasa Inggris. Mau full Indonesia, full Inggris, atau campur?
5. **Swift language mode:** PRD menulis "Swift 6 / Swift 5.10" (ambigu). Project sekarang Swift 5 mode + *default MainActor isolation*. Rekomendasiku: **tetap Swift 5 mode** untuk PoC, tapi semua kode audio/DSP/realtime wajib `nonisolated` — kalau tidak, callback audio realtime akan ter-isolasi ke MainActor dan bisa crash/stutter. Setuju?
6. **Threshold:** 75%, ±50 cents, −40 dB — mau dibuat bisa diatur dari debug screen supaya bisa di-tuning saat user testing? (Rekomendasiku: ya.)

---

## 8. Minor / kerapian

1. Enum `case simpan = "SUDAH"`, `case buang = "BELUM"` — nama case dan raw value beda istilah. Usulan: `.passed` / `.failed` + label tampilan terpisah.
2. Section 6 meminta "production-ready tanpa TODO" — kontradiktif dengan status PoC dan extension point Phase 2. Usulan: "berjalan end-to-end, extension point Phase 2 ditandai `// MARK:`".
3. Section 6 meminta 4 file besar (`DomainLayer.swift`, dst.) — sulit direview & rawan konflik kalau dikerjakan tim. Usulan: folder per layer, satu tipe per file.
4. Section 6 belum mencakup: vocal range test, stem/instrumental, transposisi, disclaimer, export sebagian.
5. Project memakai `GENERATE_INFOPLIST_FILE = YES` → permission ditambahkan sebagai build setting `INFOPLIST_KEY_NSCameraUsageDescription` dll., bukan edit `Info.plist` manual. `Configuration.md` perlu menyesuaikan.
6. ~~`prd.md` ada di dalam folder target app dan ikut ter-copy ke app bundle.~~ **Sudah dipindah ke `docs/prd.md`.**
7. Preview kamera full-screen (layar iPhone ~19.5:9) dengan aspect-fill akan menampilkan crop berbeda dari video 9:16 yang terekam — perlu guide frame atau letterbox kalau mau WYSIWYG.
8. File yang di-import dari Apple Music (DRM) tidak bisa dibaca `AVAssetReader` — perlu pesan error yang jelas. Juga error untuk: klip < 15 detik, tidak ada vokal terdeteksi, format tidak didukung, izin kamera/mic ditolak.

---

## 9. Perubahan yang sudah saya lakukan

Sesuai keputusan "ikut PRD: iOS 18, iPhone", di `poc-c6.xcodeproj/project.xcproj`:

| Setting | Sebelum | Sesudah |
|---|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | 27.2 | **18.0** |
| `TARGETED_DEVICE_FAMILY` | 1,2 (iPhone + iPad) | **1 (iPhone)** |
| Orientasi iPhone | Portrait + Landscape kiri/kanan | **Portrait saja** |

Sudah dicek dengan `xcodebuild -showBuildSettings`. `SWIFT_VERSION` belum diubah (menunggu jawaban pertanyaan #5). `prd.md` belum saya ubah.
