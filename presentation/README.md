# FrOSCon 2026 Presentation Plan: MicroVMs auf Proxmox VE

> **Event:** FrOSCon 2026 (August 2026)  
> **Format:** 45-Minute Technical Talk + Q&A  
> **Target Audience:** System Administrators, DevOps Engineers, Cloud Infrastructure Engineers, Virtualization Enthusiasts.

---

## 1. Slide Deck Structure & Narrative

The talk will build upon the Stammtisch presentation (`slides.md`), expanding the technical depth and adding the Proxmox VE patch implementation and benchmark findings.

### Block 1: Introduction & MicroVM Fundamentals (10 min)
- The Isolation Spectrum: Bare Metal → Full VM → MicroVM → Container.
- Why MicroVMs? Speed, density, security boundary (KVM vs. Linux namespaces).
- Architectural Deep Dive: Firecracker (AWS) vs. QEMU microVM (`-M microvm`).
- Hardware modeling: PCI vs. MMIO (`virtio-mmio`), ACPI vs. PVH direct boot.

### Block 2: Proxmox VE & The MicroVM Challenge (10 min)
- How Proxmox VE (`pve-qemu-server`) currently starts VMs.
- Why `qemu-server` defaults to `q35`/`pc` and PCI bridge topology.
- What prevents microVMs from running out-of-the-box in PVE.

### Block 3: Minimally Invasive Patch Design (10 min)
- Architectural goals: Zero breaking changes to `pc`/`q35`, modular integration.
- Perl patch walkthrough in `PVE::QemuServer`:
  - Machine type registration (`microvm`).
  - PCI bridge suppression.
  - Virtio MMIO device translation (`virtio-blk-device`, `virtio-net-device`).
- Configuration file syntax: `/etc/pve/qemu-server/<vmid>.conf`.

### Block 4: Benchmarks & Empirical Results (10 min)
- Benchmark Setup & Tooling (Ansible + PVE host).
- Metric 1: Startup Latency (P50/P99 - Firecracker vs. QEMU microVM vs. QEMU q35 vs. PVE microVM).
- Metric 2: Memory Footprint & Density (VMs per 64 GB RAM).
- Metric 3: The Kernel Impact (Slim Kernel vs. Distro Cloud Kernels vs. Host Kernel).
- Metric 4: Concurrent Scaling (1 to 64+ VMs parallel boot).

### Block 5: Summary, Live Demo & Q&A (5 min)
- Demo: Deploying and starting a microVM via `qm start` on Proxmox VE.
- Status of upstream contribution / RFC to Proxmox community.
- Open Q&A.

---

## 2. Tooling & Export

- Source: `presentation/slides.md` (Marp Markdown)
- Custom Theme: `marp-theme.css`
- Build script: `build-slides.sh`
- Export targets: PDF, HTML, PPTX
