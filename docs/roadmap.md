# Roadmap

## Security hardening
- [X] Tailscale: MFA on the identity provider, Tailnet Lock, and ACLs limiting
      shared users to the Jellyfin ports
- [ ] SSH key authentication; disable password and direct root login
- [X] Remove unneeded packages from the Podman container

## Resilience
- [ ] Rehearse a container restore from vzdump
- [ ] Offsite, encrypted backup copy (3-2-1)
- [X] ZFS mirror for the data drive
- [X] Planned reboot test: every container and service returns unattended

## Services (Podman, CT 103)
- [X] SearXNG: private metasearch for my own devices over Tailscale
- [X] `tailscale serve` HTTPS for the apps container (also covers the
      X-Forwarded-For warning in searxng logs and the remote-path Uptime Kuma
      monitor)
- [X] Curate SearXNG engines (DuckDuckGo, Bing, Wikipedia, Google; removes
      the recurring ahmia/torch load errors)
- [ ] beets: automated music tagging, art, genres, and lyrics from an inbox folder
- [ ] Immich: phone photo backup, with the GPU shared into Podman for
      face recognition and search
- [ ] Explo: weekly discovery playlists from ListenBrainz recommendations
- [ ] AudioMuse: audio-analysis based "sounds like" mixes
- [ ] multi-scrobbler: ListenBrainz scrobbling until a Jellyfin plugin
      supports the current release
      
## Follow-ons discovered during the SearXNG build

- [X] Restrict the raw `:8888` port bind to loopback only, now that
      `tailscale serve` is the front door (reduces exposed surface)
- [X] Evaluate Orion (Kagi) as an alternative iOS browser — native WebKit,
      supports desktop extensions, prompts for search engine on first launch
- [ ] Self-host ntfy (currently relaying through public ntfy.sh; also carries
      the unresolved iOS lock-screen push delivery issue)
- [X] Vaultwarden on CT 103 — password/passkey autofill replacing iCloud
      Keychain; requires backup integration designed before go-live

## Hardware
- [X] Swap GTX 1060 for a GTX 1660 (Turing NVENC: better quality per
      bitrate, 6 GB VRAM for ML workloads), same 580 driver branch

## Media
- [ ] Overnight HEVC compression job for large video files (CPU x265)
- [ ] Episode thumbnails generated from title-card frames via chapter markers

## Related project
- [ ] A JavaFX front end for rsync transfers with verification and safe batch
  renaming (separate repository).
- [X] Expose Vaultwarden through `tailscale serve` on CT 103 (the Jellyfin HTTPS
  pattern) rather than widening the port bind.
- [X] Finish the music directory migration and edit the nightly backup script's
  includes/excludes; verify sizes with `du -sh` before and after.
- [ ] Write a `pull-configs.sh` on the Mac that gathers all four CTs' configs in
  one command.
- [ ] Confirm Podman's network driver honors loopback-only port binds as
  expected.
