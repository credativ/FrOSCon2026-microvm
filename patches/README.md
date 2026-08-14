# Proxmox VE Patch Architecture: QEMU `microvm` Machine Support

> **Goal:** Create a clean, minimally invasive patch for Proxmox VE (`pve-qemu-server`) to enable native `machine: microvm` execution.

---

## 1. Overview of Proxmox VE QEMU Integration

In Proxmox VE, VM startup commands are built dynamically by the `qemu-server` Perl package.
Key module paths in `qemu-server` source:
- `PVE/QemuServer.pm`: Central module containing `config_to_command` which translates VM configuration (`/etc/pve/qemu-server/<vmid>.conf`) into `qemu-system-x86_64` command-line arguments.
- `PVE/QemuServer/Machine.pm`: Handles machine type definitions (`pc`, `q35`, machine versions, pve-version tags).
- `PVE/QemuServer/Drive.pm`: Maps VM drive definitions (`scsiX`, `ideX`, `sataX`, `virtioX`) to QEMU `-drive` and `-device` parameters.
- `PVE/QemuServer/PCI.pm`: Manages PCI bridge topology (PCIe root ports for `q35`, PCI slots for `pc`).

---

## 2. Technical Challenge: Full PC vs. MicroVM

Standard Proxmox VE VMs rely heavily on standard PC/q35 hardware emulation:
1. **PCI Bus & PCIe Root Ports:** `q35` initializes multiple PCI bridges/root ports. `microvm` **has no PCI bus** (uses `virtio-mmio` instead).
2. **ACPI & BIOS/UEFI:** Standard VMs use Seabios/OVMF. `microvm` uses PVH direct kernel boot or `qboot`.
3. **Display & USB Devices:** Proxmox defaults to VGA/SPICE/VNC controllers + USB tablet/mouse. `microvm` disables VGA/USB by default.
4. **Drive & Net Transports:** Standard drives use PCI devices (`virtio-blk-pci`, `virtio-scsi-pci`). `microvm` requires MMIO devices (`virtio-blk-device`, `virtio-net-device`).

---

## 3. Minimally Invasive Patch Strategy

To ensure high maintainability and upstream potential for Proxmox VE, the patch follows these design principles:

### Principle 1: Zero Impact on standard `pc` / `q35` VMs
All `microvm`-specific code paths must be strictly gated behind a machine type check (`if ($machine_type =~ /^microvm/)`).

### Principle 2: Opt-in via standard VM Configuration
Users configure microVMs by setting in `/etc/pve/qemu-server/<vmid>.conf`:
```ini
machine: microvm
kernel: /var/lib/vz/template/qemu/vmlinuz-slim
initrd: /var/lib/vz/template/qemu/initramfs-slim.img
args: console=hvc0 root=/dev/vda rw
virtio0: local-lvm:vm-100-disk-0,size=4G
net0: virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0
```

### Principle 3: Targeted Patch Points

The patch set is split into two minimal parts:

#### Part 1: Backend Patch (`pve-qemu-server`) → [0001-pve-qemu-server-microvm.patch](file:///Users/formorer/Claude/Projects/Stammtisch%20Vortrag/patches/0001-pve-qemu-server-microvm.patch)
1. **Machine Type Validation (`PVE::QemuServer::Machine`):**
   - Add `microvm` to allowed machine types schema pattern.
   - Return `'microvm'` in `machine_base_type()`.
   - Register `microvm => {}` in `$supported_machine_flags`.
   - Update internal POD documentation for `machine_base_type`.

#### Part 2: Web GUI Patch (`pve-manager`) → [0002-pve-manager-gui-microvm.patch](file:///Users/formorer/Claude/Projects/Stammtisch%20Vortrag/patches/0002-pve-manager-gui-microvm.patch)
1. **Machine Selector (`QemuMachineSelector.js`):**
   - Adds `['microvm', 'microvm']` to combo items.
2. **Architecture Mapping (`Architecture.js`):**
   - Adds `'microvm'` to `allowedMachines.x86_64`.
3. **Machine Edit Form (`MachineEdit.js`):**
   - Adds `&& values.machine !== 'microvm'` check to prevent ExtJS from resetting `microvm` to `__default__`.

#### Part 3: Documentation Patch (`pve-docs`) → [0003-pve-docs-microvm.patch](file:///Users/formorer/Claude/Projects/Stammtisch%20Vortrag/patches/0003-pve-docs-microvm.patch)
1. **Reference Documentation (`qm.adoc`):**
   - Adds documentation entry for `microvm` machine type under *Virtual Machines (KVM)* -> *System Configuration*.
   - Explains `virtio-mmio`, direct kernel booting, use-cases (ephemeral / CI/CD) and limitations (no PCI, no live-migration).

---

## 4. Development Workflow & Testing Steps

1. **Backend Patch Deployment:**
   ```bash
   cp /usr/share/perl5/PVE/QemuServer.pm /usr/share/perl5/PVE/QemuServer.pm.bak
   patch -p1 -d /usr/share/perl5/PVE < patches/0001-pve-qemu-server-microvm.patch
   systemctl restart pvedaemon pveproxy
   ```
2. **Web GUI Patch Deployment:**
   ```bash
   patch -p1 -d /usr/share/pve-manager < patches/0002-pve-manager-gui-microvm.patch
   systemctl restart pveproxy
   ```
3. **Validation:**
   - **CLI / API:** Run `qm create 100 --machine microvm ...` and check `qm showcmd 100`.
   - **Web UI:** Open Proxmox VE Web UI in browser -> VM Hardware -> Edit Machine Type -> Verify `microvm` option appears.

