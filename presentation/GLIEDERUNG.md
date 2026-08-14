# Gliederung – FrOSCon-Vortrag (Samstag)

**MicroVMs auf Proxmox VE — Firecracker, QEMU microVM und der Weg in `qemu-server`**

> Basis: der Stammtisch-Vortrag [`../../slides.md`](../../slides.md) (30 min, gemischtes
> Publikum). Diese Fassung zieht den Fokus stärker auf **Proxmox VE**: Wie Proxmox
> VMs startet, warum microVMs nicht out-of-the-box laufen, der minimal-invasive
> Patch, saubere `.deb`-Verifikation, und Benchmarks inkl. der PVE-Variante.
>
> **Annahmen (anpassbar):** ~45 min Vortrag + Q&A, Publikum technischer als beim
> Stammtisch (Admins/DevOps, Proxmox-affin). Zeitbudget je Block als Richtwert.

---

## Roter Faden (eine Folie zum Merken)

> Proxmox kann volle VMs **und** Container — dazwischen klafft eine Lücke.
> MicroVMs füllen sie: VM-Isolation, fast Container-Tempo. QEMU microVM passt in
> Proxmox, sobald man `qemu-server` ein paar Dinge beibringt. Und der eigentliche
> Boot-Hebel ist am Ende **nicht der VMM, sondern der Kernel**.

Diese Kern-These des Stammtischs bleibt, wird aber in einen Proxmox-Rahmen
gestellt: „Was heißt das konkret für meinen Proxmox-Host?"

---

## Blockübersicht (Zeitbudget ~45 min)

| # | Block | min | Herkunft |
| :-- | :-- | :-- | :-- |
| 0 | Titel | – | neu |
| 1 | Wer bin ich / Einordnung | 2 | Stammtisch (adapt) |
| 2 | Motivation: die Lücke zwischen LXC und VM | 3 | Stammtisch (Proxmox-Frame) |
| 3 | Isolationsspektrum & die drei Kandidaten (komprimiert) | 5 | Stammtisch (kürzen) |
| 4 | Wie Proxmox eine VM startet | 6 | **neu** |
| 5 | Warum microVMs in PVE nicht out-of-the-box laufen | 4 | **neu** |
| 6 | Der Patch: minimal-invasiv microVM in `qemu-server` + GUI | 8 | **neu** |
| 7 | Sauber testen: `.deb`-Build + nested-PVE-Pipeline | 3 | **neu** (kürzbar) |
| 8 | Benchmarks: Kernel-Hebel + PVE-Overhead + Skalierung | 8 | Stammtisch + **neu** |
| 9 | Live-Demo: microVM in der Proxmox-Web-UI | 4 | **neu** |
| 10 | Einordnung & Grenzen (Proxmox-Brille) | 2 | Stammtisch (adapt) |
| 11 | Status/Upstream-RFC + Zusammenfassung | 2 | **neu** |
| — | Q&A | Rest | – |

Kürzungs-Reserve, falls die Zeit knapp wird: Block 7 ganz raus (nur 1 Satz),
Block 3 auf 3 min stauchen.

---

## Detail je Block

### 1 · Wer bin ich (2 min)
- Alexander Wirt, credativ — Debian Developer, Schwerpunkt Virtualisierung/Proxmox.
- Aufhänger: „Ich betreibe Proxmox. Firecracker fasziniert mich — passt das zusammen?"
- *Übernahme aus Stammtisch, Proxmox-Bezug betont.*

### 2 · Motivation: die Lücke zwischen Container und VM (3 min)
- Proxmox-Admin kennt zwei Werkzeuge: **LXC** (schnell, dicht, geteilter Kernel)
  und **KVM-VM** (harte Isolation, eigener Kernel, aber schwer & langsam im Start).
- Dazwischen: tausende kurzlebige, isolierte Workloads (CI-Runner, FaaS,
  Multi-Tenant). Container zu unsicher, volle VM zu teuer.
- **MicroVM** = VM-Isolation ohne den Ballast. *Das ist das Versprechen — den Rest
  des Vortrags prüfen wir, ob und wie das auf Proxmox aufgeht.*
- *Asset:* Stammtisch-Slide „Warum microVMs?" + Isolations-Stack, um LXC ergänzt.

### 3 · Isolationsspektrum & die drei Kandidaten (5 min, komprimiert)
- Ein KVM unten, drei VMMs darüber: **QEMU full (q35)**, **QEMU microVM**,
  **Firecracker**. Kernaussage: KVM ist überall gleich, nur der VMM (Device-Modell
  + Sicherheitsgrenze) unterscheidet sich.
