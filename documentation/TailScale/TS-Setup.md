# Tailscale VPN — Debian 12 LXC Rebuild

*Clean rebuild: dedicated homelab GitHub OAuth, Debian 12 Bookworm LXC, subnet router for full LAN access.*

### GitHub Account Used: `PRIVATE GITHUB`
When using GitHub, you can use your regular GitHub account, but I decided to create a separate dedicated GitHub account to ensure that the access here was as isolated as possible.

## Assumptions

This guide assumes:

- You have Proxmox host shell access and the privileges needed to edit LXC configs and sysctl settings.
- The Debian 12 standard LXC template has already been downloaded.
- Your Proxmox host supports the LXC capabilities used here, including unprivileged containers and `/dev/net/tun` passthrough.

> **Placeholder convention:** Values like `CTID`, `STATIC-IP-ADDRESS`, `ROUTER-IP`, `PI-HOLE-IP`, and `YOUR_PRE_AUTH_KEY` are examples. Replace them with your environment's actual values before running commands.

## Prerequisites

- Proxmox host operational with `vmbr0` bridge and VLAN-aware enabled.
- Pi-Hole DNS active at `PI-HOLE-IP` (Boot Order 1).
- Debian 12 standard LXC template downloaded (`pveam download local debian-12-standard`).
- Dedicated homelab GitHub account created (see Section 0).
- Tailscale account registered at [login.tailscale.com](https://login.tailscale.com) via **GitHub OAuth** with the homelab account.
- Pre-auth key generated from the Tailscale admin console (see Section 0).

---

## 0. Account & Pre-Auth Setup

This section covers creating a clean, decoupled Tailscale identity before any infrastructure work begins.

### Create a Dedicated Homelab GitHub Account

1. Go to [github.com/join](https://github.com/join) and create a new account.
   - Use a separate email address from your primary GitHub account.
   - Suggested username pattern: `<your-handle>-homelab` or `<your-handle>-lab`.
2. Enable 2FA on the new account before proceeding.

> **Why a dedicated account?** This decouples your homelab Tailnet from your primary GitHub identity. The same account will serve as the home for future IaC (Terraform) repos per the Extraction Protocol portfolio requirement.

### Sign Up for Tailscale

1. Go to [login.tailscale.com](https://login.tailscale.com).
2. Select **"Sign in with GitHub"** and authorize with your **homelab** GitHub account (not your primary account).
3. Complete the network creation prompt — name it something like `homelab` or `slab`. This is a personal preference, something that you can really call whatever makes the most sense and is descriptive to what you're going to be hosting TS on. 

### Generate a Pre-Auth Key

Pre-auth keys allow the LXC container to join the Tailnet headlessly — no browser, no interactive login required.

1. In the Tailscale admin console, go to **Settings → Keys → Generate auth key**.
2. Configure the key:

   | Setting | Value |
   | :--- | :--- |
   | **Reusable** | No (single-use for this build) |
   | **Ephemeral** | No (node should persist after disconnection) |
   | **Expiry** | 90 days (or your preference) |
   | **Tags** | Optional — e.g., `tag:infra` |

3. Copy the key immediately — it will not be shown again.

> **Security note:** Treat this key like a password. Do not commit it to any repository. Use it once during Section 7 (`tailscale up`) and clear it from clipboard history afterward. Generate a new key if this build is interrupted.

---

## 1. Decommission Old LXC

Before rebuilding, remove the old Tailscale node cleanly:

1. **Deauthorize the old device** in the [Tailscale admin console](https://login.tailscale.com/admin/machines) → click the node → **Remove machine**.
2. **Stop and destroy the old LXC** from the Proxmox GUI or shell:
    ```bash
    pct stop <OLD_CTID>
    pct destroy <OLD_CTID>
    ```

---

## 2. Create Debian 12 LXC

Create an unprivileged container via the Proxmox GUI (**Create CT**) or CLI:

| Setting           | Value                                                     |
| :---------------- | :-------------------------------------------------------- |
| **CT ID**         | `102` (or next available)                                 |
| **Hostname**      | `tailscale-vpn`                                           |
| **OS Template**   | `debian-12-standard` (Bookworm)                           |
| **Unprivileged**  | Yes                                                       |
| **Disk**          | `2 GB` on `vm-storage`                                    |
| **CPU**           | `1 core`                                                  |
| **RAM**           | `256 MB`                                                  |
| **Swap**          | `0`                                                       |
| **Network**       | `vmbr0`, Static `STATIC-IP-ADDRESS/24`, GW `ROUTER-IP`    |
| **DNS**           | `PI-HOLE-IP` (Pi-Hole)                                    |
| **Start at boot** | Yes, **Boot Order 2** (after Pi-Hole)                     |

**Do not start the LXC yet.** Host-side configuration in Section 3 must be applied first.

---

## 3. Host-Side TUN Passthrough & IP Forwarding

Both the TUN device passthrough and IP forwarding must be configured on the **Proxmox host** before the container starts. SSH into the Proxmox host to perform these steps.

### 3a. TUN Device Passthrough

Tailscale requires `/dev/net/tun` for native WireGuard performance. Edit the LXC config file:

```bash
nano /etc/pve/lxc/<CTID>.conf
```

Append these two lines:

```text
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

### 3b. Enable IP Forwarding on the Proxmox Host

Subnet routing requires the host to forward packets between the container's virtual interface and the physical bridge (`vmbr0`). Without this, advertised routes will appear active but traffic will silently drop at the host boundary.

```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-ip-forward.conf
sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

Verify it took effect:

```bash
sysctl net.ipv4.ip_forward
# Expected output: net.ipv4.ip_forward = 1
```

### Start the LXC

```bash
pct start <CTID>
```

---

## 4. Container Hardening, Cleanup & IP Forwarding

Log into the LXC console (`pct enter <CTID>`) and run the following.

### Strip Unnecessary Packages

```bash
apt update && apt upgrade -y
apt purge -y exim4 exim4-base exim4-config exim4-daemon-light postfix rpcbind nfs-common
apt autoremove -y
```

**Why:** `exim4`/`postfix` are mail servers. `rpcbind`/`nfs-common` are NFS utilities. None belong on a VPN gateway.

### Disable Internal Time-Sync

The Proxmox host handles NTP — disable it inside the container to avoid conflicts:

```bash
systemctl disable --now systemd-timesyncd
```

### Enable IP Forwarding Inside the Container

Tailscale's subnet router requires `ip_forward` to be set **both** on the Proxmox host (done in Section 3b) and inside the container itself. The container-level setting enables Tailscale to forward packets between the Tailnet tunnel and the LAN interface.

```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf
```

Verify:

```bash
sysctl net.ipv4.ip_forward
# Expected output: net.ipv4.ip_forward = 1
```

---

## 5. Install Tailscale (First-Party Apt Repo)

Install via the official Tailscale script, which configures the stable apt repository and installs the package. It is convenient, but if you prefer stricter auditing, review the script first before piping it to `sh`:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

---

## 6. Systemd Service Hardening

### The Three-Layer Security Model

| Layer | Protection | What It Does |
| :---- | :--------- | :----------- |
| **A. Unprivileged LXC** | Container isolation | `root` inside the LXC maps to UID `100000` on the host — a "fake root" with no host-level privileges. |
| **B. TUN Passthrough** | Explicit device access | Only `/dev/net/tun` is granted — no other host devices are exposed. This is the device isolation boundary (systemd `PrivateDevices` is intentionally omitted — see override comments). |
| **C. Systemd Hardening** | Service restriction | Even as "root" inside the container, Tailscale cannot access the filesystem, home directories, or kernel tunables. Does not restrict devices — that is Layer B's job. |

### Apply the Systemd Override

Create a drop-in override for the `tailscaled` service:

```bash
systemctl edit tailscaled
```

Paste the following configuration:

```ini
[Service]
# Filesystem restrictions
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

# Kernel restrictions
ProtectHostname=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true

# Only allow network management capabilities
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW

# NOTE: PrivateDevices=true is intentionally omitted.
# It creates a minimal /dev namespace that blocks /dev/net/tun access,
# causing tailscaled to crash on startup (exit-code 1, rapid restart loop).
# Device isolation is already handled by the unprivileged LXC boundary —
# only /dev/net/tun is passed through (see Section 3a).
```

Save and exit, then reload the daemon:

```bash
systemctl daemon-reload
```

---

## 7. Bring Up Tailscale

Authenticate and advertise the home LAN subnet in a single command:

```bash
tailscale up --advertise-routes=192.x.x.x/24 --auth-key=<YOUR_PRE_AUTH_KEY>
```

**`--advertise-routes=192.x.x.x/24`** tells the Tailnet that this node can route traffic to your entire home LAN. Once routes are approved in Section 8, remote Tailnet peers will be able to reach `PROXMOX-IP:8006` (Proxmox GUI), `PI-HOLE-IP/admin` (Pi-Hole), and all other static infrastructure.

> **Why `--shields-up` is intentionally omitted**
>
> `--shields-up` is designed for **mobile clients on untrusted public networks** (coffee shop WiFi, hotel hotspots). It sets iptables INPUT rules that reject all inbound connections to the node's Tailscale IP (`100.x.x.x`).
>
> In a **stationary LXC subnet router**, those same iptables rules interact with forwarded subnet traffic, introducing latency degradation. This matches observed behavior in this setup: subnet routes approved and working correctly, but all LAN access stalled — dropping `--shields-up` resolved it immediately. The exact behavior can vary by Tailscale version and host firewall rules.
>
> Security is fully covered by the three-layer model already in place:
> - **Unprivileged LXC** — fake root with no host privileges
> - **Explicit TUN passthrough** — only `/dev/net/tun`, nothing else
> - **Systemd hardening** — service-level filesystem and capability restrictions
>
> This node is stationary, single-purpose, and not internet-facing. `--shields-up` provides no meaningful additional protection here and actively degrades the core function of this node (subnet routing).

---

## 8. Admin Console — Approve Advertised Routes

Routes advertised in Section 7 are **not active** until manually approved in the Tailscale admin console. This is an intentional safety gate to prevent accidental subnet exposure.

1. Go to the [Tailscale admin console → Machines](https://login.tailscale.com/admin/machines).
2. Find the `tailscale-vpn` node (it should display as connected).
3. Click the node → scroll to **"Subnets"** → click **"Edit route settings"**.
4. Approve `192.x.x.x/24`.
5. Wait ~30 seconds for the route to propagate across the Tailnet.

Verify the route is active on the node:

```bash
tailscale status
# The node's own entry should show subnet routes: 192.x.x.x/24 what we typed in just before this step.
```

---

## 9. Verification

Run these from inside the LXC (`pct enter <CTID>`):

```bash
# Confirm tailnet connection and subnet advertisement
tailscale status

# Confirm Tailscale IP assignment (100.x.x.x range)
tailscale ip

# Run connectivity diagnostics
tailscale netcheck

# Verify systemd hardening is active
systemctl status tailscaled

# Confirm process is running (will show as root — "fake root" in unprivileged LXC)
ps aux | grep tailscale

# Confirm IP forwarding is active inside the container
sysctl net.ipv4.ip_forward
```

### Remote Access Test

From an **external device on the Tailnet** (e.g., a laptop or phone with Tailscale installed):

1. Ensure the remote device has route acceptance enabled:
   ```bash
   # Run this on the remote CLIENT device — not the router LXC
   tailscale up --accept-routes
   ```
   > **Note:** `--accept-routes` must be set on **client devices** that want to use advertised subnets. The router LXC only advertises routes — it does not need this flag.

   > **iOS / Android:** The mobile Tailscale app does not have a CLI. The equivalent of `--accept-routes` is the **"Use Tailscale subnets"** toggle found in **Tailscale app → Settings (gear icon)**.

2. Verify access to homelab infrastructure via the subnet route:
   - **Proxmox GUI:** `https://192.x.x.x:8006`
   - **Pi-Hole Admin:** `http://192.x.x.x/admin`

If both load without latency, the subnet router is working correctly.

### Persistence Verification

These checks confirm the VPN will recover automatically after a host crash, reboot, or power loss.

**From the Proxmox host:**

```bash
# Confirm the LXC is set to start at boot
pct config <CTID> | grep onboot
# Expected output: onboot: 1

# If missing or 0, fix it:
pct set <CTID> --onboot 1
```

**From inside the LXC** (`pct enter <CTID>`):

```bash
# Confirm tailscaled will start on container boot
systemctl is-enabled tailscaled
# Expected output: enabled

# If disabled, fix it:
systemctl enable tailscaled
```

### Reboot Persistence Test

Run from the **Proxmox host** to verify end-to-end recovery:

```bash
pct reboot <CTID>
# Wait ~30 seconds, then:
pct enter <CTID>

systemctl status tailscaled     # Should show: active (running)
tailscale status                 # Should show: connected with subnet routes
sysctl net.ipv4.ip_forward       # Should show: = 1
```

After confirming, re-run the remote access test from your phone over LTE to verify the full path.

> **Why re-auth is not needed after reboot:** When `tailscale up --auth-key=...` ran in Section 7, Tailscale wrote its authenticated state to `/var/lib/tailscale/tailscaled.state`. On every subsequent restart, `tailscaled` reads this file and reconnects automatically. The pre-auth key is only needed once for initial registration — you do not need to generate a new one unless you destroy and recreate the container.

---

## Runbook Summary

- **Tailscale VPN (LXC):** Unprivileged Debian 12 Bookworm container. GitHub OAuth auth via dedicated homelab account.
- **Role:** Subnet router — advertises `192.x.x.x/24` to the Tailnet for full LAN access from remote peers.
- **Hardening:** Three-layer model — unprivileged LXC, explicit TUN passthrough, systemd service overrides. Legacy mail/NFS packages purged.
- **Performance:** Native WireGuard via host-level TUN device passthrough. `--shields-up` intentionally omitted — causes iptables interaction latency in LXC subnet routing; three-layer model is the appropriate security layer for a stationary gateway.
- **IP Forwarding:** Enabled at both the Proxmox host level (`/etc/sysctl.d/99-ip-forward.conf`) and inside the container (`/etc/sysctl.d/99-tailscale.conf`).
- **Persistence:** LXC starts at boot (order 2, after Pi-Hole). `tailscaled` enabled via systemd. Authenticated state persists across reboots via `/var/lib/tailscale/tailscaled.state` — no re-auth required.