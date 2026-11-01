# Troubleshooting Log

Real incidents from the build, each written as symptom, investigation, root
cause, fix, and lesson.

---

## 1. Server unreachable from the whole network

**Symptom:** Mid-transfer, SSH dropped with "host is down." No device in the
house could reach the server or Jellyfin, though the server's NIC link light
was flashing.

**Investigation (bottom-up):**
- On the server console: `uptime` showed no reboot, so the transfer was likely
  still running in `tmux`.
- `dmesg` showed the Intel e1000e driver healthy: `NIC Link is Up 1000 Mbps
  Full Duplex`, no hang messages.
- `ip -br addr` and `ip route` showed the correct address and default gateway.
- `ip neigh` showed the router as `STALE`; from the Mac, `arp -a` showed the
  server as `(incomplete)`, meaning nothing answered at layer 2.

**Root cause:** The switch's uplink cable to the router has a broken latch and
had popped out. The server's link to the switch was fine, but the switch was
cut off from the rest of the network.

**Fix:** Reseated the cable. The transfer had kept running inside `tmux` and
finished normally.

**Lesson:** Work up from layer 1. Link up plus a correct IP config plus no ARP
replies narrowed it to the physical path one hop away.

---

## 2. Container wouldn't start: pre-start hook failed

**Symptom:** `pct start 100` failed with `lxc.hook.pre-start ... exited with
status 2`.

**Investigation:** `pct start 100 --debug` showed `directory
'/mnt/pve/library' does not exist`.

**Root cause:** A typo in the bind-mount path (`/mnt/pve/library` instead of
`/mnt/pve/media/library`). Proxmox validates mount sources before start.

**Fix:** Re-ran `pct set` with the correct path.

**Lesson:** `--debug` turns a generic failure into a specific one. Tab
completion prevents path typos.

---

## 3. Brace expansion created stray directories

**Symptom:** `mkdir -p /mnt/pve/media/library{Shows, Movies, Music, Family}`
didn't create the expected folders.

**Root cause:** The shell splits on spaces **before** brace expansion, so the
command created four literal names like `library{Shows,` and `Movies,`. The
missing `/` before `{` would also have glued names together.

**Fix:** Removed the strays with `rmdir` (which refuses to delete non-empty
directories), then used
`mkdir -p /mnt/pve/media/library/{Shows,Movies,Music,Family}`.

**Lesson:** Preview expansions with `echo` before running destructive or
creating commands.

---

## 4. Finder copies to the SMB share failed (error -8062)

**Symptom:** Dragging folders onto the Samba share failed with Finder error
-8062. Permissions and a direct write test as the share user both succeeded.

**Root cause:** A server-side `veto files = /.DS_Store/` rule. Finder copies
each folder's hidden `.DS_Store` file, the server refused it, and Finder
aborted the entire copy.

**Fix:** Removed the veto rule and stopped the Mac from writing `.DS_Store`
files to network volumes:
`defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true`.

**Lesson:** A rule that looks tidy on the server can break the client. The fix
belonged on the client side.

---

## 5. fstab parse error

**Symptom:** `mount -a` reported `unknown filesystem type '0'`, then
`parse error at line 1`.

**Investigation:** `cat -n /etc/fstab` showed a fragment of the new entry
pasted onto the front of line 1, ahead of the comment.

**Fix:** Backed up the file (`cp /etc/fstab /etc/fstab.bak`), deleted line 1
with `sed -i '1d'`, and validated with `findmnt --verify` before mounting.

**Lesson:** Never reboot with an unverified fstab. Always pair a new entry
with `nofail` and run `findmnt --verify` after every edit.

---

## 6. systemd service failed with 203/EXEC

**Symptom:** The backup service failed with status `203/EXEC` and "Unable to
locate executable," but the script existed at the exact path.

**Investigation:** Ruled out hidden characters with
`ls --quoting-style=c` and `cat -A` on the filename, the `ExecStart=` line,
and the shebang. `ls -l` then showed `-rw-r--r--`.

**Root cause:** The script wasn't executable. `chmod +x` had run before the
file was saved.

**Fix:** `chmod +x /usr/local/bin/backup-family.sh`.

**Lesson:** Check permissions early. Error wording can point somewhere else
entirely.

---

## 7. Backup script stopped before finishing

**Symptom:** After adding a third `rsync` line, the service exited with status
1 and no `DONE` in the log.

**Investigation:** The script logs rsync's own errors. The log showed
`rsync: --exclue=.DS_Store: unknown option`. After the fix, an old error entry
at the top of the log caused brief confusion until the timestamps were
compared.

**Root cause:** A typo (`--exclue`). Because of `set -euo pipefail`, the script
stopped at the failing line instead of reporting a false success.

**Fix:** `sed -i 's/--exclue=/--exclude=/'`, rerun, verify with
`rsync -rnci` (checksum dry run, no output means identical).

