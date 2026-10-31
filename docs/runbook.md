# Runbook

Common operations and recovery steps. Run on the Proxmox host (`root@pve`)
unless noted.

## Where am I?

| Prompt | Location |
|---|---|
| `root@pve` | Proxmox host |
| `root@jellyfin` | CT 100 |
| `root@files` | CT 101 |
| `root@pihole` | CT 102 |
| `root@apps` | CT 103 |

`pct` only exists on the host. `pct enter <id>` opens a shell in a container;
`exit` leaves it.

## Status at a glance

```
pct list
for id in 100 101 102 103; do echo -n "$id: "; pct exec $id -- hostname -I; done
```

Or open the Homepage dashboard / Uptime Kuma.

## Backups

```
tail -8 /var/log/backup-family.log          # last runs: START / DONE
systemctl list-timers | grep backup         # next and last nightly run
ls -lh /mnt/pve/media/dump/                 # weekly container backups
systemctl start backup-family.service       # run the nightly job now
```

Verify a copy byte for byte (no output means identical):

```
rsync -rnci --exclude='.DS_Store' /mnt/pve/media/library/Music/ /mnt/backup/Music/
```

### Restore a container from backup

Not yet rehearsed; test on a spare ID first.

```
pct restore 999 /mnt/pve/media/dump/vzdump-lxc-100-<date>.tar.zst --storage local-lvm
```

Bind mounts (media folders) aren't inside container backups, so re-add the
`mp0` line from `configs/lxc` if needed.

## Adding media

1. Copy into `_incoming/` on the SMB share (`smb://<files-ip>/media`), or rsync
   to `<user>@<files-ip>:/srv/media/_incoming/`.
2. Rename to the conventions below.
3. Move into the library folder (instant on the same share).
4. Jellyfin picks it up via real-time monitoring, or run a library scan.

```
Movies/Title (Year)/Title (Year).mkv
Movies/Title (Year)/extras/Featurette.mkv
Shows/Show (Year)/Season 01/Show (Year) - S01E01 - Episode Title.mkv
Shows/Show (Year)/Season 00/...            specials, numbered as on TMDB
Music/Album Artist/Album/01 Title.ext      tagged with MusicBrainz Picard
Music/Album Artist/Album/01 Title.lrc      synced lyrics sidecar
```

Avoid `pt1`/`part 2`/`disc 2` in filenames unless the files really are one
item split in parts; Jellyfin stacks them into a single entry.

## Updates

```
apt update && apt full-upgrade                         # host (or the web UI)
pct exec 100 -- bash -c "apt update && apt full-upgrade -y"   # a container
```

Podman stacks (inside CT 103):

```
cd /opt/stacks/<app>
podman-compose pull && podman-compose up -d
```

After a host kernel update, before relying on GPU transcoding:

```
dkms status        # nvidia should be "installed" for the new kernel
nvidia-smi         # host sees the GPU
pct exec 100 -- nvidia-smi
```

The container's user-space driver must match the host driver version exactly.

## Common problems

| Symptom | First checks |
|---|---|
| Remote playback fails, home works | Toggle Tailscale on the client device; check the "remote" Uptime Kuma monitor |
| Jellyfin scan stuck | Restart Jellyfin (`pct exec 100 -- systemctl restart jellyfin`), rescan |
| Jellyfin web UI fine, phone app odd | Force-quit the app and start a fresh queue |
| Share missing in Finder | `pct exec 101 -- systemctl status smbd avahi-daemon`; connect with Cmd+K `smb://<files-ip>/media` |
| Container won't start | `pct start <id> --debug`, read the ERROR lines |
| GPU container won't start after reboot | `ls -l /dev/nvidia*` on host; `nvidia-modprobe -c0 -u` creates the UVM devices |
| Backup failed | `tail /var/log/backup-family.log` for rsync's own error |
| Site broken by ad blocking | Pi-hole Query Log, allow the domain, or pause blocking for 5 minutes |
| Pages won't load on my devices | Server/Pi-hole down: turn Tailscale off on that device temporarily |
| Dashboard widget error | `podman logs --tail 40 <homepage-container>`; test the credential with `curl` |

## Logs

```
journalctl -u <service> -n 40 --no-pager       # any systemd service
pct exec 100 -- ls -t /var/log/jellyfin/      # Jellyfin logs, newest first
podman logs --tail 40 <container>              # Podman apps, inside CT 103
```
