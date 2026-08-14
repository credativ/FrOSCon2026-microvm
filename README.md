# MicroVMs on Proxmox VE (FrOSCon 2026)

> **Presentation at FrOSCon 2026** · Bonn-Rhein-Sieg University of Applied Sciences  
> **Speaker:** Alexander Wirt (`alexander.wirt@credativ.de`), CTO [credativ GmbH](https://credativ.de), Debian Developer since 2002.

---

## 🎯 About This Project

Containers (LXC / Docker) start in milliseconds but share the host Linux kernel. Traditional KVM virtual machines (`q35` / `i440fx`) provide strong hardware-level isolation, but take 5 to 30 seconds to boot due to legacy BIOS/UEFI firmware, PCI bus scans, and generic distribution kernels.

This repository provides the companion materials for the talk **"MicroVMs auf Proxmox VE"**:
1. A **minimally invasive patch set** for Proxmox VE that enables the QEMU `microvm` machine type in the backend (`pve-qemu-server`) and web interface (`pve-manager`).
2. An **all-builtin slim kernel** configuration and build script that boots microVMs in **under 200 milliseconds**.
3. Complete **presentation slides** (HTML & PDF) and reproducible **benchmark results**.

---

## 📁 Repository Structure

```text
.
├── presentation/               # Presentation slides (Marp Markdown, HTML & PDF)
│   ├── slides.md               # Slide sources (German)
│   ├── froscon-microvm.html    # Standalone interactive HTML presentation
│   ├── froscon-microvm.pdf     # Print-ready PDF presentation
│   ├── build-slides.sh         # Build script to generate HTML & PDF
│   ├── assets/                 # Screenshots, logos, and fonts
│   └── charts/                 # Benchmark vector diagrams (SVG)
│
├── patches/                    # Proxmox VE source patches
│   ├── 0001-pve-qemu-server-microvm.patch   # Backend (Perl Machine.pm / config_to_command)
│   ├── 0002-pve-manager-gui-microvm.patch   # Web GUI (ExtJS dropdown & validation)
│   ├── 0003-pve-docs-microvm.patch          # Proxmox documentation
│   └── README.md                            # Detailed patch architecture & installation guide
│
├── kernel/                     # Minimal kernel for MicroVMs (<200ms boot time)
│   ├── build-slim-kernel.sh    # Standalone build script for Linux 6.1
│   ├── README.md               # Explanation of all-builtin architecture & drivers
│   └── output/                 # Destination folder for vmlinuz-slim (~7 MB bzImage)
│
└── benchmarks/                 # Empirical benchmark data & evaluations
    ├── README.md               # Methodology & detailed measurement data
    └── charts/                 # All benchmark diagrams (SVG)
```

---

## 🚀 Quickstart: Testing MicroVMs on Proxmox VE

### 1. Apply Proxmox VE Patches

The patches enable `machine: microvm`, suppress PCI bridge generation, and switch to VirtIO-MMIO transport:

```bash
# On your Proxmox VE host (e.g. PVE 8.x):
patch -p1 -d /usr/share/perl5/PVE < patches/0001-pve-qemu-server-microvm.patch
patch -p1 -d /usr/share/pve-manager < patches/0002-pve-manager-gui-microvm.patch

# Restart daemons:
systemctl restart pvedaemon pveproxy
```

### 2. Build & Deploy the Slim Kernel

```bash
cd kernel/
./build-slim-kernel.sh
scp output/vmlinuz-slim root@<pve-host>:/var/lib/vz/template/qemu/vmlinuz-slim
```

### 3. Configure & Start a MicroVM

Create a minimal VM configuration `/etc/pve/qemu-server/100.conf`:

```ini
name: microvm-demo
machine: microvm
cores: 2
memory: 512
kernel: /var/lib/vz/template/qemu/vmlinuz-slim
args: console=ttyS0 root=/dev/vda rw init=/init quiet
virtio0: local-lvm:vm-100-disk-0,size=4G
serial0: socket
vga: serial0
```

Start the VM and open the serial console:
```bash
qm start 100
qm terminal 100
```

---

## 📊 Benchmark Summary
*(Measurements performed using direct QEMU and Firecracker invocations on a Proxmox VE physical host)*

| VMM / Configuration | Boot Latency (P50) | VMM RSS Memory | Characteristics |
| :--- | :--- | :--- | :--- |
| **QEMU Full (`q35` + SeaBIOS)** | ~1,280 ms | ~141 MB | Full PC model, PCI root bridges |
| **QEMU MicroVM (`microvm` + Slim Kernel)** | **~180 ms** | **~137 MB** | VirtIO-MMIO, Direct Boot, KVM isolation |
| **AWS Firecracker (Direct Boot)** | ~125 ms | ~48 MB | Minimal VMM, ~3x higher instance density |

*Detailed measurements, setup details, and charts are available in [`benchmarks/`](benchmarks/).*

---

## 🛠️ Rebuilding Presentation Slides

The slide deck is built with [Marp](https://marp.app/):

```bash
cd presentation/
./build-slides.sh
```

---

## 📄 License & Trademarks

### License
All presentation slides, benchmark data, kernel configurations, build scripts, and documentation in this repository are licensed under the **[MIT License](LICENSE)**.

```text
Copyright (c) 2026 Alexander Wirt <alexander.wirt@credativ.de>
```

### Trademark & Branding Notice
- **credativ®** and the credativ logo are registered trademarks of [credativ GmbH](https://credativ.de).
- The credativ corporate branding, name, and logo assets located in `presentation/assets/credativ-*` are reserved and may not be used without prior written permission from credativ GmbH.
- **Proxmox®** is a registered trademark of Proxmox Server Solutions GmbH.
- All other trademarks and registered trademarks are the property of their respective owners.

---

## ✉️ Contact & Repository

* **Repository:** [https://github.com/credativ/FrOSCon2026-microvm](https://github.com/credativ/FrOSCon2026-microvm)
* **Author:** Alexander Wirt · `alexander.wirt@credativ.de` · [@formorer](https://github.com/formorer)
* **Company:** [credativ GmbH](https://credativ.de)
