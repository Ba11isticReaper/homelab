# NVIDIA GPU setup (host + Jellyfin container)

GTX 1060 (Pascal). NVIDIA's 580 branch is the last to support Pascal, and
Debian's packaged driver is older, so the official `.run` installer is used.

## Host

```
apt install -y build-essential dkms proxmox-default-headers

# Keep the open-source nouveau driver from claiming the card
printf 'blacklist nouveau\noptions nouveau modeset=0\n' > /etc/modprobe.d/blacklist-nouveau.conf
update-initramfs -u -k all
reboot

# Proprietary kernel module (required for Pascal), rebuilt automatically by DKMS
./NVIDIA-Linux-x86_64-580.196.07.run --dkms
nvidia-smi
```

Make sure all device files exist at boot (the UVM devices are otherwise created
on first use, and a container that expects them would fail to start):

```
printf 'nvidia\nnvidia_uvm\n' > /etc/modules-load.d/nvidia.conf
```

`/etc/udev/rules.d/70-nvidia.rules`:

```
KERNEL=="nvidia", RUN+="/usr/bin/nvidia-smi -L"
KERNEL=="nvidia_uvm", RUN+="/usr/bin/nvidia-modprobe -c0 -u"
```

## Jellyfin container

Device passthrough (see `configs/lxc/100-jellyfin.conf`):

```
pct set 100 -dev0 /dev/nvidia0,mode=0666 -dev1 /dev/nvidiactl,mode=0666 \
            -dev2 /dev/nvidia-uvm,mode=0666 -dev3 /dev/nvidia-uvm-tools,mode=0666
```

User-space driver only, same version as the host (the container shares the
host kernel, so no kernel module):

```
pct push 100 NVIDIA-Linux-x86_64-580.196.07.run /root/NVIDIA-Linux-x86_64-580.196.07.run
pct enter 100
/root/NVIDIA-Linux-x86_64-580.196.07.run --no-kernel-module
nvidia-smi
```

Jellyfin: Dashboard > Playback > Transcoding > NVIDIA NVENC. Hardware decode for
H264, HEVC, MPEG2, VC1, VP9 (and 10-bit variants); AV1 off (not supported on
Pascal).

Verification from a transcode log:

```
Stream #0:0 -> #0:0 (h264 (native) -> h264 (h264_nvenc))
Stream #0:1 -> #0:1 (copy)
```
