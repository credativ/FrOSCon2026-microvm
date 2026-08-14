---
marp: true
theme: credativ
paginate: true
size: 16:9
footer: "Alexander Wirt · FrOSCon 2026"
---

<!-- _class: title -->
<!-- _paginate: false -->
<!-- _footer: "" -->

# MicroVMs auf Proxmox VE

### QEMU on steroids 

FrOSCon 2026 · Hochschule Bonn-Rhein-Sieg · Alexander Wirt

---

## Wer bin ich?

**Alexander Wirt** – CTO und Open-Source-Entwickler

- Debian Developer seit 2002
- Arbeit bei [credativ](https://credativ.de) – Open-Source-Beratung und Linux-Infrastruktur
- Proxmox Trainer
- Schwerpunkte: Virtualisierung, Hochverfügbarkeit, Proxmox VE, Monitoring, Architektr

<div class="hint">
<strong>Wie es dazu kam:</strong> Mein Kollege Florian meinte beiläufig: „MicroVMs in Proxmox — das müsste man mal machen.“ Na ja, wie es halt so ist steh ich nun hier. Danke Florian!
</div>

---

<!-- _class: segue -->
<!-- _paginate: false -->

## Follow the white rabbit

<img src="assets/rabbit-hole.jpg" alt="Der Kaninchenbau" style="max-height:400px; width:auto; margin:0.3em auto 0.5em; box-shadow:0 6px 18px rgba(15,23,42,0.18)">

Ein Spruch, ein Nicken in die Runde, eine Zusage — und schon war ich im Kaninchenbau.

<p class="note">Illustration: KI-generiert</p>

---

## Agenda

- **Motivation:** Die Lücke zwischen Container (LXC) und voller VM
- **Isolationsspektrum & Kandidaten:** QEMU (q35), QEMU microVM, Firecracker
- **Sicherheit:** Angriffsfläche & Isolationsgrenze gegenüber Containern
- **Wie Proxmox VMs startet:** `pve-qemu-server`, `config_to_command` & PCI-Topologie
- **Technische Hürden in PVE:** PCI-Topologie, SeaBIOS & Legacy-Geräte
- **Der Patch:** Minimal-invasive Integration in Perl-Backend & ExtJS-GUI
- **Test-Pipeline:** `.deb`-Packaging & Nested-PVE-Testbed
- **Messungen & Benchmarks:** Startup-Zeiten, VMM-RSS, Dichte & Kernel-Einfluss
- **Live-Demo:** Erstellung im Web-UI & Konsole
- **Einordnung, Grenzen & Fazit:** Wann nimmt man was?

---

## Motivation: Container vs. VM

<div class="cols">
<div>

**Container (LXC / Docker)**
- Starten in Millisekunden
- Fast kein Speicher-Overhead
- **Einschränkung:** Geteilter Host-Kernel. Ein Kernel-Exploit kompromittiert direkt den Hypervisor-Host.

</div>
<div>

**KVM-VMs (Standard PC / Q35)**
- Harte Hardware-Isolation & eigener Kernel
- Eigene Sicherheitsgrenze
- **Einschränkung:** Träge Bootzeiten (5–30 s), höherer Memory-Footprint (~140 MB RSS).

</div>
</div>

<div class="hint">
<strong>Der Anwendungsfall:</strong> Kurzlebige Workloads (CI/CD Runner, FaaS, Multi-Tenant Build-Umgebungen). Container bieten zu wenig Isolation, Standard-VMs sind zu schwergewichtig. Höhere Sicherheitsanforderungen.
</div>

<!--
FaaS kurz erklären (erstes Vorkommen):
FaaS = Function as a Service. Man deployt nicht einen ganzen Server, sondern einzelne
Funktionen/Code-Schnipsel. Der Provider startet pro Aufruf blitzschnell eine isolierte
Umgebung, führt die Funktion aus und wirft sie danach wieder weg (Beispiel: AWS Lambda).
Genau dieser Lastfall – tausende winzige, kurzlebige, isolierte Starts – hat microVMs
überhaupt nötig gemacht.
-->


---

## Was eine MicroVM ausmacht

<div class="cols">
<div>

**Eigenschaften von MicroVMs:**
- **VM-Isolation:** Eigener Linux-Kernel via KVM (harte Sicherheitsgrenze)
- **Schneller Start:** Bootzeiten im Bereich weniger hundert Millisekunden
- **Reduzierte Angriffsfläche:** Keine Emulation von Floppy, IDE, VGA, PCI oder USB – historische Quellen von QEMU-Sicherheitslücken (CVEs)
- **Schlanker Footprint:** Nur minimale VirtIO-MMIO-Geräte am Systembus

</div>
<div>

```
[ Bare Metal / Server Hardware ]
             │
             ▼
[ KVM – Linux Hypervisor (/dev/kvm) ]
             │
     ┌───────┴───────┐
     ▼               ▼
[ Volle VM ]    [ MicroVM ]
  - PCI/ACPI      - VirtIO-MMIO
  - SeaBIOS       - Direct Kernel Boot
  - VGA / USB     - Serielle Konsole
```

</div>
</div>

<!--
virtio-mmio kurz erklären (erstes Vorkommen):
virtio = die paravirtualisierten Standard-Geräte (Disk, Netz, …); der Gast weiß, dass er
in einer VM läuft und redet über eine schlanke Schnittstelle direkt mit dem Host statt
echte Hardware zu emulieren. "Transport" ist der Weg, über den der Gast diese Geräte findet:
- virtio-PCI: Geräte hängen am (emulierten) PCI-Bus – Discovery/Enumeration wie bei echter
  PC-Hardware, dafür braucht es die ganze PCI/ACPI-Maschinerie.
- virtio-mmio: die Geräte liegen an festen, fest verdrahteten Speicheradressen (Memory-Mapped
  I/O) am Systembus – kein PCI-Bus nötig. Simpler und schneller beim Start, dafür statisch
  (feste Slots, kein Hotplug). Genau das nutzen microVM und Firecracker.
-->

---

## Isolationsspektrum: Ein KVM, drei VMMs

<div class="arch-stack">
<div class="arch-box hw">Hardware / Bare Metal</div>
<div class="arch-arrow">↓</div>
<div class="arch-box kvm">KVM – Linux Kernel Hypervisor</div>
<div class="arch-row">
  <div class="arch-box vmm">QEMU<br><small>full PC (q35)</small></div>
  <div class="arch-box vmm">QEMU<br><small>microVM (-M microvm)</small></div>
  <div class="arch-box fc">Firecracker<br><small>VMM (AWS)</small></div>
</div>
<div class="arch-arrow">↓</div>
<div class="arch-box guest">Linux Gast-Kernel</div>
<div class="arch-arrow">↓</div>
<div class="arch-box guest">Workload (Prozess / App / Container)</div>
</div>

<p class="note">KVM ist bei allen dreien identisch. Sie unterscheiden sich primär im VMM (Device-Modell, Firmware, Angriffsfläche).</p>

<!--
VMM kurz erklären (erstes Vorkommen):
VMM = Virtual Machine Monitor. Das Userspace-Programm (QEMU, Firecracker, cloud-hypervisor),
das auf KVM aufsetzt: es sagt KVM "bau mir eine VM mit so viel RAM und so vielen vCPUs",
baut dem Gast die virtuelle Hardware (Platte, Netz, serielle Konsole), lädt den Kernel und
behandelt die I/O. KVM ist der eigentliche Hypervisor im Kernel; der VMM ist das Programm
drumherum. Merksatz: KVM ist bei allen drei gleich – nur der VMM unterscheidet sich.
-->



---

## Die drei VMM-Kandidaten

| Eigenschaft | QEMU full (`q35`) | QEMU microVM (`-M microvm`) | Firecracker |
| :--- | :--- | :--- | :--- |
| **Sprache / LOC** | C · ~2.000.000 Zeilen | C · ~2.000.000 Zeilen | Rust · ~50.000 Zeilen |
| **Device-Transport** | VirtIO-PCI & emuliert | **VirtIO-MMIO** | **VirtIO-MMIO** |
| **Firmware / BIOS** | SeaBIOS / OVMF | **qboot / Direct Boot** | **Keins (Direct Boot)** |
| **Emulierte Geräte** | Dutzende (PCI, USB, IDE, VGA) | **Minimal (nur VirtIO)** | **Exakt 5 Geräte** |
| **Proxmox-Integration** | Standard (nativ) | **Über Patch machbar** | Neuer VMM / Fremdkörper |

<div class="hint">
<strong>Der Punkt für Proxmox:</strong> QEMU microVM steckt bereits im <code>qemu-system-x86_64</code>, das Proxmox ohnehin mitliefert. Es braucht keinen neuen VMM, nur die Freischaltung in Proxmox.
</div>

<!--
q35 einordnen – welche Maschinentypen Proxmox sonst kennt:
- pc  = i440fx, der historische Default (Intel 440FX, PCI, PIIX3)
- q35 = moderner Q35-Chipsatz mit echtem PCIe (heutige Empfehlung)
- versionsgepinnt: pc-i440fx-9.0 / pc-q35-9.0, dazu die +pveN-Revision
  (hält den Geräte-State über QEMU-Updates migrations-kompatibel)
- virt = für ARM/aarch64-Gäste
Unser Patch ergänzt genau einen weiteren Basistyp: microvm.
-->


---

## Firecracker: Das radikale VMM-Modell

<div class="cols">
<div>

### Firecracker-Design (AWS):
- **Strikter Minimalismus:** Nur 5 MMIO-Geräte, kein ACPI, kein PCI, kein BIOS.
- **REST-API-Steuerung:** Eigener Prozess pro VM, Konfiguration über HTTP/Socket.
- **Ziel:** Maximale Dichte & Sub-Sekunden-Starts für AWS Lambda und Fargate.

</div>
<div>

### Die Kehrseite in der Praxis:
- **Kein Storage-Layer:** Nur rohe Disk-Dateien (kein QCOW2, LVM, ZFS-Thin).
- **Keine Standard-Tools:** Kein QMP, kein Guest-Agent, kein Monitoring.
- **Hoher Integrationsaufwand:** Sämtliche Infrastruktur (Netzwerk, Storage, Lifecycle) muss drumherum selbst gebaut werden.

</div>
</div>

<div class="hint">
<strong>Praxiserfahrung:</strong> Mehrere Plattform-Teams, die mit Firecracker gestartet sind (z. B. Hocus<sup>1</sup>), wechselten für flexiblere Workloads zu QEMU/MicroVMs zurück – weil Firecrackers bewusste Reduktion außerhalb von FaaS schnell zur harten Grenze wird.
</div>

<div class="footnote">
<sup>1</sup> Hocus: <em>„Why We Migrated from Firecracker to QEMU“</em> – <a href="https://hocus.dev/blog/qemu-vs-firecracker/">https://hocus.dev/blog/qemu-vs-firecracker/</a>
</div>

---

## Sicherheitsgrenze: microVM vs. Container

<div class="cols">
<div>

### Die harte Grenze (KVM)
- Eigener Gast-Kernel statt geteiltem Host-Kernel (LXC): ein Kernel-Bug bleibt im Gast, nicht auf dem PVE-Host.
- Angriffsfläche = wenige VirtIO-MMIO-Geräte statt des vollen PC-Modells.
- Die bekannten QEMU-Escapes liefen fast alle über emulierte Legacy-Hardware (Floppy/„VENOM", USB, NICs) – genau die fehlt hier.

</div>
<div>

### Härtung – und was PVE (nicht) tut
- **QEMU kann mehr:** seccomp via `-sandbox on`; per AppArmor ließe sich der QEMU-Prozess je VM zusätzlich einsperren.
- Proxmox liefert dafür – anders als für LXC – **kein** AppArmor-Profil mit. Das bleibt Handarbeit und ist nicht Teil des Patches.
- Selbst mit AppArmor erreicht QEMU nicht ganz Firecrackers seccomp-Niveau (Jailer: ~50 Syscalls, Namespaces, cgroups, chroot + Rust).
- Unabhängig davon: die kleinere Gerätemenge der microVM verkleinert auch hier die Angriffsfläche.

</div>
</div>

<div class="hint">
Der Gewinn gegenüber dem Container: microVM tauscht „geteilter Kernel" gegen eine echte KVM-Grenze — genau darum setzen FaaS-Plattformen microVMs statt Container ein.
</div>

<!--
seccomp kurz erklären (erstes Vorkommen):
seccomp = "secure computing mode", ein Linux-Kernel-Feature. Man legt pro Prozess fest,
welche Syscalls er überhaupt an den Kernel stellen darf; alles andere wird geblockt
(Prozess bekommt Fehler oder wird gekillt). Damit schrumpft die Kernel-Angriffsfläche:
Selbst wenn der VMM übernommen wird, kann der Angreifer nur noch die wenigen erlaubten
Syscalls nutzen. QEMU schaltet das per `-sandbox on` ein; Firecracker bringt einen
sehr engen Filter (~50 erlaubte Syscalls) als Default mit.
-->

---

## Wie Proxmox eine VM startet

```
/etc/pve/qemu-server/<vmid>.conf
               │
               ▼
   [ PVE::QemuServer::config_to_command() ]
               │
               ├── PVE::QemuServer::Machine  (Maschinentyp & Versionierung)
               ├── PVE::QemuServer::PCI      (PCIe Root Ports & Bridges)
               ├── PVE::QemuServer::Drive    (Laufwerke: SCSI, VirtIO-PCI)
               └── PVE::QemuServer::Memory   (RAM & Hugepages)
               │
               ▼
   qemu-system-x86_64 -id 100 -name vm100 ...
```

Proxmox übersetzt die deklarative Konfigurationsdatei via Perl in den exakten QEMU-Kommandozeilenaufruf.

---

## Was Proxmox standardmäßig generiert: `qm showcmd`

```bash
/usr/bin/kvm -id 100 -name vm100 -chardev socket,id=qmp,path=/var/run/qemu-server/100.qmp ... \
  -nodefaults -boot menu=on,strict=on,splash=/usr/share/qemu-server/bootsplash.jpg \
  -vga none -nographic \
  -device pcie-root-port,id=pci.1,bus=pcie.0,slot=1 ... \
  -device pcie-root-port,id=pci.2,bus=pcie.0,slot=2 ... \
  -device virtio-balloon-pci,id=balloon0,bus=pci.1,addr=0x0 \
  -device virtio-scsi-pci,id=scsihw0,bus=pci.2,addr=0x0 \
  -drive file=/var/lib/vz/images/100/vm-100-disk-0.raw,if=none,id=drive-scsi0 ...
```

**Struktur des Aufrufs:**
1. Proxmox initialisiert standardmäßig eine vollständige **PCIe-Root-Port- und Bridge-Hierarchie**. (Bei q35)
2. Alle Geräte (`scsi`, `net`, `balloon`) werden als **PCI-Geräte (`-pci`)** an Slots gehängt.
3. Als Boot-Mechanismus wird das Standard-BIOS (SeaBIOS/OVMF) vorausgesetzt.

---

## Warum microvm in PVE nicht out-of-the-box läuft

<div class="cols">
<div>

### Was Proxmox generiert:
- PCIe Root Ports (`pcie.0`, `pci.1`, `pci.2`)
- PCI-basierte Geräte (`virtio-blk-pci`, `virtio-net-pci`)
- SeaBIOS / OVMF Bootloader
- ACPI-Power-States (`PIIX4_PM`, `ICH9-LPC`)
- Standard-Grafik & USB-Tablets

</div>
<div>

### Was `microvm` erfordert:
- **Kein PCI-Bus** (Geräte via `virtio-mmio`)
- **Kein SeaBIOS** (Direct Kernel Boot)
- **Kein klassisches ACPI** (PIIX4/ICH9), nur minimales `acpi-ged`
- **Reine serielle Konsole** (`ttyS0` / `hvc0`)
- Minimaler Device-Tree

</div>
</div>

<div class="hint">
<strong>Problem im Standard-PVE:</strong> Setzt man manuell <code>machine: microvm</code>, schlägt die Schema-Prüfung fehl, Proxmox baut PCI-Bridges für einen nicht existierenden PCI-Bus und QEMU bricht den Start mit Fehlermeldung ab.
</div>

---

## Der Patch: Architektur & Designentscheidungen

> **Voraussetzung:** Null Risiko für bestehende `pc`/`q35` VMs. Alle Änderungen greifen nur, wenn explizit `machine: microvm` konfiguriert ist.

<div class="cols">
<div>

#### Backend (`pve-qemu-server`)
- **`Machine.pm`:** Erlaubt `microvm` in der JSON-Schema-Validierung.
- **`Machine.pm`:** Führt `microvm` als eigenständigen Base-Type.
- **`config_to_command`:** Überspringt PCI-Bridge-Generierung und ACPI-Power-Flags bei MicroVMs.

</div>
<div>

#### Web-GUI (`pve-manager`)
- **`QemuMachineSelector.js`:** Fügt `microvm` zur Auswahlliste hinzu.
- **`Architecture.js`:** Erlaubt `microvm` in der x86_64-Architektur-Filterliste.
- **`MachineEdit.js`:** Verhindert Zurücksetzen auf Default.

</div>
</div>

---

## Der Backend-Patch im Detail: `PVE::QemuServer::Machine`

```diff
--- a/src/PVE/QemuServer/Machine.pm
+++ b/src/PVE/QemuServer/Machine.pm
@@ -58,7 +58,7 @@ my $machine_fmt = {
         description => "Specifies the QEMU machine type.",
         type => 'string',
         pattern =>
-            '(pc|pc(-i440fx)?-\d+(\.\d+)+(\+pve\d+)?(\.pxe)?|q35|pc-q35-\d+(\.\d+)+(\+pve\d+)?(\.pxe)?|virt(?:-\d+(\.\d+)+)?(\+pve\d+)?)',
+            '(pc|pc(-i440fx)?-\d+(\.\d+)+(\+pve\d+)?(\.pxe)?|q35|pc-q35-\d+(\.\d+)+(\+pve\d+)?(\.pxe)?|virt(?:-\d+(\.\d+)+)?(\+pve\d+)?|microvm)',
         maxLength => 40,
@@ -167,6 +167,7 @@ my sub machine_base_type {
     return 'q35' if $machine_type =~ m/q35/;
     return 'i440fx' if $machine_type =~ m/^pc/;
     return 'virt' if $machine_type =~ m/^virt/;
+    return 'microvm' if $machine_type =~ m/^microvm/;
```

**Ergebnis:** Proxmox akzeptiert `machine: microvm` in CLI, GUI und REST-API.

---

## MicroVM in der Proxmox Web-GUI

<div class="cols">
<div>

<img src="assets/pve-gui-machine-dropdown.png" alt="Proxmox Web UI Machine Dropdown" style="width:100%;border:1px solid #d8dde1;border-radius:8px;box-shadow:0 4px 12px rgba(0,0,0,0.08)">

</div>
<div>

### Auswirkungen in der Web-GUI:
- **VM-Erstellungs-Wizard:** Machine-Dropdown bietet neben *Default (i440fx)* und *q35* nun **`microvm`** an.
- **VM-Hardware-Optionen:** Machine-Typ bleibt nach dem Speichern dauerhaft in `/etc/pve/qemu-server/<vmid>.conf` erhalten.
- **ExtJS-Kategorieprüfung:** `allowedMachines.x86_64` validiert die Auswahl fehlerfrei.

</div>
</div>

---

## Test-Pipeline: `.deb`-Build & Nested-PVE

Sicheres Testen von PVE-Patches ohne Eingriff in Produktivknoten:

```
[ Git Repo: Patch-Dateien ]
          │
          ▼  (Ansible Orchestrator)
[ 1. Build-VM: Debian Trixie / Bookworm ]
  ├── quilt push (Patches anwenden)
  └── dpkg-buildpackage -b -uc -us → *.deb
          │
          ▼  (Scp / Fetch Artefakte)
[ 2. Nested Proxmox-Test-VM (VM 9002) ]
  ├── dpkg -i *.deb
  ├── systemctl restart pvedaemon pveproxy
  └── qm showcmd & Boot-Verifikation
```

<div class="hint">
<strong>Nested-KVM-Detail:</strong> Die äußere Test-VM muss mit <code>--cpu host</code> angelegt werden, damit Hardware-Virtualisierung (<code>/dev/kvm</code>) in der inneren Test-VM ankommt.
</div>

---

## Benchmarks: Methodik

### Messaufbau (in zwei Akten):
- **Viele Läufe, identische Hardware:** jede Variante mehrfach (10×) auf **demselben Host** gemessen, angegeben ist der **Median (P50)** – Ausreißer fallen so raus.
- **Identisches RootFS:** Alpine Linux 3.21 minirootfs (ext4), für alle Läufe gleich.
- **Readiness-Signal:** Zeit bis zum seriellen Marker `+++BENCHREADY+++` aus dem Gast-Init.
- **Es geht um Verhältnisse:** Absolutwerte hängen an der Host-Hardware — entscheidend ist das Verhältnis zwischen den Varianten.

---

## Erster Anlauf: microVM mit dem Distro-Kernel

<div class="cols">
<div>

- Maschinentyp **microvm**: kein PCI, kein SeaBIOS, virtio-mmio, Direkt-Boot – im Prinzip Firecracker-Bauart in Proxmox.
- Gebootet mit dem Kernel, den Proxmox/Debian ohnehin mitbringt.

</div>
<div>

<div class="hint">
Ergebnis: <strong>~3,25 s</strong> bis Userspace — und das, obwohl der Maschinentyp schon der schlanke <code>microvm</code> ist.
</div>

</div>
</div>

---

<!-- _class: segue -->

## Warum zur Hölle ist das immer noch so lahm?

Der ganze PC-Ballast ist weg – kein PCI, kein BIOS, minimale Geräte. Firecracker verspricht Millisekunden. Und wir stehen bei **über drei Sekunden**.

Der VMM kann es also nicht allein sein. Was bremst?

---

## Auflösung: der Kernel ist der Hebel

<div class="cols">
<div><img src="charts/kernel.svg" alt="Kernel-Hebel: Slim- vs. Distro-Kernel" style="width:100%"></div>
<div>

### Dieselbe microVM – nur der Gast-Kernel getauscht:
- **Distro-Kernel:** ~3.250 ms
- **Slim-Kernel:** ~484 ms → **×6,7 schneller**

Der Distro-Kernel probt beim Boot hunderte Treiber/Module, fährt udev und ein Initramfs hoch. Der Slim-Kernel hat alles fest eingebaut, kein Initramfs – er wacht „fertig" auf.

</div>
</div>

---

## Und der VMM? Gleicher Kernel, nur VMM variiert

<img src="charts/startup.svg" alt="Cold-Start: QEMU full vs. microVM vs. Firecracker" style="display:block;margin:0 auto;max-height:380px">

<div class="hint">
Mit dem schlanken Kernel liegen alle im selben Bereich (QEMU full 874 ms · microVM 484 ms · Firecracker 320 ms). Der VMM bringt nur noch ~Faktor 2–3 – der berühmte „10–100×"-Vorsprung war zum größten Teil der Kernel.
</div>

---

## Woher kommen Slim-Kernel & RootFS?

<div class="cols">
<div>

### Slim-Kernel
- Selbst gebaut (`build-slim-kernel.sh`): Firecracker-CI-Config + `CONFIG_ACPI=y`, **alles fest eingebaut**, keine Module, kein Initramfs.
- Ergebnis: ~7 MB `bzImage` → `/var/lib/vz/template/qemu/vmlinuz-slim`.
- Direkt-Boot mit `root=/dev/vda` – kein Initramfs nötig, weil die VirtIO-Treiber im Kernel sitzen.

</div>
<div>

### RootFS
- Alpine 3.21 minirootfs → ext4-Image, als `virtio0`-Disk eingehängt.
- Für alle Messungen identisch (fairer Vergleich).

</div>
</div>

<div class="hint">
Heute landen Kernel & RootFS noch manuell auf dem Node — First-Class-Image-Handling in PVE ist einer der offenen Punkte.
</div>

---

## Memory Footprint (VMM RSS) & Dichte

<div class="cols">
<div>

<img src="charts/memory.svg" alt="Memory Footprint RSS" style="width:100%">

- **QEMU Full (q35):** ~141 MB RSS
- **QEMU MicroVM:** ~137 MB RSS *(nur ~4 MB weniger)*
- **Firecracker:** ~48 MB RSS

</div>
<div>

<img src="charts/density.svg" alt="Density: VMs pro GB RAM" style="width:100%">

- **QEMU full / microvm:** ~7 VMs / GB RAM
- **Firecracker:** ~21 VMs / GB RAM (**~3× mehr**)
- **Grund:** QEMUs C-Codebasis belegt Grundspeicher; Dichte bleibt Firecrackers Domäne.

</div>
</div>

---

## Skalierung: Paralleler Start (1 bis 32 VMs)

<img src="charts/concurrent.svg" alt="Concurrent Boot Skalierung" style="display:block;margin:0 auto;max-height:420px">

<div class="hint">
Beide skalieren beim parallelen Start nahezu linear. Bei 32 gleichzeitigen VMs: Firecracker ≈1,3 s (41 ms/VM), QEMU microVM ≈1,9 s (60 ms/VM)
</div>

---

## Kostet die Proxmox-Schicht etwas?

Zwei getrennte Fragen: der **Gast-Boot** selbst und der **Vorlauf** davor.

<div class="cols">
<div>

### Der Gast-Boot ist identisch
- `qm start` und rohes `qemu-system-x86_64 -M microvm` erzeugen **dieselbe QEMU-Kommandozeile** (`qm showcmd`).
- Sobald QEMU läuft, ist die Boot-Phase also messbar die gleiche.

</div>
<div>

### Aber der Vorlauf ist nicht gratis
- API und GUI-Klick sind **asynchron**: sie legen einen Task an und kehren sofort zurück – die Arbeit macht ein `pvedaemon`-Worker.
- Davor: Task-Queue, Config-Parsing, Storage aktivieren, tap-/Hook-Setup. Das kostet Zeit **vor** dem QEMU-Exec.

</div>
</div>

---

## Live-Demo: MicroVM in Proxmox VE

<div class="cols">

<div>

### VM-Konfiguration (`/etc/pve/qemu-server/100.conf`):
```ini
name: microvm-demo
machine: microvm
cores: 2
memory: 512
args: -kernel /var/lib/vz/template/qemu/vmlinuz-slim
  -append "console=ttyS0 root=/dev/vda rw"
virtio0: local:100/vm-100-disk-0.raw,size=64M
serial0: socket
vga: serial0
```

<p class="note">Direct-Boot läuft über <code>args:</code> (<code>-kernel/-initrd/-append</code>) – noch kein First-Class-Key. Fat-Variante: zusätzlich <code>-initrd …/initrd-fat.img</code>.</p>

</div>
</div>

---

## QEMU-Aufruf: `qm showcmd` im Detail

```bash
# qm showcmd 101   (gepatchtes PVE · microvm-fat · Management-/QMP-Args gekürzt)
/usr/bin/kvm -id 101 -name microvm-fat -nodefaults -nographic \
  -machine 'smm=off,type=microvm+pve0' \
  -cpu kvm64,enforce,+kvm_pv_eoi,+kvm_pv_unhalt,+lahf_lm,+sep \
  -smp '2,sockets=1,cores=2,maxcpus=2' -m 512 \
  -chardev 'socket,id=serial0,path=/var/run/qemu-server/101.serial0,server=on,wait=off' \
  -device 'isa-serial,chardev=serial0' \
  -blockdev '{"driver":"throttle",…,"file":{"driver":"raw","file":{"driver":"file",
      "filename":"/var/lib/vz/images/101/vm-101-disk-0.raw"}},"node-name":"drive-virtio0"}' \
  -device 'virtio-blk-device,drive=drive-virtio0,id=virtio0,write-cache=on' \
  -device 'virtio-balloon-device,id=balloon0,free-page-reporting=on' \
  -kernel /var/lib/vz/template/qemu/vmlinuz-fat \
  -initrd /var/lib/vz/template/qemu/initrd-fat.img \
  -append 'console=ttyS0 root=/dev/vda rw init=/init quiet'
```

<div class="cols">
<div>

- **`microvm+pve0`:** Maschinentyp inkl. PVE-Revision, `smm=off`
- **`virtio-*-device`:** VirtIO-MMIO für Disk & Balloon (Netz optional)
- **`isa-serial`:** serielle Konsole über UNIX-Socket

</div>
<div>

- **Keine PCI-Bridges:** `pci.0` & Root-Ports übersprungen
- **Kein USB/VGA:** keine Controller initialisiert
- **Direct Boot:** `-kernel/-initrd/-append`, kein SeaBIOS/OVMF

</div>
</div>

<!--
smm=off kurz erklären:
SMM = System Management Mode, ein spezieller, hochprivilegierter x86-CPU-Modus (quasi
"Ring -2"), in den die CPU per SMI springt. Firmware (SeaBIOS/OVMF) nutzt SMM z. B. für
Power-Management und Secure-Boot-Enforcement. Eine microVM hat gar keine solche Firmware
und bootet den Kernel direkt – SMM wird also nicht gebraucht und abgeschaltet (smm=off).
Nebeneffekt: eine Komplexitäts-/Angriffsflächen-Quelle weniger. Bei q35 mit OVMF/Secure
Boot ist SMM dagegen an.
-->

---

## QEMU Device Tree

<div class="cols">
<div>

```text
main-system-bus (MicroVM)
├── isabus-bridge
│   └── isa.0
│       └── isa-serial (ttyS0)
├── virtio-mmio (24 statische MMIO-Slots)
│   ├── [Slot 21] ── virtio-net-device ("net0" via TAP)
│   ├── [Slot 22] ── virtio-blk-device ("virtio0")
│   └── [Slot 23] ── virtio-balloon-device ("balloon0")
├── acpi-ged (ACPI Generic Event Device)
└── ioapic (x2), kvmclock, fw_cfg_io
```

</div>
<div>

- **Kein PCI-Root-Bus (`pci.0`):** Null PCI-Initialisierungszyklen beim Start.
- **VirtIO-MMIO Transport:** Feste MMIO-Adressen am Systembus statt dynamischer PCI-BAR-Zuweisung.
- **Minimaler Footprint:** Keine USB-, IDE-, SATA-, VGA- oder Floppy-Controller im Baum.

</div>
</div>

---

## Einordnung: LXC, MicroVM, volle VM

Wann nimmt man in der Praxis was?

| Kriterium | LXC Container | QEMU microVM (PVE) | Volle KVM-VM (`q35`) |
| :--- | :--- | :--- | :--- |
| **Isolation** | Geteilter Kernel (weich) | **Eigener Kernel (hart)** | **Eigener Kernel (hart)** |
| **Bootzeit** | < 100 ms | **~480 ms** (Slim-Kernel) | 5 – 30 s |
| **VMM Memory RSS** | 0 MB | **~137 MB** | ~141 MB |
| **Live-Migration** | Nein | **Nein / eingeschränkt** | **Ja (vollständig)** |
| **Hardware-Passthrough**| Eingeschränkt | **Nein (kein PCI)** | **Ja (PCIe, GPU, USB)** |
| **Typischer Use-Case** | Webserver, Linux-Dienste | **CI/CD Runner, FaaS, Sandboxes** | Windows, Datenbanken, Cluster |

---

## Grenzen & Einschränkungen

- **Keine Live-Migration:** MicroVMs sind in QEMU nicht migrations-versioniert. Für Cluster-Updates ungeeignet.
- **Kein Hotplug:** Geräte, vCPUs und RAM können nicht im laufenden Betrieb hinzugefügt werden.
- **Kein Windows / Non-Linux:** MicroVMs erfordern Linux-Kernel mit VirtIO-MMIO-Treibern.
- **Kein PCI-Passthrough:** Für dedizierte GPUs oder PCIe-NICs bleibt nur `q35`.

<div class="hint">
<strong>Stärke bei kurzlebigen Workloads:</strong> MicroVMs passen zu Jobs, die nach Sekunden oder Minuten wieder verworfen werden (CI/CD, Tests, Microservices, Functions).
</div>

---

## Was noch fehlt: Offene Punkte & Leftovers

- **Direct Kernel Boot in `qm.conf`:** Parameter wie `kernel`, `initrd` und `append` werden bisher über `args:` durchgereicht. Es fehlen native First-Class-Config-Optionen in CLI, REST-API und GUI.
- **Storage- & Image-Handling:** Wie kommen schlanke Kernel und RootFS-Templates auf den Node? (Echtes MicroVM-Image-Format oder Storage-Plugin-Erweiterung).
- **Netzwerk via MMIO:** `virtio-net-device` sauber an Linux-Bridges/VLANs anbinden und im Erstellungs-Wizard konfigurierbar machen.
- **GUI-Bereinigung:** Nicht unterstützte Optionen (`scsihw`, `bios`, `vga`, `ide/sata`) bei `machine: microvm` in der Web-UI ausblenden statt mit unpassenden Defaults anzuzeigen.
- **Upstream-Diskussion:** Abstimmung mit dem Proxmox-Entwicklerteam auf `pve-devel` über die saubere Modellierung im PVE-Objektmodell.

---

## Zusammenfassung & Fazit

1. **Isolation & Performance:** MicroVMs verbinden KVM-Sicherheit mit Startzeiten im Bereich weniger hundert Millisekunden.
2. **Der Kernel ist der Hebel:** Ein generischer Distro-Kernel mit Modulen und Initramfs braucht Sekunden für Udev & Hardware-Scan. Erst ein schlanker All-Built-in-Kernel (~7 MB `bzImage`) ohne Initramfs bringt das Tempo.
3. **VirtIO-MMIO als Paradigma:** Verzicht auf PCI spart Initialisierungszeit und Speicher, limitiert aber auf statische, nicht-hotplugfähige Geräte.
4. **Machbarkeit bewiesen:** Ein minimal-invasiver Patch ohne Seiteneffekte für bestehende VMs beweist, dass Proxmox VE MicroVMs nativ unterstützen kann.

---

<!-- _class: closing -->
<!-- _paginate: false -->

# Vielen Dank! Fragen & Diskussion

### Alexander Wirt · `alexander.wirt@credativ.de`

<p style="margin-top: 1.2em"><strong>Code & Patches:</strong> <a href="https://github.com/credativ/FrOSCon2026-microvm">https://github.com/credativ/FrOSCon2026-microvm</a></p>
<p>FrOSCon 2026 · Hochschule Bonn-Rhein-Sieg</p>

---
