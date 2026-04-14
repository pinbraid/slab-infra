
*This guide was my initial walkthrough of how to get PiHole up and running within my already established Proxmox environment.*

**If you’re following this guide, replace the example network values with the actual IPs used by your own network.**

1.  **Proxmox Host Updated:** Ensure your Proxmox server is fully updated.
2.  **Networking Working:** Confirm your Proxmox host can access the internet.
3.  **Download Ubuntu LXC Template:** This is the base operating system for your Pi-hole container.
    *   In the Proxmox web UI, on the left menu, click on your server (`proxmox-slab`).
    *   In the middle panel, click on **Local (proxmox-slab)** (your XXXGB boot drive).
    *   Click on the **CT Templates** tab.
    *   Click **Templates**.
    *   Scroll down and select `ubuntu-22.04-standard` (or `ubuntu-24.04-standard` if available and you prefer the absolute latest).
    *   Click **Download**. Wait for it to complete.

---

### **Part 1: Creating the Pi-hole LXC Container in Proxmox**

An LXC container is perfect for Pi-hole because it's incredibly lightweight, fast, and uses minimal resources.

1.  **Click "Create CT":** In the top-right corner of the Proxmox web UI, click the **Create CT** button (it looks like a little blue box).

2.  **General Tab:**
    *   **Host Name:** `pihole` (or `dns-server`, etc. – something descriptive).
    *   **Password:** Set a strong password for the `root` user *inside* the container. Confirm it.
    *   **Unprivileged container:** Keep this **checked** (default).
    *   Click **Next**.

3.  **Template Tab:**
    *   **Storage:** Select **`local`** (this is where you downloaded the template).
    *   **Template:** Select the `ubuntu-22.04-standard.tar.zst` (or 24.04) that you just downloaded.
    *   Click **Next**.

4.  **Disk Tab:**
    *   **Storage:** Select **`vm-storage`** (local NVMe storage – this is crucial for performance).
    *   **Disk size (GB):** `8` (Pi-hole uses very little space, 8GB is generous).
    *   Click **Next**.

