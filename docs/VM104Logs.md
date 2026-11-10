# Game Streaming Server (VM 104) — Build Log Extension

**Session dates:** Nov 9–10, 2026

---

## GOAL STATUS UPDATE

Game streaming VM is operational end-to-end: Bazzite + Sunshine + GTX 1660 passthrough, reachable on LAN and via Tailscale (away-WiFi proven, cellular partially — see Known Issues). Cold-boot-to-streamable chain validated with zero human input. Milestone: proof-of-concept upgraded to working build.

---

## SOLVED: The 503 "failed to initialize video capture/encoding" blocker

**Root cause (three stacked failures):**

1. **Sunshine as a systemd *system* service cannot capture the Wayland session.** Env vars (`XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`) point at the right paths but cannot grant session membership — Wayland/KWin capture requires being part of the login session, and portals/kwin reject processes from outside it. Every encoder probe failed at the *capture* step (journal showed `Failed to gain CAP_SYS_ADMIN` + `drop_elevated_privileges` loops, then `Fatal: Unable to find display or encoder during startup`). Note: capture failure kills **all** encoders (vulkan/vaapi/software/nvenc) regardless of `encoder = nvenc` config.
2. **Portal permission token went stale.** Sunshine's screen-capture approval on Wayland lives in `~/.config/sunshine/portal_token`. A stale token (likely flatpak-era or predating EFI rebuild) caused KWin to reject it and demand the interactive "Allow remote access" popup every single start — and headless, that popup = hang forever, ports never bind.
3. **Autostart raced the desktop portal.** Sunshine launching via KDE autostart at login started before `xdg-desktop-portal` was ready → `Error: Failed to create session:` → hung start, no ports, no error spam.

**The fix (final working architecture):**

- `systemctl disable --now sunshine` — system service abandoned entirely (known-bad fallback unit left at `/etc/systemd/system/sunshine.service`, disabled).
- KDE autostart file `~/.config/autostart/sunshine.desktop` with a **sleep delay**:

  ```ini
  [Desktop Entry]
  Type=Application
  Name=Sunshine
  Exec=/bin/bash -c "sleep 20 && sunshine"
  X-KDE-autostart-phase=2
  ```

