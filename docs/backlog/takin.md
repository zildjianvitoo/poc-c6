# Backlog — Takin

**Peran:** Sesi rekaman (baris 2–3 board): Rekam → Nyanyi + playback → Pitch live + piano roll → Nilai segmen → Rewind / Lanjut.
**Output utama:** `RawMasterVideo.mov` + `passedTakesPrefix()` yang lolos `TakeLogContract.validatePassedTakes` (PRD §12.2).
**Branch kamu:** `takin` (jangan commit ke `main`, lihat `docs/COLLABORATION.md` §6).

Prioritas: **P0** = wajib untuk milestone, **P1** = penting, **P2** = kalau sempat.
Milestone: **M1** kontrak beku · **M2** end-to-end demo sintetis · **M3** end-to-end lagu demo asli · **M4** keputusan Track B.

> Bagianmu ada di **jalur kritis**. Hasil potongan video Zildjian bergantung pada akurasi waktu dari sini. Kerjakan TK-04 dan TK-05 paling awal, dan pair dengan Zildjian di bagian clock.

---

## Folder milikmu
```
poc-c6/Domain/UseCases/   TrackLivePitchUseCase, EvaluateSegmentUseCase
poc-c6/Data/Capture/      CaptureRepositoryImpl
poc-c6/Data/Audio/        ReferencePlaybackRepositoryImpl, AudioRouteMonitorImpl
poc-c6/Shared/DSP/        CrepePitchDetector (dipakai juga oleh Ikzaz)
poc-c6/Data/Session/      SessionTakeLogRepositoryImpl
poc-c6/Presentation/Recording/   RecordingPianoRollView, RecordingViewModel,
                                 CorrectionOverlayView, LoopStateController
```

## Kontrak
| Arah | Kontrak | Ke/dari |
|---|---|---|
| Kamu pakai | `PreparedSong` | dari Ikzaz (sementara pakai `DomainFixtures.preparedSong` / demo sintetis Zildjian) |
| Kamu hasilkan | URL video mentah + `[TakeAttemptLog]` LOLOS (waktu file, sudah dikompensasi latency, + handle 30 ms) | Zildjian |
| Kamu hasilkan | `CrepePitchDetector` | Ikzaz |
| Kamu implementasikan | `CaptureRepository`, `ReferencePlaybackRepository`, `AudioRouteMonitor`, `SessionTakeLogRepository` | — |

---

## Backlog

> **Status 1 Nov 2026 (takeover, branch `integration`):** ✅ = selesai di kode dan lolos cek Mac/simulator. 🟡 = kode selesai, menunggu tes di iPhone fisik.

