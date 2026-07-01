# german-vps — Hetzner VPS automation

Ansible-managed configuration for the Hetzner Cloud server at `91.98.64.214`
(CAX-class, **arm64**, 2 vCPU / 4 GB / 40 GB, Nuremberg, Ubuntu 24.04 LTS).
The box runs rootful podman containers via quadlets:

| Service   | Image                                  | Purpose                                   | Exposure |
|-----------|----------------------------------------|-------------------------------------------|----------|
| tailscale | `ghcr.io/tailscale/tailscale:latest`   | Tailnet exit node (`german-vps`)          | outbound only (userspace/netstack) |
| sing-box  | `ghcr.io/sagernet/sing-box:v1.13.14`   | shadowsocks-2022 proxy exit               | 3128/tcp+udp |
| ~~squid~~ | retired 2026-06-30                     | basic-auth forward proxy → see `archive/` | — |

## Usage

```sh
cp secrets/secrets.yml.example secrets/secrets.yml   # first time; fill in, chmod 600
just syntax                         # lint the playbook
just check                          # dry run
just apply                          # converge the server (idempotent, re-run any time)
just verify                         # post-apply health checks (plain ssh, no ansible)
```

Ansible is provided ad hoc through nix (`nix shell nixpkgs#ansible`); nothing
else is required locally beyond `ssh` and the private key
`~/.ssh/ssh-key-2023-12-26.key`.

## What the playbook manages

- **base** — packages, Hetzner NTP, `needrestart` auto-restart, 2 GB swap file
  (`vm.swappiness=10`), network-hardening sysctls.
- **updates** — unattended-upgrades (security + `-updates` origins, unused
  kernel/dependency cleanup, auto-reboot 04:00) and Ubuntu Pro: attaches with
  `ubuntu_pro_token` from secrets and enables `esm-infra`/`esm-apps`.
- **ssh** — `/etc/ssh/sshd_config.d/10-hardening.conf`: key-only auth
  (`PasswordAuthentication no`), `PermitRootLogin no`, `AllowUsers aaron`,
  no X11, tighter auth limits. Removes root's `authorized_keys`.
  (The 2025 cloud-init `sed` hardening never actually applied — this fixes it.)
- **podman** — the two quadlets, `/opt` payload dirs, sing-box config
  (PSK templated from secrets, 0600), Tailscale auth key in root-only
  `/etc/default/tailscale-container` instead of inline in the quadlet
  (with `TS_AUTH_ONCE=true`, so rotating the key can't crash-loop restarts),
  forwarding sysctls (needed by podman's published-port DNAT; tailscale itself
  runs userspace netstack), `podman-auto-update.timer`.
- **firewall** — ufw: default deny in/routed, `limit 22/tcp`,
  allow `3128/tcp+udp` plus the `route allow` rules podman's DNAT needs,
  with an auto-rollback guard around the first enable. fail2ban sshd jail
  (systemd backend, incremental bans).
- **cleanup** — removes the retired squid quadlet/mask/images//opt/squid,
  the stale podman-1.x `libpod.conf`, and scrubs the squid password from
  root's bash history.

## Update automation (already in place, now codified)

- OS packages: `unattended-upgrades` daily; auto-reboot at 04:00 when needed.
- Container images: `podman-auto-update.timer` nightly (`AutoUpdate=registry`);
  tailscale tracks `:latest`, sing-box is pinned (`singbox_image` in
  `group_vars/all.yml` — bump it there and re-apply).

## Rebuild from scratch (disaster recovery)

1. Create a Hetzner CAX server (Ubuntu 24.04) with `cloud-init/user-data.yaml`
   as user data; attach the cloud firewall allowing `22/tcp` and `3128/tcp+udp`.
   (sing-box is effectively IPv4-only: podman's default network has no IPv6
   DNAT, so 3128 rules only matter for v4.)
2. Point `inventory.ini` at the new IP.
3. Secrets: new Tailscale auth key (tag:container) in `secrets/secrets.yml`
   (or restore `/opt/tailscale` to keep the node identity); keep the same
   `shadowsocks_psk` so clients continue to work.
4. `just apply && just verify`.
5. Fresh Tailscale registrations: approve the exit node in the admin console.

## Security posture notes

- Ingress is filtered twice: Hetzner Cloud firewall (22, 3128) **and** ufw on
  the host. Verify the Hetzner rule for 3128 includes **UDP**, or shadowsocks
  UDP relay silently degrades.
- **After any manual `ufw reload`/`ufw disable && enable`, run
  `sudo podman network reload --all`** — ufw's iptables-restore flushes
  netavark's FORWARD rules and sing-box stops accepting new connections until
  they're re-added. The playbook does this automatically on every apply.
- All accounts have locked passwords; auth is a single RSA-2048 key. Consider
  rotating to ed25519 (`ssh-keygen -t ed25519`), adding the new public key to
  `group_vars/all.yml` + Hetzner console, applying, then removing the old one.
- `AllowTcpForwarding`/`AllowAgentForwarding` remain enabled deliberately
  (useful for tunnels); flip them in `roles/ssh/files/10-hardening.conf` if unused.
- Container supply chain: images are pulled unsigned
  (`policy.json = insecureAcceptAnything`, podman default) and tailscale tracks
  `:latest` nightly — accepted trade-off for hands-off updates.
- **Follow-ups after first apply** (one-time, manual):
  - Rotate the Tailscale OAuth key in the admin console (the old one sat
    world-readable in the quadlet since 2025) and update `secrets/secrets.yml`.
  - Consider rotating `shadowsocks_psk` (`openssl rand -base64 32`) and
    updating your client configs.
