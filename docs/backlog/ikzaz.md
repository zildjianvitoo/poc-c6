# Backlog — Ikzaz

**Peran:** Persiapan lagu (baris 1 board): Impor → Pisah stem → Audio→MIDI → Guide + segmen → Transposisi.
**Output utama:** `PreparedSong` yang lolos `validate()` (PRD §12.2).

Prioritas: **P0** = wajib untuk milestone, **P1** = penting, **P2** = kalau sempat.
Milestone: **M1** kontrak beku · **M2** end-to-end demo sintetis · **M3** end-to-end lagu demo asli · **M4** keputusan Track B.

---

## Folder milikmu
```
poc-c6/Domain/UseCases/   PrepareSongUseCase, SliceSegmentsUseCase,
                          ComputeTranspositionUseCase, DetectVocalRangeUseCase
poc-c6/Data/Separation/   Bundled, CenterChannel, CoreML (flag)
poc-c6/Data/Audio/        BasicPitchAnalysisRepository, YINAnalysisRepository,
                          AudioTranspositionRepositoryImpl
poc-c6/Data/Session/      VocalRangeRepositoryImpl
poc-c6/Presentation/VocalRange/, poc-c6/Presentation/Import/
poc-c6/Resources/         stem lagu demo, guide, BasicPitch.mlpackage
```

## Kontrak
| Arah | Kontrak | Ke/dari |
|---|---|---|
| Kamu hasilkan | `PreparedSong` (segmen, earphone mix, instrumental, transposisi) | Takin, Zildjian |
| Kamu pakai | `YINPitchDetector` (shared DSP) | dari Takin (TK-03) |
| Kamu implementasikan | `StemSeparationRepository`, `AudioAnalysisRepository`, `AudioTranspositionRepository`, `VocalRangeRepository` | — |

---

## Backlog

| ID | Task | Prio | Milestone | Tergantung | Selesai kalau |
|---|---|---|---|---|---|
| IK-01 | Review & setujui kontrak Domain bersama tim | P0 | M1 | — | PR kontrak di-approve 3 orang |
| IK-02 | `SliceSegmentsUseCase` (PRD §5.3: gap > 0.8 s, gabung < 3 s, pecah > 8 s, segmen menutup timeline, segmen tanpa note) | P0 | M2 | IK-01 | Hasilnya lolos `PreparedSong.validate()` untuk minimal 5 kasus: normal, tanpa jeda, banyak jeda pendek, intro instrumental, frase > 8 s |
| IK-03 | `ComputeTranspositionUseCase` (PRD §5.4) | P0 | M2 | IK-01 | Cowok vs lagu cewek → `octaveShift = -1`; range pas → shift 0; `semitoneShift` selalu dalam −6…6 |
| IK-04 | Siapkan lagu demo Track A: pilih lagu royalty-free, pisah stem di Mac (mis. Demucs), trim 15–60 s, export `mix`, `vocal`, `instrumental` | P0 | M3 | — | 3 file di `Resources/`, durasi persis sama, terdengar bersih |
| IK-05 | `BundledStemsRepository` (Track A) | P0 | M3 | IK-04 | Mengembalikan `SeparatedStems` dari Resources |
| IK-06 | `BasicPitchAnalysisRepository`: cek lisensi + ekspor CoreML Basic Pitch, inference di vocal stem, reduksi monofonik (PRD §5.3) | P0 | M3 | IK-04 | Guide lagu demo cocok saat didengar/dibandingkan manual; hasil disimpan juga sebagai `demo_guide.json` |
| IK-07 | `YINAnalysisRepository` (fallback) | P1 | M3 | TK-03 | Dipakai otomatis kalau model gagal load atau 0 note |
| IK-08 | `AudioTranspositionRepositoryImpl` (AVAudioEngine manual rendering + `AVAudioUnitTimePitch`) | P0 | M3 | — | Render ±1…6 semitone, durasi output = input, `semitones == 0` tidak render ulang |
| IK-09 | `PrepareSongUseCase` (separate → extract → slice → transpose → render) + progress per langkah | P0 | M3 | IK-02, 03, 05, 06, 08 | Output lolos `validate()`; progress bisa ditampilkan di UI |
| IK-10 | Vocal Range Test: `DetectVocalRangeUseCase`, `VocalRangeRepositoryImpl` (`UserDefaults`), `VocalRangeTestView` | P0 | M3 | TK-03 | Nada terendah & tertinggi tersimpan; bisa tes ulang |
| IK-11 | `AudioImportView` + `PrepViewModel`: Files/Photos/Demo, waveform trimmer 15–60 s, disclaimer Phase 1, layar Ready (jumlah segmen, transposisi) | P0 | M3 | IK-09 | Alur impor → Ready jalan di device |
| IK-12 | Pesan error impor: DRM, format tidak didukung, tidak ada vokal terdeteksi (PRD §9) | P1 | M3 | IK-11 | Semua kasus §9 bagianmu punya pesan |
| IK-13 | `CenterChannelStemRepository` (fallback L−R / mid) + disclaimer tambahan | P1 | M3 | — | Lagu import tanpa CoreML tetap bisa diproses |
| IK-14 | **Spike Track B:** model separasi CoreML on-device (timebox 3–5 hari) | P1 | M4 | IK-05 | Laporan tertulis: model, ukuran, waktu proses 60 s, memori puncak, kualitas, go/no-go |
| IK-15 | `CoreMLStemSeparationRepository` di balik flag `useCoreMLSeparation` | P2 | M4 | IK-14 = go | Bisa diaktifkan dari Debug Settings |

## Catatan
- Note disimpan di **key asli**; transposisi hanya di `TranspositionPlan`.
- Instrumental dan earphone mix harus di-transpose dengan `semitoneShift` yang **sama**.
- Jangan commit lagu ber-copyright ke repo (mis. *A Whole New World*); pakai untuk tes lokal saja.
