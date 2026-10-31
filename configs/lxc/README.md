# Container configuration excerpts

Relevant lines from `/etc/pve/lxc/<id>.conf` on the Proxmox host. Network
interface lines (MAC addresses) are omitted. All containers are unprivileged
Debian 13 (amd64) and start at boot.

## 100-jellyfin.conf

```
unprivileged: 1
onboot: 1
cores: 4
memory: 4096
mp0: /mnt/pve/media/library,mp=/media,ro=1
dev0: /dev/nvidia0,mode=0666
dev1: /dev/nvidiactl,mode=0666
dev2: /dev/nvidia-uvm,mode=0666
dev3: /dev/nvidia-uvm-tools,mode=0666
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

- `ro=1`: the media server can read the library but never modify it.
- `devN`: GPU device files for NVENC transcoding.
- The last two lines give the container a TUN device for Tailscale.

## 101-files.conf

```
unprivileged: 1
onboot: 1
mp0: /mnt/pve/media/library,mp=/srv/media
```

Read-write mount. The library is owned by host UID/GID 101000 (container
UID 1000, the Samba user).

## 102-pihole.conf

```
unprivileged: 1
onboot: 1
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

Tailscale runs with `tailscale up --accept-dns=false` to avoid a DNS loop.

## 103-apps.conf

```
unprivileged: 1
onboot: 1
features: keyctl=1,nesting=1
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

- `nesting=1`: lets Podman run containers inside this container.
- `keyctl=1`: kernel keyring access that container runtimes need in an
  unprivileged container.