**Lesson:** The application log explains *why*; systemd only says *that* it
failed. Read timestamps before trusting a log line.

---

## 8. Services down after a host reboot

**Symptom:** The file share vanished from Finder after the host was rebooted
for GPU work.

**Root cause:** Containers don't start at boot unless configured to. Only the
container started by hand during the GPU work had come back.

**Fix:** `pct set <id> -onboot 1` for every container, plus
`systemctl enable smbd avahi-daemon` inside the file-share container.

**Lesson:** Test a full reboot deliberately rather than discovering this
during a power outage.

---

## 9. Remote streaming stopped after server restarts

**Symptom:** After several container restarts, the phone couldn't reach
Jellyfin over Tailscale, even though Jellyfin answered locally.

**Investigation:** From inside the container, `curl` to Jellyfin's Tailscale IP
returned `Healthy`, and `tailscale ping` to the phone succeeded. The iOS
Tailscale app showed a MagicSock (path discovery) warning.

**Root cause:** The phone's Tailscale client had lost its path to the restarted
node and hadn't rebuilt it.

**Fix:** Re-checking the connection in the Tailscale app restored the path.

**Lesson:** Prove each hop separately. Later, a second Uptime Kuma monitor on
the Tailscale HTTPS address was added so "Jellyfin down" and "remote path down"
look different at a glance.

---

## 10. Monitoring container couldn't resolve Tailscale names

**Symptom:** Uptime Kuma showed the Tailscale HTTPS check as down, while `curl`
to the same URL from the container host succeeded.

**Investigation:** `podman exec <container> getent hosts <name>.ts.net`
returned nothing.

**Root cause:** The Podman container had its own network namespace and DNS,
which didn't include Tailscale's MagicDNS resolver on the host.

**Fix:** `network_mode: host` for the monitoring container.

**Lesson:** Container networking is a separate environment. Test from inside
the container, not just the host it runs on. Host networking is a reasonable
trade for a tool whose job is reaching other services.

---

## 11. Dashboard widget authentication failure

**Symptom:** Homepage's Pi-hole widget reported "failed to authenticate."

**Investigation:**
- Logged into Pi-hole's API directly with `curl -X POST .../api/auth`: the app
  password returned `"valid":false`, the normal login returned `true`.
- `pihole-FTL --config webserver.api.app_pwhash` showed an app password hash
  was stored.

**Root cause:** The copied app password didn't match the one Pi-hole had
saved.

**Fix:** Generated a new app password, copied it with the copy button, applied
it, tested it with `curl` immediately, then updated `.env` and restarted the
stack (env files are only read at container start).

**Lesson:** Test credentials against the API directly to separate "wrong key"
from "app isn't reading the key."

---

## 12. Media server stopped while adding GPU devices

**Symptom:** Music stopped mid-stream, and `pct push` failed with "can only
push files to a running CT."

**Root cause:** Adding device passthrough entries stopped the running
container.

**Fix:** Started the container, then copied the driver installer in and
installed the user-space driver with `--no-kernel-module`, matching the host's
driver version exactly.

**Lesson:** Hardware-level container changes can restart the container. Plan
them for a quiet moment.

---

## 13. Installer run on the wrong machine

**Symptom:** The Pi-hole installer offered `vmbr0` and `veth100i0` as network
interfaces instead of `eth0`.

**Root cause:** The commands had been run on the Proxmox host, not inside the
new container. `vmbr0` and `veth*` exist only on the host.

**Fix:** Cancelled at the interface prompt, confirmed nothing was installed
(`which pihole`, no Pi-hole directories), removed the script, and checked that
the host's package upgrade hadn't left the GPU driver unbuilt (`dkms status`).

**Lesson:** Read the prompt (`root@pve` vs `root@<container>`) before every
command. Unfamiliar output is a signal to stop.

---

## 14. Background playback stopping on iPhone

**Symptom:** Music faded out whenever the phone locked or the app went to the
background, even with the phone unlocked.

**Investigation:** Not network related (Tailscale stayed up). A downloaded
AAC track kept playing; streamed originals didn't.

**Root cause:** The client's handling of directly streamed Opus files in the
background.

**Fix:** Transcode to AAC in the client settings, then start a fresh queue
(queued tracks keep the settings they were loaded with).

**Lesson:** Settings may only apply to newly loaded items; retest from a clean
state.

---

## 15. Selecting the right architecture

**Symptom:** The container creation summary listed
`debian-13-standard_..._arm64.tar.zst`.

**Root cause:** The ARM64 template had been downloaded, likely because the
admin workstation is an Apple Silicon Mac. The server is x86-64.

**Fix:** Downloaded the amd64 template and removed the ARM one before creating
the container.

**Lesson:** Review the confirmation screen. Architecture mismatches fail in
confusing ways later.