- **Portal token reset procedure:** `rm ~/.config/sunshine/portal_token` → reboot → click Allow ONCE at the monitor (the fresh token then persists across reboots, no popup). WARNING: deleting `sunshine_state.json` at the same time forces re-pairing of ALL Moonlight clients (gotcha #11 companion — only do it when certs are actually broken).
- **Unit-file/desktop-file gotcha:** only the FIRST `Exec=` line is honored. Appending a second one silently does nothing.

**Verified:** two consecutive cold reboots: autologin → +20s → Sunshine listening (47984/47989/47990 TCP, 48010) → `portal_token` regenerates unattended → Moonlight streams.

---

## HARDWARE CHANGES

- **CPU:** i5-4590 → **i7-4790** (4c/8t), new thermal paste (prior session, carried forward).
- **GPU:** GTX 1060 removed → GTX 1660 (TU116) installed at PCI 01:00. IMPORTANT: Turing exposes four functions (.0 VGA, .1 Audio, .2 USB, .3 Type-C UCSI).
- **PSU:** upgraded to 650W.
- **Storage:** 2× ST8000DM004 (Seagate Barracuda, SMR consumer) 8TB installed → ZFS mirror (below).
- **Passthrough config fixed during transplant:** `/etc/modprobe.d/vfio.conf` still carried 1060 IDs (`10de:1c02,10de:10f1`) — caught pre-boot by `lspci -nnk -s 01:00.0` showing no driver in use. Updated to `10de:2184,10de:1aeb,10de:1aec,10de:1aed` (all four 1660 functions), `update-initramfs -u -k all`, host reboot, verified "Kernel driver in use: vfio-pci".
- 1660 delivers Turing NVENC — better encoder than the 1060's Pascal NVENC; `encoder = nvenc` config unchanged.

---

## NETWORK OUTAGE (post-hardware-reboot) — RESOLVED

**Symptoms:** every name-based service dead network-wide (Jellyfin phone app, Mac Samba, homepage blanket API errors); raw-IP access fine; Mac loses all internet when Tailscale toggles on.

**Root cause:** DHCP lease loss on eth0 (IPv4 only; IPv6 kept working, hiding it) in the two Tailscale-bearing LXCs after the disruptive reboot. Because Tailscale's global DNS points all personal devices at PiHole's tailnet address, one container's missing IPv4 = total household DNS blackout. Affected: CT 102 (pihole), CT 103 (apps/homepage).

**Diagnostic tell:** `hostname -I` inside container showed only a 100.x address; `ip -br addr` showed eth0 with IPv6 only, no IPv4, no default route.

**Resolution:**

- Immediate: `dhclient -v eth0` inside each affected container.
- Permanent: converted net0 to static v4 on CT 102 and CT 103 (`pct set <id> --net0 name=eth0,bridge=vmbr0,firewall=0,ip=192.168.1.X/24,gw=192.168.1.1` — router DHCP reservation guarantees the address). Validated on next cold host reboot: all four containers up with v4 addresses.
- CT 100 (jellyfin) and CT 101 (files) left DHCP intentionally as control subjects for the next disruptive reboot.

**New post-reboot sweep habit:**

```bash
for i in 100 101 102 103; do pct exec $i -- ip -br addr; done
```

**Lesson:** when everything breaks at once, suspect shared infrastructure (DNS) before individual services. DHCP-per-boot is a single point of failure for household DNS; static it.

**Also resolved in passing:** `hostname -I` inside a container lists all interfaces incl. tailscale0 — don't grab the wrong IP for diagnostics.

---

## BACKUP DRIVE: exFAT dirty-flag incident — CLEAN

Post-shutdown, dmesg showed `exFAT-fs (sde2): Volume was not properly unmounted. Please run fsck.` — 1TB USB backup drive (family photos). Procedure: test-read newest files while mounted → `umount /mnt/backup` → `fsck.exfat -n /dev/sde2` (check-only, NO repair on sole-copy backup without reading files off first) → CLEAN. Remounted, backup script path green. Cause: exFAT has no journal; shutdowns don't always flush USB cleanly. Cosmetic dirty flag, no data damage.

---

## STORAGE: 8TB ZFS MIRROR "tank" — LIVE

- Drives: `ata-ST8000DM004-2CX188_ZCT0F9YC` + `ata-ST8000DM004-2CX188_ZR139B9H` (by-id, stable names — never `/dev/sdX`)
- `wipefs -a` (bare read-only `wipefs` query first = identity check: NTFS/GPT signatures = right disks; ext4/exfat = WRONG disk, abort)
- `zpool create -o ashift=12 -m /tank tank mirror <by-id-1> <by-id-2>`
- Properties: `compression=lz4`, `atime=off`
- ARC capped: `options zfs zfs_arc_max=3221225472` (3GB) in `/etc/modprobe.d/zfs.conf` + `update-initramfs -u -k all` — 16GB host w/ suspect stick; revisit at 32GB kit install
- Registered in Proxmox: Datacenter → Storage → ZFS (`tank`), content types Disk image + Container
- Status: ONLINE, 0 errors, 7.14T usable. Verified auto-import after host reboot.
- SMR caveat documented: Barracudas are shingled — slow sustained writes, multi-day resilvers expected. Normal for these drives, not a config fault.
- Confirm scrub timer: `systemctl list-timers | grep -i zfs-scrub` (queued check)

## VM 104 GAME DISK — LIVE

- `qm set 104 --virtio1 tank:500` — 500GB (deliberate: forces library hygiene; grow anytime via `qm resize 104 virtio1 +NG` + `resize2fs /dev/vdb1` inside; shrinking is misery, expanding is minutes)
- Note: zfspool = raw only (no qcow2); ZFS thin-provisions + compresses natively (lz4 helps game data 10–30%)
- In-VM: parted/mkfs.ext4 `/dev/vdb1`, fstab entry `UUID=... /mnt/games ext4 defaults,nofail,discard 0 2` — `nofail` mandatory for headless boot resilience
- Bazzite: `/mnt` symlinks to `/var/mnt` — `df` shows `/var/mnt/games`; same place, not a fault
- systemd `daemon-reload` hint after fstab edit → run it, then `mount -a`
- Steam: Settings → Storage → add `/mnt/games` (Ctrl+L in folder picker to type path), set default
- Verified: mount survives VM cold reboot; Sunshine unaffected

---

## TAILSCALE IN VM 104 — LIVE


- `sudo systemctl enable --now tailscaled` → `sudo tailscale up --accept-dns=false` (keeps PiHole as DNS authority)
- `tailscale ip -4` → added `https://<tailnet-ip>:47990` to `csrf_allowed_origins` in sunshine.conf (extend the line; duplicates/`encode` vs `encoder` typos are how evenings die)
- Moonlight clients: bare IP only in Add Host (no `https://`, no port — that's for the web UI)
- Verified: WiFi + VPN streaming from iPhone and LAN streaming; cold-boot auto-reconnect good

## Sunshine operational notes

- Restart discipline: `pkill sunshine` → wait a few sec → `pgrep -a sunshine` (confirm gone; kill again if not) → `nohup sunshine &` → wait ~10s → `ss -tln | grep 479` — do not stream-test until ports confirm. Stale instances bind-block new ones (caused at least one confused "didn't come back up").
- Double-instance from repeated connect/disconnect churn happens; kill all, restart once, verify.

---

## KNOWN ISSUE (OPEN, EXONERATED INFRASTRUCTURE): iPhone cellular streaming — Moonlight RTSP error 60

**Status:** Unsolved; upstream (iOS client) suspect. **Workaround:** iPhone personal hotspot → stream from Mac/iPad/etc (proven); any WiFi streams direct (works everywhere that matters).

**Symptom:** iPhone over cellular (5G and LTE) pairs, control plane works (Big Picture launches), then RTSP handshake fails error 60. WiFi + VPN: instant success.

**Everything eliminated:**

- Carrier/UDP shaping: exonerated — Mac over iPhone's own hotspot (identical tower, 5G) streams flawlessly
- Codec: H.264 same failure as HEVC
- Bitrate/resolution: fails at 720p / 4 Mbps
- Signal: fails outdoors, full bars
- MTU: `mtu = 1316` added to sunshine.conf (correct for VPN carriage; kept — no harm), no effect
- Low Data Mode (was ON, switched to Standard): no effect
- Cellular permission per-app, Background App Refresh: all correct
- Fresh client from zero: Tailscale deleted + phone rebooted + new node identity + tailnet-lock re-sign + fresh Moonlight pairing — still fails
- Tailnet path: `tailscale ping` holds direct IPv6 pongs (~80ms) steady throughout failed attempts

**Next step:** file on tailscale/tailscale (and moonlight-stream/moonlight-ios) with the hotspot datapoint; revisit on client updates.

### Tailnet Lock note (hit during phone reinstall)

- Reinstalling Tailscale = new node identity → locked out awaiting re-sign. Signing node for this tailnet: CT 100 (jellyfin container).
- Procedure: `tailscale lock status` inside jellyfin → match the iPhone's own displayed node key hash (verify against the phone's screen, never an untrusted source) → `tailscale lock sign <hash>` → refresh phone app.
- **Action item: add a second signing device** (Mac CLI lives at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`; currently not in PATH) — a single signer that's also the most-frequently-rebuilt container is a self-lockout risk.

---

## SESSION GOTCHAS (append to master gotcha list)

13. **Wayland capture requires session membership** — env vars can't fake it; system-service Sunshine is architecturally wrong for Bazzite/KDE. In-session autostart is the correct design.
14. **Portal "Allow remote access" popup is not config-suppressible** — persistence comes solely from `~/.config/sunshine/portal_token`; when stale, delete it and approve interactively ONCE.
15. **Desktop files honor only the first `Exec=` line** — appending a second does nothing silently.
16. **Sunshine autostart needs a delay** (sleep 20) or it races xdg-desktop-portal and hangs with no ports and no errors.
17. **Autologin on Bazzite works out of the box** — there is no `/etc/sddm.conf.d/` to check; absence ≠ misconfiguration.
18. **`systemctl daemon-reload` after fstab edits** (plain `systemctl` invokes polkit auth prompt over SSH; `sudo` works fine).
19. **`hostname -I` in a Tailscale container shows the tailnet IP too** — grab the LAN IP from `ip -br addr`, not hostname -I, when testing LAN issues.
20. **PCI passthrough IDs follow the card, not the slot** — after GPU swap, verify `lspci -nnk` shows vfio-pci bound before booting the VM. New Turing cards expose 4 functions, not 2.
21. **zfspool storage = raw format only** — drop `format=qcow2` from qm disk creation on ZFS.
22. **`nohup` jobs report into `nohup.out`** in cwd — ignore; verify via ports/processes instead.
23. **ExFAT dirty flags after unclean shutdown** are usually cosmetic — read-only `fsck.exfat -n` before any repair decision; never repair a sole-copy backup drive without reading data off first.

---

## UPDATED QUEUE (replaces prior queued-work list)

1. ~~Fix the 503~~ **DONE**
2. ~~End-to-end stream test~~ **DONE** (LAN + away-WiFi proven; cellular parked as known issue)
3. ~~Hardware session: PSU + 1660 + 2×8TB~~ **DONE** (transplant, ZFS mirror, game disk)
4. ~~Tailscale in VM 104~~ **DONE** (add second tailnet-lock signer — open)
5. **File iPhone cellular issue** upstream (tailscale + moonlight-ios repos) with hotspot datapoint
6. **Tailscale on the Steam Deck** → then Deck streams away from home
7. **Media copy-in** from Windows PC → /tank; decide 4TB retirement role (candidate: relieve exFAT USB as backup target per roadmap restore-rehearsal gap)
8. **Scrub timer check**: `systemctl list-timers | grep -i zfs-scrub`
9. **Dummy plug** on 1660 HDMI when it arrives Thursday (~$8–10, B09P6DKF28) — swap monitor out, no VM config change expected, then monitor goes away
10. **32GB RAM kit** on arrival: retire suspect stick immediately, bump VM 104 RAM (currently 8GB), revisit zfs_arc_max
11. **iPhone/iPadOS Shortcut** auto-start flow (POST Proxmox API `https://<pve>:8006/api2/json/nodes/pve/qemu/104/status/start`, PVEAPIToken header, Content-Type: application/json, empty body) + ACME DNS-01 cert via Proxmox Datacenter → Certificates; works over WiFi today
12. **Boot-into-Gaming-Mode experiment** (gamescope + Sunshine capture — historically rocky; fallback autostart `steam -tenfoot`)
13. **Scheduled shutdown cron**: `qm shutdown 104` with active-session guard (check Sunshine sessions via API first, or mid-game yank)
14. **Emulators + Syncthing saves + RomM** for the unified Big Picture catalog
15. **Jellyfin iGPU (QSV/VAAPI)**: pass iGPU `/dev/dri` into Jellyfin LXC, hardware accel; may need iGPU multi-monitor ON in BIOS + dummy plug on motherboard HDMI if headless iGPU won't init