| ID | Task | Prio | Milestone | Tergantung | Selesai kalau |
|---|---|---|---|---|---|
| TK-01 | Review & setujui kontrak Domain bersama tim | P0 | M1 | — | PR kontrak di-approve 3 orang |
| 🟡 TK-02 | Audio session (PRD §7.2): `.playAndRecord`, `.videoRecording`, hanya `.allowBluetoothA2DP`, input built-in mic | P0 | M2 | — | Mic tetap built-in walau pakai AirPods |
| ✅ TK-03 | `CrepePitchDetector` (CREPE tiny CoreML, hop 50 ms, noise gate, confidence ≥ 0.5) — **keputusan tim 1 Nov: CREPE menggantikan YIN**; API harus bisa dipakai Ikzaz untuk vocal range & fallback analisis | P0 | M2 | — | Nada sinus 220/440/880 Hz terdeteksi ±10 cents; lisensi marl/crepe + torchcrepe di `Licenses/` |
| 🟡 TK-04 | `CaptureRepositoryImpl`: front camera 1080×1920 @30, mirror, `AVCaptureVideoDataOutput` + `AVCaptureAudioDataOutput` → `AVAssetWriter` (HEVC), `startSession(atSourceTime: firstVideoPTS)`, `automaticallyConfiguresApplicationAudioSession = false` | P0 | M2 | TK-02 | File `.mov` terekam portrait + mirror di `SessionFiles.rawVideoURL` (dibersihkan otomatis tiap sesi baru); `fileTime(forCaptureTime:)` akurat |
| 🟡 TK-05 | `ReferencePlaybackRepositoryImpl`: `AVAudioPlayerNode`, `play(at:)` host time, konversi ke capture clock + `outputLatency` (PRD §7.1) | P0 | M2 | TK-04 | **Tes klik:** putar klik di earphone, rekam dengan mic didekatkan, selisih di file ≤ 1 frame |
| 🟡 TK-06 | Pitch live dari buffer audio capture → `pitchSamples()` (tanpa mic kedua), di queue sendiri, `nonisolated` | P0 | M2 | TK-03, TK-04 | Stream jalan selama rekaman tanpa drop frame video |
| ✅ TK-07 | `TrackLivePitchUseCase`: capture time → waktu lagu (anchor playback), bandingkan dengan target ter-transpose → `PitchEvaluation` | P0 | M2 | TK-06 | Toleransi ±50 cents & ±100 ms sesuai `PoCConfiguration` |
| ✅ TK-08 | `EvaluateSegmentUseCase`: rumus PRD §5.6 (frame target aktif, abaikan attack 100 ms, diam = miss), missed notes, `videoTimeRange` + handle | P0 | M2 | TK-07 | Unit test: diam sepanjang segmen = 0%; nyanyi tepat = ≥ 95%; segmen instrumental = lolos otomatis |
| ✅ TK-09 | `SessionTakeLogRepositoryImpl` (thread-safe) | P0 | M2 | — | `passedTakesPrefix()` lolos `TakeLogContract.validatePassedTakes` |
| ✅ TK-10 | `LoopStateController` state machine (PRD §6.1): pre-roll → nyanyi → evaluasi → lulus (lanjut tanpa berhenti) / gagal (hasil → countdown 3 s → pre-roll 2 s) | P0 | M2 | TK-05, TK-08 | Alur gagal → ulang → lulus jalan tanpa kamera berhenti |
| 🟡 TK-11 | `RecordingPianoRollView`: preview kamera + frame 9:16, piano roll tengah (`Canvas` + `TimelineView`, playhead 25%, range auto-fit), trail hijau/merah, top bar Segment x/y · Attempt n | P0 | M2 | TK-07 | 60 fps di device, overlay tidak ikut terekam |
| ✅ TK-12 | `CorrectionOverlayView`: badge PASSED / TRY AGAIN, nada salah berkedip merah, countdown | P0 | M2 | TK-10 | Sesuai PRD §5.6 |
| ✅ TK-13 | Cek earphone sebelum Record (`AudioRouteMonitor`): blok speaker, banner Bluetooth | P0 | M3 | TK-02 | Record nonaktif tanpa earphone |
| ✅ TK-14 | Tombol End Session + konfirmasi (*Export N of M* / *Keep recording* / *Discard*) | P0 | M3 | TK-10 | Memicu export sebagian ke Zildjian |
| 🟡 TK-15 | Interupsi (telepon, background, earphone dicabut, kamera dipakai app lain), batas sesi 15 menit, cek storage ≥ 1.5 GB | P1 | M3 | TK-14 | Sesi berhenti rapi + tawaran export sebagian |
| ✅ TK-16 | Kalibrasi latency manual (nilai di Debug Settings) dipakai di `latencyOffset` | P2 | M3 | TK-05 | Mengubah nilai menggeser titik potong |
| ✅ TK-17 | Rapikan dari audit 1 Nov (A-1…A-3): kembalikan `scripts/check-contracts.sh`, keluarkan `SegmentEvaluator`/`PracticeProgress`/kode MAE dari `Domain/UseCases`, ganti `Phrase`/`ReferenceNote`/`PracticeConfiguration` dengan `SongSegment`/`TargetMIDINote`/`PoCConfiguration` | P0 | M2 | — | `check-contracts.sh` versi `main` & `check-comping.sh` hijau |
| ✅ TK-18 | Sambungkan ke app: merge `main`, layar rekam di `RootView` case `.recording`, terima `PreparedSong` dari `AppFlow`, tulis ke `SessionFiles.rawVideoURL`, akhiri dengan `flow.sessionEnded(with: CompingCompositionPlan)`, izin lewat `PermissionGate` | P0 | M2 | TK-17 | Alur demo sintetis → rekam → layar Export jalan |
| ✅ TK-19 | Perbaiki scoring: satu acuan grid frame untuk evaluasi & penilaian, pakai `TrackLivePitchUseCase` (transposisi) | P0 | M2 | — | Penyanyi sempurna dengan note acak (bukan kelipatan 50 ms) ≥ 95%; `octaveShift = −1` dinilai benar |

## Catatan
- **Jangan pakai `Timer`/`Date()`/stopwatch** untuk waktu potong (PRD §7.1).
- Semua kode capture/DSP/playback wajib `nonisolated`; callback realtime tidak boleh memanggil kode MainActor (PRD §7.4).
- Panggil `Contract.assertValid(TakeLogContract.validatePassedTakes(...))` sebelum menyerahkan take ke comping.