## Incident #N — SearXNG crash loop from a fabricated bind mount

**Date:** 2026-10-31
**Component:** CT 103 / `/opt/stacks/searxng`

**Symptom**

The `searxng` container appeared in `podman ps` at one moment and produced `Error: can only start exec sessions when their container is running: container state improper` the next. Logs repeated: "... "/etc/searxng/settings.yml" does not exist, creating from template... cp: '/etc/searxng/settings.yml' is a directory sed: can't move '/etc/searxng/settings.ymlCCjD9j' to '/etc/searxng/settings.yml': Is a directory !!! ERROR !!! "/etc/searxng/settings.yml" is not a valid file, exiting..."

`restart: always` meant it restarted, failed, and restarted indefinitely — a crash loop that looked intermittently "up" when sampled.

**Investigation**
ls -la /opt/stacks/searxng

Returned two adjacent lines that explained everything:
-rw-r--r-- 1 root root 147 Oct 31 21:40 settings.yaml drwxr-xr-x 2 root root 4096 Oct 31 21:40 settings.yml

A real 147-byte file named `settings.yaml`, and an empty **directory** named `settings.yml`.

**Root cause**

Two mistakes compounding.

1. The settings file was saved as `settings.yaml` — a one-letter filename typo in nano. YAML blesses both extensions, so the file was valid; it simply was not the name the compose file mounted.
2. `podman-compose up -d` ran while `./settings.yml` did not exist. Asked to bind-mount a single file that is absent, Podman **fabricates an empty directory** at that path so the mount has a target. The container then found a directory where it expected a file.

**Fix**

podman-compose down rmdir settings.yml # refuses to delete anything non-empty — deliberate mv settings.yaml settings.yml ls -la # confirm: one file, leading dash, no 'd' podman-compose up -d

**Verification**

Version banner in the logs with no ERROR following it, `podman exec searxng printenv SEARXNG_SECRET` printing the hex key, `curl -I http://127.0.0.1:8888` returning 200.

**Lesson**

Create every bind-mounted file **before** starting a stack. A mount target that exists after a "successful" startup is not validation — it may be a fabrication. And when a container insists a path is not a valid file, run `ls -la` on it before theorizing: the leading `d` answers the question in one character.

---

## Incident #N+1 — `X-Forwarded-For` warning survives the fix that should have silenced it

**Date:** 2026-11-01
**Component:** CT 103 / SearXNG + `tailscale serve`

**Symptom**

After activating `tailscale serve --bg 8888`, SearXNG's logs still showed:

"ERROR:searx.botdetection: X-Forwarded-For nor X-Real-IP header is set!"

**Expectation**

I predicted serve would inject `X-Forwarded-For`, silence the warning, and thereby confirm the proxy chain was correctly wired. It did not.

**Investigation**

Checked upstream rather than assuming. Findings:

- Tailscale has an **open feature request** proposing exactly this behavior — a `--trusted-proxies` flag where "a serve host will append to X-Forwarded headers if and only if the peer's remote address appears in the list." A feature request for a behavior is reasonable evidence the behavior does not yet exist. A companion request covers `X-Forwarded-Proto`.
- Tailscale's own serve documentation describes the headers serve *does* add — Tailscale identity headers — and `X-Forwarded-For` is not among them.
- SearXNG's source wraps this message in `log_error_only_once`, so it fires once per worker process, not continuously. An upstream commit titled *"[fix] reduce error logs related to X-Forwarded-For & X-Real-IP headers"* confirms the intent.
- The loopback Uptime Kuma monitor hits `http://127.0.0.1:8888` directly on the published port, bypassing serve entirely. That request alone guarantees at least one header-less request per cycle.

**Root cause**

Not a misconfiguration. Two layers:

1. `tailscale serve` does not supply `X-Forwarded-For`.
2. The loopback monitor never passes through serve, so no proxy is involved at all.

SearXNG is correctly reporting a factually true condition: it cannot determine a client IP from headers, because none are present in this topology.

**Resolution**

None required — left as-is deliberately.

The message matters when the limiter is running, because an incorrect client IP makes rate limiting misfire. The limiter is off. SearXNG's docs note the `ip_limit` method "requires a valkey DB and needs a HTTP X-Forwarded-For header" — with the limiter disabled, nothing consumes that value. Single user, private instance, tailnet-only, no abuse surface.

Silencing it would require inserting a real reverse proxy (nginx/Caddy) purely to set headers that nothing reads. Bad trade. A `limiter.toml` with `trusted_proxies` defined addresses the limiter's IP resolution, not this message, and adds a file to maintain.

**Lesson**

A log line that survives a fix is not automatically proof the fix failed. Verify the premise before chasing the symptom — in this case the premise ("serve injects this header") was simply wrong, and the correct action was to stop, not to escalate. Recording a wrong prediction alongside its correction is more useful to future me than pretending the prediction was never made.
