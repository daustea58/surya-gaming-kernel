#!/bin/bash
# Build script for surya-gaming-kernel (POCO X3 NFC / surya, Android 11)
# Runs inside GitHub Actions (ubuntu-latest). Safe to run locally on a Debian/Ubuntu
# x86_64 box too, as long as build deps from the workflow are installed.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/kbuild}"
KERNEL_REPO="https://github.com/xiaomi-surya-devs/kernel_xiaomi_surya.git"
KERNEL_BRANCH="rethinking"
KERNEL_DIR="$WORK_DIR/kernel"
DEFCONFIG="surya_defconfig"
TC_DIR="$WORK_DIR/clang"
AK3_DIR="$WORK_DIR/AnyKernel3"
SUSFS_DIR="$WORK_DIR/susfs"
OUT_DIR="$ROOT_DIR/out"
ZIP_NAME="surya-gaming-kernel-$(date +%Y%m%d).zip"

log()  { echo -e "\n\033[1;32m[*] $*\033[0m"; }
warn() { echo -e "\n\033[1;33m[!] $*\033[0m"; }
die()  { echo -e "\n\033[1;31m[x] $*\033[0m"; exit 1; }

mkdir -p "$WORK_DIR" "$OUT_DIR"

# ---------------------------------------------------------------------------
log "Step 1/8: Cloning kernel source ($KERNEL_BRANCH)"
if [ ! -d "$KERNEL_DIR/.git" ]; then
  git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR" \
    || die "Failed to clone kernel source"
fi
cd "$KERNEL_DIR"

# ---------------------------------------------------------------------------
log "Step 2/8: Cloning AOSP Clang toolchain"
if [ ! -d "$TC_DIR/bin" ]; then
  git clone --depth=1 -b 14 https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone "$TC_DIR" \
    || die "Failed to clone clang toolchain"
fi
export PATH="$TC_DIR/bin:$PATH"

log "Toolchain binaries available:"
ls "$TC_DIR/bin" | grep -iE 'gcc$|clang$' || true

AARCH64_PREFIX="$(find "$TC_DIR/bin" -maxdepth 1 -name '*-gcc' 2>/dev/null | grep -i 'aarch64' | head -1 | xargs -r basename | sed 's/gcc$//')"
ARM32_PREFIX="$(find "$TC_DIR/bin" -maxdepth 1 -name '*-gcc' 2>/dev/null | grep -iE 'arm-linux|androideabi|arm-eabi' | head -1 | xargs -r basename | sed 's/gcc$//')"

export CC=clang
export CLANG_TRIPLE="aarch64-linux-gnu-"
export CROSS_COMPILE="${AARCH64_PREFIX:-aarch64-linux-android-}"
export CROSS_COMPILE_ARM32="${ARM32_PREFIX:-arm-linux-androideabi-}"
export CROSS_COMPILE_COMPAT="$CROSS_COMPILE_ARM32"
log "CROSS_COMPILE=$CROSS_COMPILE  CROSS_COMPILE_ARM32/COMPAT=$CROSS_COMPILE_ARM32"

# ---------------------------------------------------------------------------
log "Step 3/8: Applying baseline gaming defconfig patch"
if [ -f "$ROOT_DIR/patches/task1_surya_defconfig.patch" ]; then
  patch -p1 --fuzz=3 --no-backup-if-mismatch < "$ROOT_DIR/patches/task1_surya_defconfig.patch" \
    && log "Baseline tuning patch applied" \
    || warn "Baseline tuning patch did not apply cleanly, continuing anyway"
else
  warn "No baseline patch found at patches/task1_surya_defconfig.patch, skipping"
fi

# ---------------------------------------------------------------------------
log "Step 4/8: Integrating KernelSU-Next (non-GKI / legacy kprobe method)"
curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy \
  || die "KernelSU-Next setup script failed"

KSU_DIR=""
for cand in "$KERNEL_DIR/KernelSU-Next" "$KERNEL_DIR/KernelSU"; do
  [ -d "$cand" ] && KSU_DIR="$cand" && break
done
[ -n "$KSU_DIR" ] || die "Could not locate KernelSU-Next source directory after setup"
log "KernelSU-Next source found at: $KSU_DIR"

# ---------------------------------------------------------------------------
log "Step 5/8: Integrating SUSFS (root hiding) for kernel 4.14"
SUSFS_OK=0
git clone --depth=1 -b kernel-4.14 https://github.com/ShirkNeko/susfs4ksu.git "$SUSFS_DIR" \
  || die "Failed to clone susfs4ksu"

