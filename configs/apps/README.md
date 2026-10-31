# Podman host (CT 103 "apps")

```
apt install -y podman podman-compose cockpit cockpit-podman
systemctl enable --now podman-restart.service   # restart policy "always" after reboot
```

- Rootful Podman inside an **unprivileged** LXC container. Container root is
  already an unprivileged user on the Proxmox host; rootless-inside-LXC would
  complicate storage and GPU access for later stacks.
- Cockpit (`https://<apps-ip>:9090`) as the web UI. Direct root login is
  blocked; a separate admin user in the `sudo` group signs in.
- One folder per stack under `/opt/stacks/`, each with its own
  `compose.yaml`, managed with `podman-compose up -d` / `down`.
- Full image names (`docker.io/...`, `ghcr.io/...`); Podman doesn't assume a
  default registry.

## Proxmox read-only token for the dashboard

Datacenter > Permissions:

1. Group `api-ro-users`; group permission on `/`, role **PVEAuditor**, propagate.
2. User `api@pam` in that group.
3. API token `api@pam!homepage` with **privilege separation**.
4. API token permission on `/`, role **PVEAuditor**, propagate.

PVEAuditor can view everything and change nothing; privilege separation means
the token gets only what's granted to it directly.
