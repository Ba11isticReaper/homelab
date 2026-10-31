# Build Log

A chronological record of what was built and why. Commands are shown where
they're the interesting part; full configs live in [configs/](../configs).

## Day 1: hypervisor, storage, and the media server

### Goal
Replace a paid music streaming subscription and serve a personal media
library to TVs at home and to my phone (including CarPlay) anywhere, without
paying for a media server license.

### Installer media
- Verified the Proxmox ISO's SHA-256 checksum against the published value
  before writing it.
- Converted the ISO to a raw image (`hdiutil convert -format UDRW`) and wrote
  it with `dd` to the USB stick's raw device (`/dev/rdiskN`).
- Identified the target disk with `diskutil list external` and checked its
  size and "external" location before running `dd`, after an initial pick
  turned out to be one of the Mac's internal system disks.

### Proxmox install
- Enabled VT-x and VT-d in the UEFI, booted the installer in UEFI mode, and
  installed to the SSD with ext4, leaving the 4 TB data drive untouched.
- Switched from the enterprise repository to the free no-subscription
  repository and applied all updates.

### Data drive
- Wiped the 4 TB drive (GPT) and created a Proxmox **Directory** storage
  (`media`, ext4) mounted at `/mnt/pve/media`.
- Created the library structure with brace expansion:
  `mkdir -p /mnt/pve/media/library/{Shows,Movies,Music,Family}`.

### Jellyfin container
- Created an unprivileged Debian 13 container and bind-mounted the library
  **read-only**: `pct set 100 -mp0 /mnt/pve/media/library,mp=/media,ro=1`.
- Downloaded and read Jellyfin's install script before running it, rather than
  piping it straight into a root shell.
- Configured libraries; disabled saving artwork and NFO files into media
  folders, since the mount is read-only.

### Network
- Reserved fixed addresses for the host and container on the ISP router.
- Installed Tailscale inside the Jellyfin container (adding `/dev/net/tun` to
  the container config) so only Jellyfin is reachable remotely.

### Data migration
- Mounted the old external drive **read-only** and copied the library with
  `rsync` inside `tmux`, so a dropped SSH session couldn't kill the transfer.
  Dry runs first to confirm where files would land.
- Copied family videos from the Mac to the server over Ethernet with `rsync`
  over SSH, keeping timestamps and skipping `.DS_Store` files.
- Fixed permissions so the unprivileged Jellyfin user could read everything.

### Users
- Created per-person Jellyfin accounts with access to specific libraries only,
  so family accounts see home videos and nothing else.

## Day 2: file sharing, backups, GPU, remote family, HTTPS, DNS filtering

### File sharing (CT 101)
- New unprivileged container with the library mounted **read-write**.
- Transferred ownership of the library to host UID/GID `101000` (the
  container's UID 1000) so the share's user can write.
- Samba with the `fruit` macOS compatibility module and Avahi for Bonjour
  discovery, so the library appears in Finder's sidebar.
- Masks set so every new file is readable by Jellyfin, removing a manual
  `chmod` step from the workflow.

### Nightly backup
- Mounted the USB drive by **UUID** in `/etc/fstab` with `nofail` and a short
  device timeout, so a missing drive can't block boot.
- Wrote `backup-family.sh`: `set -euo pipefail`, a `mountpoint` guard, and
  `rsync -rt` without `--delete`.
- Scheduled it with a systemd service and timer (03:30 nightly,
  `Persistent=true`), ran it once by hand, and verified sizes.

### GPU transcoding
- Blacklisted the `nouveau` driver and rebuilt the initramfs.
- Installed NVIDIA's 580.196.07 driver with `--dkms` (proprietary kernel
  module, required for Pascal).
- Made the GPU device files exist at every boot (module load list plus a udev
  rule) so the container can't fail to start for want of `/dev/nvidia-uvm`.
- Passed `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm`, and
  `/dev/nvidia-uvm-tools` into the Jellyfin container, then installed the
  **matching** user-space driver inside it with `--no-kernel-module`.
- Enabled NVENC in Jellyfin and confirmed GPU encoding in the FFmpeg transcode
  log while streaming over cellular.

### Remote household
- Shared only the Jellyfin machine with a family member's Tailscale account,
  installed Tailscale and Jellyfin on their Fire TV, and disabled key expiry.

### HTTPS
- Enabled HTTPS certificates in the Tailscale admin console (accepting that
  the machine name appears in public Certificate Transparency logs), then ran
  `tailscale serve --bg 8096`. Existing `http://` clients kept working.
- Added `127.0.0.1` as a Jellyfin known proxy so it still sees real client IPs.

### Container backups
- Weekly vzdump job for all containers (snapshot mode, zstd, keep last 4) to
  the `media` storage, plus a line in the nightly script copying them to USB.

### Pi-hole (CT 102)
- Installed Pi-hole v6 with Quad9 (filtered, DNSSEC) upstream.
- Tailscale with `--accept-dns=false` to avoid a DNS loop once Tailscale's DNS
  points at Pi-hole.
- Scoped to **my own devices** through Tailscale's DNS setting, not the
  router, so a server outage can't take down DNS for the household.

### Start on boot
- Found the file-share container had stayed stopped after a host reboot, and
  set `onboot` on every container.

## Day 3: music workflow, Podman host, monitoring, dashboard

### Music
- Turned on real-time monitoring for the music library.
- Fetched synced lyrics and exported them as `.lrc` sidecar files next to each
  track (after first confirming the music was backed up).
- Added the music library to the nightly backup and verified the copy with a
  checksum comparison (`rsync -rnci`).
- Fixed Finamp stopping playback when backgrounded by transcoding to AAC
  instead of streaming the original Opus files.

### Podman host (CT 103)
- Chose **Podman** over Docker (no root daemon). Rootful Podman inside an
  **unprivileged** container, with `nesting=1,keyctl=1`.
- Cockpit with the Podman plugin as the web UI; direct root login disabled,
  separate admin user with sudo.
- `podman-restart.service` so `restart: always` containers come back after a
  reboot (Podman has no daemon to do it).

### Uptime Kuma
- Deployed with Compose, then moved from the deprecated v1 image to the
  recommended `2` tag before adding any data.
- Switched to host networking after finding the container couldn't resolve
  Tailscale MagicDNS names that the container host could.

### Homepage dashboard
- Host networking, `HOMEPAGE_ALLOWED_HOSTS` restricted to the exact addresses
  used, secrets in a `chmod 600` `.env` file referenced as
  `{{HOMEPAGE_VAR_...}}`, and **no container socket** mounted.
- Proxmox widget uses a dedicated user and API token with the read-only
  **PVEAuditor** role and privilege separation.
- Verified each credential directly against its API with `curl` when a widget
  failed.

### Optical media workflow
- Staging folder pattern (`_incoming/`) for large files, TMDB naming
  conventions for movies and series, and an `extras/` folder for bonus
  features.
