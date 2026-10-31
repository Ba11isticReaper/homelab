# Roadmap

## Security hardening
- [ ] Tailscale: MFA on the identity provider, Tailnet Lock, and ACLs limiting
      shared users to the Jellyfin ports
- [ ] SSH key authentication; disable password and direct root login
- [ ] Remove unneeded packages from the Podman container
- [ ] Self-hosted ntfy for alerts

## Resilience
- [ ] Rehearse a container restore from vzdump
- [ ] Offsite, encrypted backup copy (3-2-1)
- [ ] ZFS mirror for the data drive
- [ ] Planned reboot test: every container and service returns unattended

## Services (Podman, CT 103)
- [ ] SearXNG: private metasearch for my own devices over Tailscale
- [ ] beets: automated music tagging, art, genres, and lyrics from an inbox folder
- [ ] Immich: phone photo backup, with the GPU shared into Podman for
      face recognition and search
- [ ] Explo: weekly discovery playlists from ListenBrainz recommendations
- [ ] AudioMuse: audio-analysis based "sounds like" mixes
- [ ] multi-scrobbler: ListenBrainz scrobbling until a Jellyfin plugin
      supports the current release

## Hardware
- [ ] Swap the GTX 1060 for a GTX 1660 (Turing NVENC: better quality per
      bitrate, 6 GB VRAM for ML workloads), same 580 driver branch

## Media
- [ ] Overnight HEVC compression job for large video files (CPU x265)
- [ ] Episode thumbnails generated from title-card frames via chapter markers

## Related project
- A JavaFX front end for rsync transfers with verification and safe batch
  renaming (separate repository).
