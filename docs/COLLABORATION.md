# Panduan Kolaborasi — PoC C6

Tujuan dokumen ini: tiga orang bisa kerja paralel tanpa saling tunggu, dan **struktur data tetap sama** sampai integrasi.

Backlog per orang: [Ikzaz](backlog/ikzaz.md) · [Takin](backlog/takin.md) · [Zildjian](backlog/zildjian.md)

---

## 1. Prinsip utama: kontrak ada di kode, bukan di dokumen

**Folder `poc-c6/Domain/` adalah satu-satunya sumber kebenaran untuk struktur data.**
PRD menjelaskan *kenapa*; kode di `Domain/` menentukan *bentuknya*. Kalau PRD dan kode beda, kode yang benar, lalu PRD diperbaiki.

```
poc-c6/Domain/
  Entities/      struct & enum data (TargetMIDINote, SongSegment, PreparedSong, TakeAttemptLog, ...)
  Repositories/  protocol yang diimplementasikan tiap orang
  Contracts/     ContractValidation (aturan serah-terima versi kode) + DomainFixtures (data contoh)
  UseCases/      logika per orang (lihat backlog)
```

Kenapa ini membuat struktur data tetap sama:
1. **Compiler yang menjaga.** Kalau ada yang mengubah field, kode orang lain langsung gagal build. Tidak ada yang bisa "diam-diam beda versi".
2. **Aturan serah-terima bisa dijalankan.** Contoh aturan "segmen harus menutup timeline tanpa celah" sudah ditulis sebagai `PreparedSong.validate()`, bukan cuma kalimat di PRD.
3. **Semua orang mulai dari data contoh yang sama** (`DomainFixtures`), jadi tidak ada yang menebak-nebak bentuk data dari orang lain.

---

## 2. Siapa memiliki apa

| Folder | Pemilik | Boleh diubah orang lain? |
|---|---|---|
| `Domain/Entities`, `Domain/Repositories`, `Domain/Contracts` | **Semua (kontrak)** | Hanya lewat proses §3 |
| `Domain/UseCases/<file>` | Sesuai backlog | Tanya pemilik dulu |
| `Data/Separation`, `Data/Audio` (analisis & transposisi), `Presentation/VocalRange`, `Presentation/Import` | Ikzaz | Tanya pemilik dulu |
| `Data/Capture`, `Data/Audio` (playback & route), `Shared/DSP`, `Presentation/Recording` | Takin | Tanya pemilik dulu |
| `App`, `Data/Composition`, `Fakes`, `Presentation/Export`, `Presentation/Debug`, `Presentation/Common`, `scripts`, `docs` | Zildjian | Tanya pemilik dulu |
| `poc-c6.xcodeproj` (build settings) | Zildjian | Minta lewat chat/PR |

Kabar baik: project ini memakai **folder yang tersinkron otomatis** di Xcode. Menambah file Swift baru **tidak mengubah file project**, jadi konflik merge di `.xcodeproj` hampir tidak akan terjadi selama build settings tidak diutak-atik.

---

## 3. Cara mengubah kontrak

Kontrak boleh berubah, asal semua orang tahu.

1. Buka PR kecil yang **hanya** berisi perubahan kontrak, beri label `contract-change`.
2. Di deskripsi PR tulis: apa yang berubah, kenapa, dan siapa yang terdampak.
3. Update `validate()` dan `DomainFixtures` kalau aturannya ikut berubah, dan tambahkan cek negatif di `scripts/contract-check/main.swift`.
4. Jalankan `./scripts/check-contracts.sh`, harus hijau.
5. Update PRD §6 di PR yang sama.
6. **Wajib di-approve ketiga orang** (diatur lewat CODEOWNERS).
7. Setelah merge, kabari di grup dan semua orang rebase hari itu juga.

| Jenis perubahan | Contoh | Dampak |
|---|---|---|
| Aman (menambah) | Field baru dengan nilai default, case enum baru yang belum dipakai | Kode lama tetap build |
| Berisiko (mengubah) | Ganti nama/tipe field, hapus field, ubah arti satuan waktu | Semua yang memakai harus ikut diubah; sepakati dulu di chat sebelum buka PR |

---

## 4. Serah-terima data antar orang

Setiap serah-terima punya satu fungsi pengecek. **Pengirim** memanggilnya sebelum menyerahkan, **penerima** memanggil `Contract.assertValid` saat menerima (crash di Debug kalau melanggar, diam di Release).

| Serah-terima | Pengecek |
|---|---|
| Ikzaz → Takin & Zildjian: `PreparedSong` | `preparedSong.validate()` |
| Takin → Zildjian: take LOLOS | `TakeLogContract.validatePassedTakes(takes, segments:, crossfade:)` |
| Zildjian (sebelum export): `CompingCompositionPlan` | `plan.validate()` |

```swift
// Contoh di sisi penerima
let song = try await prepareSong.execute(...)
Contract.assertValid(song.validate())
```

