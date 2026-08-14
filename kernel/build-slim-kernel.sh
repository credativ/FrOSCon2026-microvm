#!/usr/bin/env bash
# =============================================================================
# build-slim-kernel.sh – Build an all-builtin minimal kernel for MicroVMs
# =============================================================================
# Builds a lightweight Linux kernel (~7 MB bzImage) without modules or initrd.
# All drivers required for QEMU microvm / Firecracker (VirtIO-MMIO, ext4, and
# serial console) are compiled directly into the kernel binary.
# =============================================================================
set -euo pipefail

KVER="${KVER:-6.1.102}"
ARCH="x86_64"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/output}"
WORK_DIR="${WORK_DIR:-/tmp/kernel-build}"
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"

echo "=========================================================="
echo " Building Slim MicroVM Kernel (Linux $KVER)"
echo " Output: $OUTPUT_DIR/vmlinuz-slim"
echo "=========================================================="

cd "$WORK_DIR"
SRC="linux-$KVER"
if [[ ! -d "$SRC" ]]; then
    if [[ ! -f "linux-$KVER.tar.xz" ]]; then
        echo "==> Downloading Linux kernel sources ($KVER)..."
        wget -q --show-progress "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz" || \
        curl -fSL -o "linux-$KVER.tar.xz" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz"
    fi
    echo "==> Extracting sources..."
    tar xf "linux-$KVER.tar.xz"
fi

cd "$SRC"

echo "==> Configuring kernel..."
if [[ -f "$SCRIPT_DIR/microvm-kernel.config" ]]; then
    echo "==> Using predefined config: microvm-kernel.config"
    cp -f "$SCRIPT_DIR/microvm-kernel.config" .config
else
    echo "==> Fetching Firecracker CI base configuration..."
    wget -qO .config "https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.10/$ARCH/vmlinux-$KVER.config" || \
        make defconfig

    echo "==> Enabling MicroVM & VirtIO-MMIO drivers (All-Builtin)..."
    ./scripts/config \
        --enable ACPI \
        --enable ACPI_AC \
        --enable ACPI_BUTTON \
        --enable X86_LOCAL_APIC \
        --enable X86_IO_APIC \
        --enable X86_MPPARSE \
        --enable PCI \
        --enable PCI_MMCONFIG \
        --enable VIRTIO \
        --enable VIRTIO_PCI \
        --enable VIRTIO_MMIO \
        --enable VIRTIO_BLK \
        --enable VIRTIO_NET \
        --enable EXT4_FS \
        --enable SERIAL_8250 \
        --enable SERIAL_8250_CONSOLE \
        --enable SERIAL_8250_PNP \
        --enable DEVTMPFS \
        --enable DEVTMPFS_MOUNT \
        --enable BINFMT_SCRIPT \
        --enable BINFMT_ELF \
        --enable PVH \
        --disable MODULES
fi

make olddefconfig

echo "==> Compiling bzImage with $JOBS cores..."
make -j"$JOBS" bzImage

cp -f arch/x86/boot/bzImage "$OUTPUT_DIR/vmlinuz-slim"
chmod 644 "$OUTPUT_DIR/vmlinuz-slim"

echo ""
echo "=========================================================="
echo " ✅ Slim kernel built successfully:"
echo "    $OUTPUT_DIR/vmlinuz-slim ($(du -h "$OUTPUT_DIR/vmlinuz-slim" | cut -f1))"
echo "=========================================================="
