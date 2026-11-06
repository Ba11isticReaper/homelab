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
  
## SearXNG metasearch (CT 103, build session 4)

### Goal

Replace dependence on a commercial search engine with a self-hosted metasearch instance running on my own hardware, reachable only from my own devices over Tailscale. Listed on the roadmap as: *"SearXNG: private metasearch for my own devices over Tailscale."*

### Why this one mattered

Search is the highest-value data stream I produce. Before this build, every query went to a single provider along with my IP, device characteristics, and account linkage where applicable. SearXNG breaks the link between me as a person and my search history: the server sends queries upstream, strips identifying headers, randomizes user agents, and returns aggregated results. No account, no cookie continuity, no cross-site profile.

Honest limitation recorded for future me: this is a single-user instance, so all upstream queries originate from one home IP. Upstream engines still see "someone at this address searched these things" — they just cannot attribute it to a person or device. Routing SearXNG's outbound traffic through a VPN or Tor would close that gap. Added to roadmap.

### Stack

First multi-container stack on the Podman host — two services on a compose-internal network.

- `docker.io/searxng/searxng:2026.10.30-ffa88e3ba` (pinned; tag verified by pulling the image directly)
- `docker.io/valkey/valkey:8-alpine` — cache. Publishes **no ports**; reachable only from searxng over the stack network.

Valkey replaced Redis in SearXNG's own tooling (Redis license change in 2024; the project moved to the Valkey fork). The `redis:` key in settings is deprecated in favor of `valkey:`. Not an optional bolt-on — it is part of the standard two-service shape now.

### Configuration decisions

- **`use_default_settings: true`** — inherit the image's built-in config and override only what is listed. Avoids hand-maintaining an engine list.
- **`server.limiter: false`** — the limiter is abuse protection for public instances. It requires Valkey plus a reverse proxy passing `X-Forwarded-For`/`X-Real-IP`. Private single-user instance behind Tailscale has no abuse surface. Off.
- **`server.image_proxy: true`** — result thumbnails are fetched by the server rather than my browser, so the sites hosting those images never see my device request them.
- **`search.autocomplete: ""`** — disabled. The default forwards **partial keystrokes** to DuckDuckGo's suggestion API, not just completed queries. Partial queries are often more revealing than the final one. This was the largest remaining leak in the search path and is now closed.
- **`use_default_settings.engines.keep_only`** — curated engine list instead of the full default set. Rationale: every enabled engine receives every query. Running the default set means dozens of providers see my search terms; running four means four do. Kept: `duckduckgo`, `bing`, `google`, `wikipedia`.

### Secret handling — first use of the `.env` bridge for a Podman app

Established pattern: configs stay readable and committable, secrets live in a `600` `.env`.

- `openssl rand -hex 32` generates the key
- Stored as `SEARXNG_SECRET` in `/opt/stacks/searxng/.env` (mode `600`)
- Compose substitutes `${SEARXNG_SECRET}` at container creation
- SearXNG's documented behavior: `server.secret_key` **is overwritten by** `${SEARXNG_SECRET}`. Environment takes precedence over `settings.yml`, which takes precedence over built-in defaults.
- Verified end to end with `podman exec searxng printenv SEARXNG_SECRET`

Result: `settings.yml` contains only a placeholder (`"unused-set-via-env"`) and is safe to commit. The real secret never touches a tracked file.

Correction worth recording: I initially told myself this env-var path did not exist and planned to fall back to keeping `settings.yml` out of git entirely. That was wrong — it is a documented, first-class feature. Verify before retreating to a worse pattern.

### Exposure

Published on port `8888`, which binds all of CT 103's interfaces — LAN and tailnet alike. Tailnet-only access was the goal; the port bind delivered it as a side effect. LAN devices can also reach it, which was an accepted trade rather than an oversight (Pi-hole remains the only service intentionally answering on the LAN).

### Incident: crash loop from a fabricated mount

See `troubleshooting.md` for the full writeup. Short version: podman-compose started before `settings.yml` existed, Podman fabricated an empty **directory** at the bind-mount path, and the container crash-looped on `"/etc/searxng/settings.yml" is not a valid file`. Root cause turned out to be one step earlier than the directory — a `.yaml` / `.yml` filename typo in nano.

### Client migration (iPhone)

Safari on iOS cannot use a custom search engine. The Settings → Search → Search Engine list is a fixed menu, and there is no import mechanism. This is unique among major browsers and is directly tied to the revenue from the default search slot.

Switched to **Firefox for iOS**:

- Telemetry and studies toggles off; no Mozilla account (so no Sync identifiers exist at all)
- SearXNG added as a custom search engine: `https://apps.<tailnet>.ts.net/search?q=%s`
- Set as default search engine, then Firefox set as the system default browser

Note: every browser on iOS outside the EU is WebKit underneath, so "Firefox on iPhone" is WebKit with Firefox's UI and settings. The differences between iOS browsers live in interface and control, not engine.

