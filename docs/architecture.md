# Architecture

## Hardware

| Component | Detail |
|---|---|
| Motherboard | ASRock (UEFI), VT-x and VT-d enabled |
| CPU | 4 threads |
| RAM | 16 GB DDR3 |
| Boot / VM storage | 500 GB SATA SSD (Proxmox + container disks) |
| Data drive | 4 TB HGST Ultrastar 7200 rpm HDD |
| Backup drive | 1 TB WD external USB drive (exFAT, readable on any computer) |
| GPU | NVIDIA GTX 1060 3 GB (Pascal) |
| NIC | Intel e1000e gigabit, wired to a switch |

## Software

- **Proxmox VE 9.2** (Debian 13 base, kernel 7.0), no-subscription update repository
- **Container templates:** Debian 13 standard, amd64
- **NVIDIA driver 580.196.07** (last branch that supports Pascal), installed with DKMS so it rebuilds on kernel updates

## Storage layout

```
SSD (local / local-lvm)
  Proxmox OS
  container root disks (thin provisioned)

4 TB HDD, ext4, Proxmox "Directory" storage named media -> /mnt/pve/media
  library/
    Shows/     TV series
    Movies/    films, one folder per title
    Music/     tagged music library (Artist/Album/Track)
    Family/    home videos and photos
  dump/        weekly Proxmox container backups (vzdump)
  _incoming/   staging area for files still being written (outside every library)

1 TB USB, exFAT -> /mnt/backup (mounted by UUID, nofail)
  Family/          nightly copy
  Music/           nightly copy
  proxmox-dump/    nightly copy of the weekly container backups
```

Why a `library/` subfolder: Proxmox creates its own folders (like `dump/`) at
the top of the storage, so keeping media one level down keeps the two apart.

Why `_incoming/`: Jellyfin watches the library folders in real time. Writing
large files into a staging folder first, then moving them (an instant rename on
the same filesystem), means Jellyfin never catalogs a half-written file.

## Containers

All containers are **unprivileged** (container root maps to an unprivileged
user on the host) and start automatically at boot.

| ID | Name | Resources | Key configuration |
|---|---|---|---|
| 100 | jellyfin | 4 cores, 4 GB RAM, 16 GB disk | Library mounted **read-only** at `/media`; NVIDIA device files passed through; Tailscale; `tailscale serve` HTTPS front door |
| 101 | files | 1 core, 512 MB RAM, 8 GB disk | Library mounted **read-write** at `/srv/media`; Samba with macOS compatibility module; Avahi (Bonjour) discovery |
| 102 | pihole | 1 core, 512 MB RAM, 4 GB disk | Pi-hole v6, Quad9 upstream; Tailscale with `--accept-dns=false` |
| 103 | apps | 4 cores, 6 GB RAM, 40 GB disk | `nesting=1,keyctl=1` for Podman; Cockpit web console; Tailscale |

### File ownership across containers

Unprivileged containers shift user IDs by 100000 (container UID 1000 = host
UID 101000). The library is owned by host UID/GID `101000`, which is the Samba
user inside `files`. Files are world-readable (`644` / `755`), so Jellyfin can
read everything while only the file-share container can write. Samba's
`create mask` and `directory mask` keep new files readable automatically.

## Networking

- **Home network:** every container and the host have DHCP reservations on the
  ISP router, so addresses never change. Each container has its own IP on the
  `vmbr0` bridge.
- **No inbound ports are open on the router.** SMB stays on the home network.
- **Remote access:** Tailscale runs inside the containers that need it
  (`jellyfin`, `pihole`, `apps`), not on the Proxmox host. Remote devices
  reach individual services, not the whole LAN or the hypervisor's admin UI.
- **Remote household:** a family member's own Tailscale account has the
  `jellyfin` machine shared with it, so their Fire TV sees only that one
  machine. Key expiry is disabled on long-lived devices.
- **HTTPS:** `tailscale serve --bg 8096` puts a Let's Encrypt certificate in
  front of Jellyfin on the tailnet name. Jellyfin's own HTTPS stays off, and
  `127.0.0.1` is listed as a known proxy so Jellyfin still sees each client's
  real address (which its remote-access restrictions rely on).
- **DNS filtering:** Tailscale's DNS settings point my own devices at Pi-hole's
  Tailscale address, giving ad and tracker blocking at home and away. The rest
  of the household keeps using the router's DNS and is unaffected.

## Media serving

- **Libraries:** Shows, Movies, Music, Family (home videos), each with
  per-user access. Family members see only the libraries assigned to them.
- **Transcoding:** NVIDIA NVENC on the GTX 1060. Verified in a transcode log:
  `Stream #0:0 -> #0:0 (h264 (native) -> h264 (h264_nvenc))`, with audio copied
  untouched.
- **Music:** tagged with MusicBrainz Picard (MusicBrainz IDs, cover art),
  synced lyrics stored as `.lrc` sidecar files, real-time library monitoring.
- **Clients:** Jellyfin app on Fire TV; Finamp on iPhone with CarPlay
  (transcoding to AAC for reliable background playback); Feishin on desktop.

## Monitoring and dashboard

- **Uptime Kuma** (Podman, host networking) checks Jellyfin's `/health`
  endpoint on both the LAN address and the Tailscale HTTPS address, plus
  Pi-hole, Proxmox, and Samba (TCP 445). Two Jellyfin checks separate "Jellyfin
  is down" from "the remote path is down."
- **Homepage** shows live widgets for Jellyfin, Pi-hole, Proxmox, and Uptime
  Kuma, each through its own credential.

## Backups

| What | How | When | Where |
|---|---|---|---|
| Family, Music | `rsync -rt` (no `--delete`) | nightly, 03:30 | USB drive |
| All containers | Proxmox vzdump, snapshot mode, zstd, keep last 4 | weekly, Sunday 02:00 | 4 TB HDD |
| Container backups | `rsync -rt` | nightly, 03:30 | USB drive |

The nightly job is a systemd service + timer (`Persistent=true`, so a missed
run happens at next boot). The script refuses to run if the USB drive isn't
mounted, which prevents it from silently filling the SSD. See
[configs/host](../configs/host).

Known gaps (no offsite copy, no RAID, restore not yet rehearsed) are tracked in
[security.md](security.md) and [roadmap.md](roadmap.md).
