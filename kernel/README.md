# MicroVM Slim Kernel

This directory contains the configuration and build automation for the **All-Builtin Minimal Kernel**, optimized for QEMU `microvm` and AWS Firecracker.

---

## 1. Why a Custom Slim Kernel?

Standard Linux distribution kernels (e.g. Debian/Ubuntu default kernels) are built for broad hardware compatibility:
- **Size:** 40 – 70 MB (`vmlinuz` + initramfs).
- **Modules:** Thousands of drivers compiled as dynamic `.ko` modules inside the initramfs.
- **Boot overhead:** Udev device scans, dynamic module loading, and firmware probing add **1 to 5 seconds** of latency.

A **MicroVM Slim Kernel** takes the opposite approach:
- **Size:** ~7 MB `bzImage`.
- **No dynamic modules (`CONFIG_MODULES=n`):** All necessary drivers are built directly into the kernel.
- **No initramfs:** The kernel directly mounts the root filesystem (`root=/dev/vda`) at boot.
- **Boot time:** **< 50 milliseconds** from launch to init execution.

---

## 2. Included Drivers & Kernel Configuration

The configuration builds upon the minimal Firecracker CI baseline and adds the essential drivers required for QEMU MicroVM:

| Config Option | Purpose |
| :--- | :--- |
| `CONFIG_VIRTIO=y` & `CONFIG_VIRTIO_MMIO=y` | VirtIO-MMIO transport for disk and network (no PCI required) |
| `CONFIG_VIRTIO_BLK=y` | VirtIO Block device driver (virtual disk `/dev/vda`) |
| `CONFIG_VIRTIO_NET=y` | VirtIO Network device driver (`eth0`) |
| `CONFIG_EXT4_FS=y` | Built-in Ext4 filesystem support |
| `CONFIG_SERIAL_8250=y` & `CONFIG_SERIAL_8250_CONSOLE=y` | Serial interface (`ttyS0`) for headless streaming and logging |
| `CONFIG_DEVTMPFS=y` & `CONFIG_DEVTMPFS_MOUNT=y` | Automatic mounting of `/dev` at boot |
| `CONFIG_ACPI=y` | Minimal ACPI Generic Event Device (`acpi-ged`) for graceful shutdown/reboot |
| `CONFIG_PVH=y` | PVH direct boot support (fastest ELF kernel entry point) |
| `CONFIG_MODULES=n` | Disables module subsystem for minimal footprint and maximum security |

---

## 3. Building the Kernel

### Prerequisites (Debian / Ubuntu):
```bash
sudo apt-get update
sudo apt-get install -y build-essential flex bison libelf-dev libssl-dev bc xz-utils wget curl
```

### Run the build:
```bash
chmod +x build-slim-kernel.sh
./build-slim-kernel.sh
```

The compiled kernel image will be placed in `./output/vmlinuz-slim`.

---

## 4. Deploying to Proxmox VE

Copy the compiled `vmlinuz-slim` image to your Proxmox host:

```bash
scp output/vmlinuz-slim root@<pve-host>:/var/lib/vz/template/qemu/vmlinuz-slim
```

In your VM configuration (`/etc/pve/qemu-server/<vmid>.conf`):
```ini
machine: microvm
kernel: /var/lib/vz/template/qemu/vmlinuz-slim
args: console=ttyS0 root=/dev/vda rw init=/init quiet
```
