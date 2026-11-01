# surya-gaming-kernel

Custom kernel untuk POCO X3 NFC (codename `surya`, Snapdragon 732G / SM7150), Android 11, dibangun otomatis lewat GitHub Actions.

## Fitur

- **Root**: [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) terintegrasi via metode kprobe (non-GKI legacy), karena kernel ini berbasis Linux 4.14.
- **Root hiding**: [SUSFS](https://gitlab.com/simonpunk/susfs4ksu) (lewat mirror aktif [ShirkNeko/susfs4ksu](https://github.com/ShirkNeko/susfs4ksu), branch `kernel-4.14`) — menyembunyikan jejak root dari pengecekan aplikasi (mis. Play Integrity, aplikasi banking), bukan untuk anti-cheat bypass game kompetitif.
- **Performa gaming ringan**: I/O scheduler Zen sebagai default, governor CPU SchedHorizon, dukungan kernel module.
- **Paket keluaran**: flashable ZIP berbasis AnyKernel3.

## Source

- Kernel: [`xiaomi-surya-devs/kernel_xiaomi_surya`](https://github.com/xiaomi-surya-devs/kernel_xiaomi_surya) branch `rethinking` (lineage msm-4.14 / ThunderBolt-Surya).
- Defconfig: `surya_defconfig`.
- Toolchain: AOSP Clang (prebuilt).

## Build

Build dilakukan otomatis lewat workflow `.github/workflows/build.yml`. Pergi ke tab **Actions** di repo ini → pilih workflow **Build Surya Gaming Kernel** → **Run workflow**. Hasil build (flashable ZIP) muncul sebagai artifact setelah selesai (sekitar 20-40 menit).

## Catatan

Repo ini **tidak** menyertakan driver pembaca/penulis memori proses lain (memory-cheat driver). Fokusnya murni performa dan root yang tersembunyi untuk kebutuhan wajar (kompatibilitas aplikasi), bukan kecurangan di game online.