Cek kontrak di Mac tanpa simulator:
```bash
./scripts/check-contracts.sh
```

---

## 5. Kerja tanpa saling tunggu

| Kalau kamu butuh... | Pakai ini dulu |
|---|---|
| `PreparedSong` dari Ikzaz | `DomainFixtures.preparedSong` → lalu demo sintetis Zildjian (ZV-06) |
| Take LOLOS dari Takin | `DomainFixtures.compingPlan()` |
| Implementasi protocol orang lain | Fakes di `poc-c6/Fakes/` (ZV-03), dipilih lewat `AppContainer` |
| `YINPitchDetector` dari Takin | Tunggu TK-03 (dikerjakan paling awal) |

---

## 6. Alur Git

Repo: https://github.com/zildjianvitoo/poc-c6

**Setup sekali setelah clone** (mengaktifkan pengecek format commit):
```bash
git config core.hooksPath .githooks
```

- `main` diproteksi: tidak boleh push langsung, wajib lewat PR.
- Nama branch: `ikzaz/slice-segments`, `takin/capture-writer`, `zildjian/comping-audio`.
- Satu PR = satu task backlog (sebut ID-nya di judul, mis. `TK-04 Capture with AVAssetWriter`).
- Review minimal 1 orang; PR yang menyentuh `Domain/Entities|Repositories|Contracts` wajib 3 orang.
- Rebase ke `main` minimal sekali sehari.
- Jangan commit: lagu ber-copyright, file video hasil rekaman, `xcuserdata/`.

### Format commit: Conventional Commits (wajib)

```
<type>(<scope opsional>): <deskripsi singkat, huruf kecil, tanpa titik di akhir>
```

| Type | Dipakai untuk |
|---|---|
| `feat` | Fitur baru |
| `fix` | Perbaikan bug |
| `refactor` | Ubah struktur kode tanpa mengubah perilaku |
| `perf` | Peningkatan performa |
| `test` | Menambah/mengubah tes |
| `docs` | Dokumentasi saja |
| `style` | Format kode (spasi, urutan import), tanpa ubah logika |
| `build` | Build settings, project Xcode, dependency |
| `ci` | Workflow CI |
| `chore` | Pekerjaan lain-lain (gitignore, rapi-rapi) |
| `revert` | Membatalkan commit sebelumnya |

Scope yang disarankan (sesuai area): `domain`, `contract`, `separation`, `analysis`, `transpose`, `vocal-range`, `import`, `capture`, `playback`, `pitch`, `recording`, `evaluation`, `comping`, `export`, `app`, `debug`, `docs`.

Contoh:
```
feat(capture): write raw video with AVAssetWriter
fix(evaluation): count silent frames as misses
refactor(comping): split audio mix into its own type
docs: add takin backlog
feat(contract)!: rename audioDuration to duration
```

- Tambahkan `!` setelah type/scope untuk perubahan yang **merusak kompatibilitas** (terutama perubahan kontrak berisiko di §3).
- Judul PR juga pakai format yang sama, diikuti ID backlog di deskripsi.
- Hook `.githooks/commit-msg` menolak commit yang formatnya salah (commit merge dan revert bawaan git tetap diizinkan).

---

## 7. Konvensi kode

- **Semua tipe non-UI wajib `nonisolated`.** Project memakai default MainActor isolation; tanpa `nonisolated`, kode audio realtime akan ikut MainActor dan bisa crash/patah-patah (PRD §7.4).
- ViewModel: `@Observable`, tetap di MainActor (default).
- **Tidak ada angka ajaib.** Semua threshold & durasi diambil dari `PoCConfiguration`.
- Waktu: `TimeInterval` (detik) di timeline lagu, `CMTime` untuk capture clock & waktu file video. Jangan campur.
- Index segmen mulai dari 0; UI menampilkan `index + 1`.
- Satu tipe utama per file, nama file = nama tipe.
- `Domain/` hanya boleh import `Foundation` dan `CoreMedia` (dijaga oleh `check-contracts.sh`, karena script itu compile di macOS).
- Teks UI dalam bahasa Inggris.

---

## 8. Ritme tim

| Kapan | Apa |
|---|---|
| Setiap hari (async di grup) | Kemarin apa, hari ini apa, ada yang menghambat? |
| Hari pertama | Review & bekukan kontrak (M1) |
| Setiap akhir milestone | Integration day: gabungkan semua, jalankan di device, cek acceptance criteria PRD §10 |
| Kalau ada perubahan kontrak | Kabari di grup sebelum dan sesudah merge |

## 9. Definition of Done (per task)
- [ ] Build sukses, tidak ada warning baru
- [ ] `./scripts/check-contracts.sh` hijau (kalau menyentuh `Domain/`)
- [ ] Pengecek kontrak dipanggil di titik serah-terima (kalau ada)
- [ ] Diuji di iPhone fisik untuk fitur kamera/audio
- [ ] Kriteria "Selesai kalau" di backlog terpenuhi
- [ ] PR di-review & merged
