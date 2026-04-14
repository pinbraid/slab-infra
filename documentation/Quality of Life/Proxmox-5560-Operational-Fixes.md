# Proxmox on Dell Precision 5560 — Operational Fixes

This document describes the operational fixes I applied while running Proxmox on a Dell Precision 5560 laptop. The system constraints are:

* Single-node Proxmox host
* 32GB RAM
* 1TB NVMe storage
* Workloads include K3s, Ubuntu VMs, and future IoT/Kubernetes services
* Laptop hardware means battery, thermals, and sleep behavior are critical

The goal is to make the host stable, reduce unnecessary wear on NVMe, and keep the laptop running reliably as a hypervisor.

## 1. Battery charge management

Status: `applied ✅`

### Why
Laptop batteries degrade quickly if kept at 100% charge while plugged in continuously. Since the machine is acting as a stationary Proxmox host, the battery should be managed as a longevity feature rather than primary power.

### What was changed
* Entered BIOS using `F2`
* Set power management to either:
  * `Primarily AC Use`
  * or a custom charge profile such as start at 50% and stop at 80%

### Result
AC power is now preferred and the battery is not being kept at full charge constantly.

## 2. CPU power management and thermals

Status: `applied ✅`

### Why
The Dell laptop can produce significant heat under sustained VM workloads. Proxmox default CPU governor is `performance`, which keeps clocks high and increases thermal output.

### What was changed
* Installed `linux-cpupower`
  ```bash
  apt install linux-cpupower
  ```
* Verified the current driver and governor:
  ```bash
  cpupower frequency-info
  ```
* Switched to `powersave` governor:
  ```bash
  cpupower frequency-set -g powersave
  ```
* Persisted the setting with crontab:
  ```text
  @reboot /usr/bin/cpupower frequency-set -g powersave > /dev/null 2>&1
  ```

### Result
The CPU now scales down when idle and still boosts when VMs require compute. This reduces fan noise and thermal pressure.

## 3. Sleep and lid behavior

Status: `applied ✅`

### Why
On a laptop host, sleep or lid-triggered suspend can crash Proxmox and all running VMs. The system must remain active even if the lid is closed.

### What was changed
* Updated GRUB to power down the local console after idle, without suspending the host:
  ```bash
  nano /etc/default/grub
  ```
  Append:
  ```text
  consoleblank=60
  ```
  Then:
  ```bash
  update-grub
  ```
* Updated systemd logind settings to ignore lid events:
  ```bash
  nano /etc/systemd/logind.conf
  ```
  Set:
  ```text
  HandleLidSwitch=ignore
  HandleLidSwitchExternalPower=ignore
  HandleLidSwitchDocked=ignore
  ```
* Masked sleep targets to prevent any accidental suspend:
  ```bash
  systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  ```
* Rebooted to apply changes.

### Result
The display backlight can turn off automatically, but the host remains fully operational with lid closure ignored.

## 4. Single-node NVMe endurance: disable HA services

Status: `applied ✅`

### Why
Proxmox HA services generate constant writes to `pmxcfs`, which is unnecessary on a single-node host and can reduce NVMe lifespan.

### What was changed
* Disabled and stopped HA services:
  ```bash
  systemctl disable --now pve-ha-lrm
  systemctl disable --now pve-ha-crm
  ```

### Result
Reduced background cluster-related writes and CPU overhead on the single-node host.

## 5. VLAN-aware bridge configuration

Status: `applied ✅`

### Why
The physical network and future IoT/Kubernetes segments will benefit from VLAN tagging. Enabling VLAN awareness now avoids later bridge rework.

### What was changed
* In the Proxmox GUI, opened `vmbr0` and enabled `VLAN aware`
* Applied the network configuration

### Result
The bridge is ready for VLAN-tagged traffic without additional bridge creation.

## 6. Memory deduplication monitoring (KSM)

Status: `monitoring ⚠️`

### Why
Three Ubuntu VMs for K3s are expected to load similar memory pages. KSM can deduplicate identical pages and free RAM.

### What to know
* Proxmox `ksmtuned` normally activates when host RAM reaches around 80%
* No action is required immediately, but this should be monitored once the cluster workload increases

### Result
KSM is left to trigger automatically when needed.

## 7. SSD swap and trim management

Status: `partially applied ✅`

### Why
Swap activity on the NVMe should be minimized. At the same time, trim and discard must be enabled so that deleted VM storage is actually freed on the SSD.

### What was changed
* Enabled weekly SSD trim:
  ```bash
  systemctl enable --now fstrim.timer
  ```
* Verified that LVM-Thin discard is enabled for new VMs in the Proxmox GUI (Disks tab)

### Planned/future action
* Tune `vm.swappiness` if swap needs to be further restricted:
  ```bash
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
  sysctl -p
  ```
  (or use `1` for a more aggressive emergency-only setting)

### Result
Trim is active and the host is configured to reclaim space correctly. Swap tuning remains a future optimization.

## 8. Backup schedule

Status: `applied ✅`

### Why
A single-node lab environment is vulnerable to configuration mistakes. Regular backups are necessary for recovery.

### What was changed
* Created a local Datacenter Backup job in Proxmox
* Set schedule to nightly at `02:00 MST`
* Set selection mode to `All`
* Set retention to keep the last `3` backups

### Result
Automatic snapshots are now taken nightly, enabling quick restoration after an outage or misconfiguration.

## Notes

This article is intended as a concise record of operational actions applied to a Proxmox host running on laptop hardware. The laptop form factor imposes additional constraints on battery health, thermals, and suspend behavior, so the emphasis is on durability and stability rather than raw performance.