5.  **CPU Tab:**
    *   **Cores:** `1` (Pi-hole barely needs one core. You can give it 2 if you're feeling generous, but 1 is plenty).
    *   Click **Next**.

6.  **Memory Tab:**
    *   **Memory (MB):** `512` (Pi-hole runs comfortably on 512MB; 1024MB (1GB) is also a safe choice if you have the RAM to spare).
    *   Click **Next**.

7.  **Network Tab (CRITICAL STEP):**
    *   **Bridge:** `vmbr0` (This is your main network bridge).
    *   **YOUR_PIHOLE_IP/CIDR:** `YOUR_PIHOLE_IP (with the correct subnet/CIDR for your LAN)` (This is the **static IP** for your Pi-hole. I made sure to reserve IP addresses within my home network for Infrastructure).
    *   **Gateway:** `YOUR_GATEWAY_IP` (Your router's IP address).
    *   Leave IPv6 as `(automatic)`.
    *   Click **Next**.

8.  **DNS Tab (CRITICAL STEP):**
    *   **Use host settings:** **Uncheck** this box. We want the container to use external DNS *before* Pi-hole is installed.
    *   **DNS server:** `8.8.8.8` (Google's public DNS).
    *   **DNS Domain:** Leave blank.
    *   Click **Next**.

9.  **Confirm Tab:**
    *   Review all settings. Make sure the IP, Disk Storage, and Template are correct.
    *   **Start after created:** **Check** this box.
    *   Click **Finish**.

Proxmox will now create and start your Pi-hole LXC container. 
You will see its ID (e.g., `100`) appear in the left-hand menu.

---

### **Part 2: Installing Pi-hole Inside the LXC Container**

Now that the container is running, we install Pi-hole into it.

1.  **Access the LXC Console:**
    *   In the Proxmox left menu, click on your new Pi-hole container (e.g., `100 (pihole)`).
    *   In the middle column, click on **Console**. This will open a terminal directly into your container.

2.  **Log In to the Container:**
    *   You will see a login prompt. Type `root` and press Enter.
    *   Enter the `root` password you set when creating the container and press Enter.

3.  **Update the Container's OS:**
    *   First, ensure the container's operating system is fully up-to-date.
    *   ```bash
        apt update && apt upgrade -y
        ```
    *   This will take a minute or two.

4.  **Install Pi-hole:**
    *   Pi-hole provides an easy-to-use installation script.
    *   ```bash
        curl -sSL https://install.pi-hole.net | bash
        ```
    *   Follow the on-screen prompts:

        *   **Welcome Screen:** Just hit **Enter** to proceed.
        *   **Static IP (Critical):** The installer will detect `YOUR_PIHOLE_IP`. This should be the same static IP you configured in the Proxmox network tab. It will confirm this is your static IP. **Confirm this is correct** and hit **Enter**.
        *   **Upstream DNS Provider:** Select a reliable public DNS provider (e.g., **Cloudflare**, **Google**, or **OpenDNS**). These are the servers Pi-hole will ask when it doesn't have a record in its cache. Use your arrow keys and spacebar to select, then hit Enter.
        *   **Blocklists:** Keep the default blocklists selected. Hit **Enter**.
        *   **Web Admin Interface:** Select **On** (recommended). Hit **Enter**.
        *   **Install Lighttpd web server:** Select **On** (recommended). Hit **Enter**.
        *   **Log Queries:** Keep **On** (recommended for troubleshooting and statistics). Hit **Enter**.
        *   **Privacy Mode:** Choose your preference (e.g., "Show everything" for full visibility while learning). Hit **Enter**.
        *   **Installation Complete:** The installer will show you the **password for the Pi-hole web interface**. **SAVE THIS SOMEWHERE** You will need it to log into the Pi-hole dashboard.

---

### **Part 3: Configuring Your Network to Use Pi-hole**

This is the most crucial step. You need to tell your devices (or your router) to use `YOUR_PIHOLE_IP` as their primary DNS server.

#### **Option A: Router DHCP Settings (Recommended for Home Networks)**

This is the best method because every device that connects to your Wi-Fi or router (phones, smart TVs, IoT devices, guests) will automatically use Pi-hole without any individual configuration.

1.  **Log into Your Router:**
    *   Open a web browser on your personal computer.
    *   Go to your router's IP address.
    *   Log in with your router's admin username and password.

2.  **Find DHCP Settings:**
    *   Look for sections like "LAN Setup," "DHCP Server," "Network Settings," or "Internet Settings."
    *   You are looking for where your router hands out IP addresses (your DHCP address range).

3.  **Change DNS Server Settings:**
    *   Find the fields for "Primary DNS Server" and "Secondary DNS Server."
    *   **Primary DNS:** Change this to **`YOUR_PIHOLE_IP`** (your Pi-hole's static IP).
    *   **Secondary DNS (Optional but Recommended):** You have two choices here:
        *   **`8.8.8.8` (or `1.1.1.1`):** A public DNS server. This acts as a fallback if your Pi-hole ever goes down. However, it will bypass Pi-hole's ad-blocking.
        *   **Leave it blank / use your Pi-hole's IP again:** If your router allows you to put the same IP twice, or leave the secondary blank, this forces all DNS through Pi-hole. If Pi-hole goes down, DNS will stop working entirely. This is better for ensuring 100% ad blocking, but reduces redundancy.
        *   **Recommendation for learning:** Start with **`YOUR_PIHOLE_IP` for Primary** and **`8.8.8.8` for Secondary**. This allows you to confirm Pi-hole is working without losing internet access entirely if something goes wrong.

4.  **Save Settings:** Apply the changes on your router.

5.  **Reboot/Renew Client IPs:**
    *   For changes to take effect on your devices, you need to either:
        *   **Reboot each device** (phone, computer, smart TV).
        *   On Windows, open Command Prompt and type `ipconfig /release` then `ipconfig /renew`.
        *   On Mac/Linux, disconnect and reconnect to Wi-Fi/Ethernet.

#### **Option B: Per-Device Configuration (for Testing or Specific Devices)**

You can manually set the DNS on individual devices if you only want some devices to use Pi-hole, or for initial testing without changing your router.

*   **Windows:** Network and Internet Settings > Ethernet/Wi-Fi > Change adapter options > Right-click adapter > Properties > IPv4 > Properties > "Use the following DNS server addresses" -> Primary: `YOUR_PIHOLE_IP`, Secondary: `8.8.8.8`.
*   **macOS:** System Settings > Network > Wi-Fi/Ethernet > Details > DNS > Add `YOUR_PIHOLE_IP`.
*   **Android/iOS:** Usually in Wi-Fi settings for the connected network, under "IP Settings" or "Configure DNS."

---

### **Part 4: Verification and First Use**

1.  **Access Pi-hole Web Interface:**
    *   On your personal computer, open a web browser.
    *   Go to: **`http://YOUR_PIHOLE_IP/admin`**
    *   Log in using the web interface password Pi-hole gave you during installation.
    *   You should see the dashboard showing DNS queries and blocked ads!

2.  **Confirm DNS Resolution from a Client Device:**
    *   On a device that should now be using Pi-hole (e.g., your personal computer), open Command Prompt (Windows) or Terminal (Mac/Linux).
    *   Type:
        ```bash
        nslookup google.com
        ```
    *   The output should show `Server: YOUR_PIHOLE_IP` (or `127.0.0.53` if the client is itself running a local DNS cache that queries Pi-hole). This confirms your device is querying Pi-hole.

3.  **Test Ad Blocking:**
    *   Visit a notoriously ad-heavy website (e.g., `www.cnet.com`, `www.forbes.com`, `www.dailymail.co.uk`).
    *   You should notice significantly fewer (or no) ads.
    *   Check your Pi-hole dashboard—you'll see an increase in "Queries Blocked."

Congratulations! You now have a fully operational, network-wide ad blocker and DNS server. This is a powerful step in securing and improving your home network, and excellent practical experience in managing a core infrastructure service.

---

### **Part 5: Post-Install Configuration (Proxmox)**

After confirming Pi-Hole is functional, apply these settings in the Proxmox GUI to ensure DNS survives host reboots:

1.  **Start at Boot:** Select the Pi-Hole LXC → **Options** → **Start at boot** → Enable.
2.  **Boot Order:** Set **Boot Order = 1** so Pi-Hole starts before all other VMs/LXCs.
3.  **Startup Delay:** Set **Startup delay = 10s** to ensure the network bridge is ready before Pi-Hole initializes.

*This guarantees DNS is always the first service available after a host reboot.*