cp "$SUSFS_DIR/kernel_patches/fs/susfs.c" "$KERNEL_DIR/fs/susfs.c" \
  || die "Failed to copy susfs.c"
mkdir -p "$KERNEL_DIR/include/linux"
cp "$SUSFS_DIR"/kernel_patches/include/linux/susfs*.h "$KERNEL_DIR/include/linux/" \
  || die "Failed to copy susfs headers"

cd "$KERNEL_DIR"
if patch -p1 --fuzz=5 --no-backup-if-mismatch < "$SUSFS_DIR/kernel_patches/50_add_susfs_in_kernel-4.14.patch"; then
  log "Core SUSFS kernel patch applied"
  if patch -p1 --fuzz=5 --no-backup-if-mismatch < "$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"; then
    log "SUSFS<->KernelSU-Next hook patch applied"
    SUSFS_OK=1
  else
    warn "SUSFS<->KernelSU-Next hook patch had rejects. Root will still work, but SUSFS hiding may be incomplete."
  fi
else
  warn "Core SUSFS patch had rejects against this kernel tree. Continuing WITHOUT SUSFS (root will still work via KernelSU-Next, but without hiding)."
fi

# ---------------------------------------------------------------------------
log "Step 6/8: Writing defconfig additions (KSU + SUSFS + gaming tuning)"
DEFCONFIG_PATH="$KERNEL_DIR/arch/arm64/configs/$DEFCONFIG"
[ -f "$DEFCONFIG_PATH" ] || die "defconfig not found at $DEFCONFIG_PATH"

{
  echo ""
  echo "# --- appended by surya-gaming-kernel build.sh ---"
  echo "CONFIG_KSU=y"
  if [ "$SUSFS_OK" = "1" ]; then
    echo "CONFIG_KSU_SUSFS=y"
    echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y"
    echo "CONFIG_KSU_SUSFS_SUS_PATH=y"
    echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y"
    echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y"
    echo "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n"
    echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y"
    echo "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y"
    echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y"
    echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y"
    echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y"
    echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y"
  fi
  echo "# gaming/perf extras"
  echo "CONFIG_CPU_FREQ_GOV_PERFORMANCE=y"
  echo "CONFIG_CPU_FREQ_GOV_POWERSAVE=y"
} >> "$DEFCONFIG_PATH"
log "defconfig updated at $DEFCONFIG_PATH"

# ---------------------------------------------------------------------------
log "Step 7/8: Building kernel"
cd "$KERNEL_DIR"
mkdir -p out
MAKE_ARGS=(
  O=out ARCH=arm64 CC=clang
  CLANG_TRIPLE="$CLANG_TRIPLE"
  CROSS_COMPILE="$CROSS_COMPILE"
  CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32"
  CROSS_COMPILE_COMPAT="$CROSS_COMPILE_COMPAT"
)
make "${MAKE_ARGS[@]}" "$DEFCONFIG" || die "defconfig generation failed"
make "${MAKE_ARGS[@]}" -j"$(nproc)" 2>&1 | tee "$OUT_DIR/build.log" || die "Kernel build failed, see build.log"

IMAGE="out/arch/arm64/boot/Image.gz"
DTB="out/arch/arm64/boot/dts/qcom/sdmmagpie.dtb"
DTBO="out/arch/arm64/boot/dtbo.img"
for f in "$IMAGE" "$DTB" "$DTBO"; do
  [ -f "$f" ] || die "Expected build output missing: $f (build likely failed partway, check build.log)"
done
log "Kernel compiled successfully"

# ---------------------------------------------------------------------------
log "Step 8/8: Packaging flashable ZIP (AnyKernel3)"
git clone -q --depth=1 -b surya https://github.com/ragy365/AnyKernel3.git "$AK3_DIR" \
  || die "Failed to clone AnyKernel3"

cp "$IMAGE" "$DTBO" "$AK3_DIR/"
cp "$DTB" "$AK3_DIR/dtb"

cd "$AK3_DIR"
zip -r9 "$OUT_DIR/$ZIP_NAME" . -x '.git*' 'README.md' '*placeholder' \
  || die "Zipping failed"

log "DONE. Flashable zip: $OUT_DIR/$ZIP_NAME"
if [ "$SUSFS_OK" != "1" ]; then
  warn "Reminder: SUSFS did not apply cleanly on this build, see warnings above. Root (KernelSU-Next) itself should still work."
fi