- Firecracker: ~50k Zeilen Rust, 5 Geräte, Jailer, REST-API — Basis von AWS Lambda.
- QEMU microVM: *derselbe QEMU, den Proxmox schon nutzt*, nur anderer Machine Type
  (kein PCI/ACPI, virtio-mmio, Direkt-Boot via `-kernel`). **Das ist der Hebel für
  Proxmox** — kein neuer VMM im Stack, nur eine andere Betriebsart.
- Architektur-/Security-Tabellen aus dem Stammtisch nur kurz zeigen, nicht ausführen.
- *Asset:* Stammtisch-Slides „Spektrum", „Firecracker", „QEMU microVM", Architektur-Tabelle (gekürzt).

### 4 · Wie Proxmox eine VM startet (6 min) — **neu**
- `/etc/pve/qemu-server/<vmid>.conf` → `pve-qemu-server` (`config_to_command`) →
  `qemu-system-x86_64`-Kommandozeile. Kurz `qm showcmd <vmid>` live zeigen.
- Proxmox baut per Default ein volles PC/**q35**-Modell: PCIe-Root-Ports,
  PCI-Bridges, VGA/SPICE, USB-Tablet, ACPI/OVMF-SeaBIOS.
- Zentrale Perl-Module benennen (Landkarte, nicht Code): `QemuServer.pm`,
  `QemuServer/Machine.pm`, `QemuServer/PCI.pm`, `QemuServer/Drive.pm`.
- *Quelle:* [`../proxmox-patch/README.md`](../proxmox-patch/README.md) §1.
- *Asset (neu):* Diagramm „conf → config_to_command → qemu-Args"; ein `qm showcmd`-Ausschnitt.

### 5 · Warum microVMs in PVE nicht out-of-the-box laufen (4 min) — **neu**
- microVM hat **keinen PCI-Bus** → q35s Bridge-Topologie passt nicht.
- Kein ACPI/klassisches BIOS → PVH/Direkt-Boot statt SeaBIOS/OVMF.
- Device-Transport: `virtio-blk-pci` → `virtio-blk-device` (MMIO), analog Netz.
- Default-Geräte (VGA/USB/SPICE) müssen weg.
- Fazit: Proxmox generiert genau die Hardware, die microVM nicht hat → man muss
  `qemu-server` beibringen, für diesen Machine Type anders zu bauen.
- *Quelle:* [`../proxmox-patch/README.md`](../proxmox-patch/README.md) §2.
- *Asset (neu):* Gegenüberstellung q35-Cmdline vs. microvm-Cmdline (rot = entfällt).

### 6 · Der Patch: microVM in `qemu-server` (8 min) — **neu, Herzstück**
- Design-Prinzipien: **null Impact** auf `pc`/`q35` (alles hinter
  `if machine =~ /^microvm/`), **Opt-in** per `.conf`, upstream-tauglich.
- Backend-Patch (`0001`): Machine-Type registrieren · PCI-Bridges/VGA/USB
  überspringen · Laufwerke/Netz auf virtio-mmio übersetzen · `kernel`/`initrd`/
  `args` in Direkt-Boot durchreichen.
- GUI-Patch (`0002`): `microvm` im Machine-Dropdown (`MachineEdit.js`) + im
  Erstellungs-Wizard (`CreateWizard.js`).
- **Praxis-Anekdote (Heureka-Moment aus der Entwicklung):**
  ExtJS-Falle in `MachineEdit.js`: Proxmox hat `microvm` anfangs beim Speichern
  stillschweigend auf `Default (i440fx)` zurückgesetzt, weil es alles außer `q35`
  als veralteten gepinnten Versions-String interpretierte (`pc-i440fx-5.1`).
- Config-Beispiel zeigen:
  ```ini
  machine: microvm
  kernel: /var/lib/vz/template/qemu/vmlinuz-slim
  args: console=hvc0 root=/dev/vda rw
  virtio0: local-lvm:vm-100-disk-0,size=4G
  ```
- Ehrlichkeit: aktueller Stand ist Draft/experimentell (Grenzen in Block 10).
- *Quelle:* [`../proxmox-patch/README.md`](../proxmox-patch/README.md) §3.
- *Asset (neu):* Patch-„Landkarte" (welches Modul, welche Änderung), Config-Snippet, GUI-Dropdown-Screenshot.

### 7 · Sauber testen — `.deb`-Build + nested PVE (3 min, kürzbar) — **neu**
- Kurzargument: einen PVE-Patch testet man nicht per `.pm`-Copy ins laufende
  System, sondern als echtes Paket. → Ansible-Pipeline baut die Patches als
  `.deb` (quilt) in einer Build-VM und installiert sie in einer **nested
  PVE-Test-VM**; Verifikation über `qm showcmd`.
- **Nested KVM Tipp:** Warum `--cpu host` (statt Default `kvm64`) essenziell ist,
  damit Hardware-Virtualisierung (`/dev/kvm`) bis in die Test-VM durchgereicht wird.
- Botschaft: reproduzierbar, isoliert, Host bleibt sauber — „so wird aus einem
  Draft-Patch etwas Vorzeigbares."
- *Quelle:* [`../build-pipeline/README.md`](../build-pipeline/README.md).
- *Asset (neu):* das ASCII-Flow-Diagramm aus der Pipeline-README (vereinfacht).
- *Kürzung:* Wenn Zeit knapp → ein Satz + Verweis aufs Repo.

### 8 · Benchmarks (8 min) — Stammtisch-Kern + PVE-Erweiterung
- **Methodik zuerst** (fair!): nur der VMM variiert, identischer Slim-Kernel &
  rootfs, Readiness-Marker auf serieller Konsole.
- **Cold-Start** (`startup.svg`): gleicher Kernel → alle dicht beieinander,
  Faktor 10 aus der Literatur schmilzt.
- **Der Kernel-Hebel** (`kernel.svg`): dieselbe microVM, nur Kernel getauscht →
  Faktor 6–7. *Die zentrale Erkenntnis, bleibt Höhepunkt.*
- **Proxmox-Overhead (neu):** `pve_microvm` (patched PVE) vs. rohes CLI-QEMU-
  microVM vs. Firecracker vs. q35 — kostet die Proxmox-Schicht messbar Boot/RSS?
- **Skalierung/Dichte** (`concurrent.svg`, `density.svg`): Firecrackers Domäne —
  ~3× VMs pro GB RAM; ehrlich benennen, wo QEMU microVM nicht mithält.
- *Quelle:* [`../benchmarks/README.md`](../benchmarks/README.md), Charts aus `../../charts/`.
- *Asset (neu):* Chart mit der `pve_microvm`-Variante (Startup + RSS).

### 9 · Live-Demo (4 min) — **neu**
- In der Proxmox-Web-UI: VM anlegen, im Wizard Machine-Type **microvm** wählen
  (der GUI-Patch), starten, Boot auf der Konsole zeigen.
- **Safety Net / Fallback:** Vorbereitetes Backup-Slide mit Terminal-Ausschnitt /
  `qm showcmd` & Screenshot der laufenden Web-UI (falls Konferenz-WLAN/Tunnel zickt).
- *Asset (neu):* Demo-Skript + Fallback-Aufzeichnung.

### 10 · Einordnung & Grenzen mit Proxmox-Brille (2 min)
- Entscheidungshilfe erweitert um **LXC**: LXC (max. Dichte, geteilter Kernel) ·
  microVM (Isolation + Tempo, kurzlebig) · full VM (Windows/GPU/Live-Migration).
- Ehrliche Grenzen von PVE-microVM: **Live-Migration** schwach (nicht
  versioniert, kein Hotplug), Snapshot-Feinheiten, Feature-Parität zur GUI,
  „experimentell". Wer Live-Migration braucht → q35.
- *Asset:* Stammtisch-„Wann nimmt man was?"-Tabelle, um LXC/PVE-Zeile ergänzt.

### 11 · Status, Upstream-RFC & Zusammenfassung (2 min)
- Stand des Patches, Idee eines RFC an die Proxmox-Community, offene Punkte.
- Take-aways: (1) microVM = QEMU, das Proxmox schon kann, nur anders konfiguriert;
  (2) der Patch ist bewusst minimal-invasiv; (3) **der Kernel, nicht der VMM, ist
  der Boot-Hebel.**
- *Asset:* Stammtisch-„Zusammenfassung“-Slide, Proxmox-Fazit ergänzt.

---

## Was aus dem Stammtisch übernommen / gekürzt / neu ist

- **Übernehmen (evtl. straffen):** Isolationsspektrum, drei Kandidaten,
  Architektur- & Security-Tabellen, alle Benchmark-Charts, „Kernel ist der Hebel",
  Entscheidungstabelle.
- **Kürzen:** Firecracker-Internals/BIOS-Tonspur und Security-Deep-Dive — beim
  technischeren Publikum knapper, dafür Raum für Proxmox.
- **Neu:** Block 4–7 + 9 + 11 (Proxmox-Startpfad, Warum-nicht-nativ, Patch, Test-
  Pipeline, Live-Demo, Upstream-Status) und der `pve_microvm`-Benchmark.

## Neu zu erstellende Assets (Backlog)
1. Diagramm „`.conf` → `config_to_command` → qemu-Args".
2. Gegenüberstellung q35- vs. microvm-Kommandozeile (Diff-Optik).
3. Patch-Landkarte (Modul → Änderung) + Config-Snippet + GUI-Screenshot.
4. Benchmark-Chart mit `pve_microvm`-Variante (Startup + RSS).
5. Live-Demo-Skript + Fallback-Screencast.
6. Vereinfachtes Pipeline-Flow-Diagramm (Block 7).
