# Backlog — Zildjian Vito

**Peran:** Comping & export (baris 4 board) + integrator: End Record → Pilih take LOLOS → Potong, tempatkan, mix, export → Preview.
**Output utama:** `FinalCoverVideo.mp4` (vokal user + instrumental) dan app yang menyatukan kerja semua orang.
**Branch kamu:** `zildjian` (jangan commit ke `main`, lihat `docs/COLLABORATION.md` §6).

Prioritas: **P0** = wajib untuk milestone, **P1** = penting, **P2** = kalau sempat.
Milestone: **M1** kontrak beku · **M2** end-to-end demo sintetis · **M3** end-to-end lagu demo asli · **M4** keputusan Track B.

---

## Folder milikmu
```
poc-c6/App/               poc_c6App, AppContainer, navigasi
poc-c6/Domain/UseCases/   AutoCompingVideoUseCase
poc-c6/Data/Composition/  VideoCompositionRepositoryImpl
poc-c6/Data/Separation/   SynthesizedDemoRepository
poc-c6/Fakes/             fake semua protocol
poc-c6/Presentation/Export/, poc-c6/Presentation/Debug/, poc-c6/Presentation/Common/ (izin & error)
poc-c6.xcodeproj          satu-satunya yang mengubah build settings
scripts/, docs/
```

## Kontrak
| Arah | Kontrak | Ke/dari |
|---|---|---|
| Kamu pakai | URL video mentah + take LOLOS | dari Takin (sementara `DomainFixtures.compingPlan()`) |
| Kamu pakai | `PreparedSong.instrumentalURL`, `segments` | dari Ikzaz |
| Kamu hasilkan | `AppContainer`, fakes, demo sintetis | semua orang |
| Kamu implementasikan | `VideoCompositionRepository` | — |

---

## Backlog

| ID | Task | Prio | Milestone | Tergantung | Selesai kalau |
|---|---|---|---|---|---|
| ZV-01 | ~~Setup git + push ke GitHub~~ (sudah) · sisa: proteksi `main`, CODEOWNERS untuk `poc-c6/Domain/` (wajib review 3 orang), PR template, invite Ikzaz & Takin | P0 | M1 | — | Semua anggota bisa clone, aktifkan hook commit, buat branch, buka PR |
| ZV-02 | Pimpin review kontrak Domain (sudah ada draft di `poc-c6/Domain/`) sampai di-approve semua | P0 | M1 | — | PR kontrak merged, `scripts/check-contracts.sh` hijau |
| ZV-03 | Fakes untuk semua protocol di `Fakes/` (pakai `DomainFixtures`) | P0 | M1 | ZV-02 | Ikzaz & Takin bisa jalankan bagiannya tanpa menunggu yang lain |
| ZV-04 | `AppContainer` (dependency wiring, bisa pilih real/fake) + navigasi utama: Vocal Range → Import → Ready → Recording → Export | P0 | M1 | ZV-03 | App jalan end-to-end dengan fakes |
| ZV-05 | Tambah unit test target via Xcode + pindahkan pengecekan kontrak ke test | P1 | M1 | ZV-01 | `⌘U` menjalankan tes kontrak |
| ZV-06 | `SynthesizedDemoRepository`: melodi sinus (vokal), chord pad (instrumental), mix = jumlah keduanya, guide sudah diketahui pasti | P0 | M2 | ZV-02 | `PreparedSong` sintetis lolos `validate()` dan bisa diputar |
| ZV-07 | `VideoCompositionRepositoryImpl` bagian video: tiap take ditempatkan di `segment.audioStartTime`, hard cut, render 1080×1920, `preferredTransform` | P0 | M2 | ZV-02 | Pakai video uji: urutan & posisi potongan benar |
| ZV-08 | Audio vokal: 2 track bergantian (A/B) + handle 30 ms + `setVolumeRamp` crossfade | P0 | M2 | ZV-07 | Tidak ada klik di batas segmen |
| ZV-09 | Mix instrumental (track sendiri dari t = 0, gain 1.0/0.8), fade-out 1 s untuk export sebagian | P0 | M2 | ZV-07 | Vokal sinkron dengan instrumental, drift < 40 ms |
| ZV-10 | Export `.mp4` H.264 + AAC 48 kHz dengan progress | P0 | M2 | ZV-09 | Waktu export < 2× durasi klip |
| ZV-11 | `AutoCompingVideoUseCase`: buat `CompingCompositionPlan` dari take LOLOS, `Contract.assertValid` sebelum export | P0 | M2 | ZV-07 | Export penuh & sebagian (N = 1…M−1) jalan; N = 0 → pesan "Nothing to export yet" |
| ZV-12 | **Pair dengan Takin** untuk verifikasi clock/titik potong (tes klik TK-05) | P0 | M2 | TK-05 | Akurasi potong ±1 frame terbukti di device |
| ZV-13 | `ExportPreviewView` + `CompingViewModel`: progress, `VideoPlayer`, `ShareLink`, Save to Photos | P0 | M2 | ZV-10 | Video bisa diputar, dibagikan, disimpan |
| ZV-14 | Layar izin kamera/mic/Photos + error handling umum (PRD §9), `INFOPLIST_KEY_*` usage descriptions | P0 | M3 | ZV-04 | Semua izin ditolak → layar penjelasan + tombol Settings |
| ZV-15 | `DebugSettingsView` untuk `PoCConfiguration` (disimpan lokal) | P1 | M3 | ZV-04 | Ubah threshold tanpa build ulang |
| ZV-16 | Hapus file sementara saat mulai sesi baru | P1 | M3 | ZV-11 | Storage tidak menumpuk |
| ZV-17 | Integrasi M3: ganti fakes dengan implementasi asli, uji acceptance criteria PRD §10 di device | P0 | M3 | semua P0 | Checklist §10 terisi |
| ZV-18 | Jaga PRD & `docs/` tetap sinkron dengan kontrak | P1 | terus | — | Setiap PR kontrak juga update PRD §6 |