Considered and rejected: **Zen Browser** — desktop only, no iOS or Android build, and no published plans for one. (An unrelated app of a similar name exists on the App Store.) **Orion** remains an option to evaluate later; it is a native WebKit browser that can run desktop extensions and asks for a search engine on first launch.

### HTTPS via `tailscale serve`

Activated `tailscale serve --bg 8888` on CT 103, giving the machine a real Let's Encrypt certificate and proxying HTTPS to `127.0.0.1:8888`.

Accepted trade, consistent with the Jellyfin machine: certificate issuance publishes the machine name into public Certificate Transparency logs. Machine names become public; IPs and services stay private.

`SEARXNG_BASE_URL` updated to the HTTPS hostname with **no port** — serve listens on 443 externally and hands off to 8888 internally, so including `:8888` would make every generated link wrong. Required a full `podman-compose down && up -d`, since environment values are read only at container creation.

Verified on the worst-case path: iPhone on cellular, WiFi off, Tailscale on — padlock present, search returns results.

### Conceptual trap discovered: MagicDNS is not `tailscale serve`

Worth recording because I fell into it. I believed CT 103 was already serving HTTPS because I was reaching `apps.<tailnet>.ts.net` in the browser. It was not.

- **MagicDNS** is a naming feature. It maps `apps.<tailnet>.ts.net` → the machine's `100.x` address. Tailnet-wide, always on. Gives a *name*, no encryption.
- **`tailscale serve`** is an HTTPS gatekeeper. Terminates TLS with a real certificate and proxies to a local port. Per-machine, per-port, opt-in.

`tailscale serve status` on CT 103 returned `No serve config` — proving no HTTPS existed — while the hostname still resolved and worked over plain HTTP. "The name resolves" is not the same claim as "HTTPS exists." Query the system rather than trusting memory.

### Monitoring

Two monitors, mirroring the Jellyfin pattern (process health vs. path health):

- **`SearXNG (LAN)`** — HTTP check against `http://127.0.0.1:8888`. Kuma runs host-networked, so loopback tests the process itself, not the network path.
- **`SearXNG (remote)`** — HTTPS check against `https://apps.<tailnet>.ts.net`. Tests the path my phone actually uses.

Both verified by stopping and starting the container to watch them flap and recover. A monitor never observed firing is a monitor that cannot be trusted.

Notification delivery caveat: Kuma → ntfy reaches the topic successfully (messages appear in the ntfy app), but pushes do not reach the iOS lock screen. Parked until ntfy is self-hosted, since the push relay is the suspected layer.

### Known cosmetic log noise

- `ahmia: can't register engine` / `torch: can't register engine` — Tor hidden-service engines failing to load outside a Tor setup. Resolved by engine curation (neither is in `keep_only`).
- `missing config file: /etc/searxng/limiter.toml` — bot detection announcing it has no config. Limiter is off by design.
- `X-Forwarded-For nor X-Real-IP header is set!` — see `troubleshooting.md`. Expected, inert, no fix warranted.

## Day 4: password manager, config syncing, and taming the backup job

### Vaultwarden on CT 103

Goal: replace the last remaining cloud service — the password manager — with a
self-hosted one, completing the project goal of zero paid cloud dependencies.

Chosen shape, and why each line matters:

- Port published as `127.0.0.1:8222:80` — loopback only. Nothing on the LAN or
  tailnet can reach the web UI directly. External access will follow the
  Jellyfin pattern: `tailscale serve` terminating HTTPS at the Tailscale layer
  and forwarding to loopback.
- `SIGNUPS_ALLOWED=false` — even if reachability changes later, strangers
  cannot register accounts.
- Image pinned to `docker.io/vaultwarden/server:1.37.4` — no surprise upgrades.
- `DOMAIN` and `ADMIN_TOKEN` come from a `.env` file on the server, never from
  the repo. The compose file is safe to publish precisely because it contains
  no secrets; the `.env` beside it is not.

### Pulling live configs into the repo

The repo lives on the Mac; the live configs live inside the containers, which
have no users or SSH. The bridge is a one-line pipe through the Proxmox host,
which can reach into any container without a login inside it:

    ssh root@pve-host "pct exec 103 -- cat /opt/stacks/vaultwarden/compose.yaml" \
      > ~/Documents/homelab/configs/apps/vaultwarden/compose.yaml

Authorization chain: the Mac SSHes into the PVE host as root, the host runs
`pct exec` as root, and the file streams back over the same connection.
Reversed, the same pipe pushes a repo file back into a container on deploy.

### Music library split

Problem: one shared `Music` library means one person's shuffle is everyone's
shuffle — Sinatra surfacing between Avicii and ADELA.

Fix: sibling directories per audience (`My Music`, `Family Music`,
`Guest Music`), each mounted into Jellyfin as a separate library so the
library boundary is the persona boundary. Backup behavior follows directory
boundaries: the parent `music` tree is included in the nightly sync; bulk,
disposable media stays outside it so the 1 TB backup target does not fill
with shows. (Backup script excludes to be documented in `configs/host/` once
edited.)
