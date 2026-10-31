# Security

## Principles applied

### Isolation
- **Every service runs in its own unprivileged LXC container.** Root inside a
  container maps to an unprivileged user on the host. This was visible in
  practice: when Cockpit's disk service tried to touch the host's physical
  drives from inside container 103, the kernel refused every write.
- **Nothing runs directly on the hypervisor** beyond Proxmox itself, the GPU
  driver, and the backup job.

### Least privilege
- **Jellyfin mounts the library read-only.** A compromised media server can
  read media but can't delete or encrypt it. Only the file-share container has
  write access.
- **Dashboard credentials are scoped:** the Proxmox widget uses a dedicated
  API token with the read-only `PVEAuditor` role and privilege separation, so
  a leaked token can't change anything.
- **No container-engine socket** is mounted into the dashboard. Homepage
  documents mounting it for auto-discovery; that would hand a web app
  root-equivalent control of every container, which a dashboard doesn't need.
- **Remote households see one machine.** Tailscale machine sharing exposes only
  the Jellyfin container to a family member's account, and their Jellyfin user
  sees only the libraries assigned to it.

### Minimal exposure
- **No ports forwarded on the router.** Remote access is outbound-initiated
  WireGuard via Tailscale.
- **SMB is LAN-only.** It was never designed for internet exposure.
- **Tailscale is installed per container,** not on the Proxmox host, so the
  hypervisor's admin interface isn't reachable from the tailnet.
- **Pi-hole answers all origins** only because nothing reaches it except the LAN
  and my tailnet. That setting would be unsafe with a port forward.
- **Declined:** a torrent client on the server (would publish the home IP to
  swarms and want an open port), Tailscale Funnel (public login page),
  router-wide Pi-hole DNS (a server outage would break the household's
  internet, including a work laptop).

### Secrets
- Credentials live in a `.env` file with mode `600`, referenced from config
  files as variables, so configs can be read and shared safely.
- `.env` is excluded from this repository by `.gitignore`.
- Secrets typed on the command line were prefixed with a space to keep them
  out of shell history.

### Supply chain
- **Verified the Proxmox ISO checksum** before installing.
- **Read install scripts before running them** (Jellyfin, Tailscale, Pi-hole,
  Docker/Podman tooling) instead of piping `curl` output straight into a root
  shell.
- **Full image names** (`docker.io/...`, `ghcr.io/...`) in Podman so an image
  can't be resolved from an unexpected registry.
- **Supported versions:** moved Uptime Kuma off its deprecated v1 tag before
  deploying it for real. Pinning a version prevents surprise upgrades but still
  requires moving to supported versions deliberately.
- **Third-party Jellyfin plugins:** refused to install a plugin build that
  didn't target the running Jellyfin version.
- Compose files are written from each project's official documentation, not
  copied from forum posts.

### Data protection
- Backups **never propagate deletions** (`rsync` without `--delete`), so a
  mistake on the server can't erase the backup copy.
- The backup script **refuses to run if the backup drive isn't mounted**.
- `set -euo pipefail` stops the script at the first error so a failed step
  never logs as success.
- A **frozen copy** of the music library was taken before running a tool that
  could rewrite every file, because the nightly job overwrites changed files.

## Threat model notes

- **Tailscale's coordination server** distributes public keys, so in theory a
  compromised coordination service could add a device to the tailnet. Traffic
  itself is end-to-end encrypted and never readable by Tailscale. Mitigations
  planned: MFA on the identity provider and **Tailnet Lock** (devices sign new
  nodes, removing the coordination server from the trust chain).
- **The identity login is the front door.** Whoever controls the account used
  to sign into Tailscale can add devices.
- **Certificate Transparency:** enabling Tailscale HTTPS publishes the machine
  name and tailnet ID in public CT logs. IPs and services stay private.
- **Shared tailnet access** currently allows all ports on the shared machine.

## Known gaps (backlog)

| Gap | Plan |
|---|---|
| Tailscale has no MFA, Tailnet Lock, or ACLs yet | Enable all three; restrict shared users to TCP 8096 / 443 on the Jellyfin node. Pending household sign-off. |
| SSH to the host uses root with a password | Key-based authentication, disable password login, use a non-root user for routine work |
| No offsite backup | Encrypted copy to cloud storage or a drive kept elsewhere (3-2-1 rule) |
| Single data drive, no redundancy | ZFS mirror when a second drive is available |
| Container restore not yet rehearsed | Test-restore a container from vzdump to a spare ID |
| Jellyfin and Pi-hole API keys carry full access | Both products lack read-only keys; kept in `.env`, dashboard Tailscale-only |
| Unneeded packages pulled in with Cockpit (ModemManager, udisks2) | Remove to reduce attack surface |
| Uptime Kuma alerts go through public ntfy.sh | Random topic name for now; self-host ntfy later |
