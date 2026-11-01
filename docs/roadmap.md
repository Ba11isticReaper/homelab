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

- [ ] Route SearXNG's outbound requests through a VPN or Tor exit, so upstream
      engines see an IP that is not my home address (closes the single-user
      instance attribution gap)
- [ ] Restrict the raw `:8888` port bind to loopback only, now that
      `tailscale serve` is the front door (reduces exposed surface)
- [ ] Evaluate Orion (Kagi) as an alternative iOS browser — native WebKit,
      supports desktop extensions, prompts for search engine on first launch
- [ ] Self-host ntfy (currently relaying through public ntfy.sh; also carries
      the unresolved iOS lock-screen push delivery issue)
- [ ] Vaultwarden on CT 103 — password/passkey autofill replacing iCloud
      Keychain; requires backup integration designed before go-live

    

## Hardware
- [ ] Swap the GTX 1060 for a GTX 1660 (Turing NVENC: better quality per
      bitrate, 6 GB VRAM for ML workloads), same 580 driver branch

## Media
- [ ] Overnight HEVC compression job for large video files (CPU x265)
- [ ] Episode thumbnails generated from title-card frames via chapter markers

## Related project
- A JavaFX front end for rsync transfers with verification and safe batch
  renaming (separate repository).

