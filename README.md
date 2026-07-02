# german-vps — Hetzner VPS automation

Ansible-managed configuration for the Hetzner Cloud server at `91.98.64.214`
(CAX-class, **arm64**, 2 vCPU / 4 GB / 40 GB, Nuremberg, Ubuntu 24.04 LTS).
The box runs rootful podman containers via quadlets:

| Service   | Image                                  | Purpose                                   | Exposure |
|-----------|----------------------------------------|-------------------------------------------|----------|
| tailscale | `ghcr.io/tailscale/tailscale:latest`   | Tailnet exit node (`german-vps`)          | outbound only (userspace/netstack) |
| sing-box  | `ghcr.io/sagernet/sing-box:v1.13.14`   | shadowsocks-2022 proxy exit               | 3128/tcp+udp |
| ~~squid~~ | retired 2026-06-30                     | basic-auth forward proxy → see `archive/` | — |

## Repository layout

```
ansible/     config *inside* the box — playbook, roles, inventory
terraform/   Hetzner resources *around* it — OpenTofu, local state
cloud-init/  day-0 user data, consumed by terraform on a rebuild
secrets/     gitignored live secrets + committed *.example templates
scripts/     verify.sh health checks, apply.sh wrapper
archive/     retired configs kept for reference
```

## Usage

```sh
cp secrets/secrets.yml.example secrets/secrets.yml     # first time; fill in, chmod 600
cp secrets/hcloud-token.example secrets/hcloud-token   # first time; Hetzner API token, chmod 600
just syntax                         # lint the playbook
just check                          # dry run
just apply                          # converge the server (idempotent, re-run any time)
just verify                         # post-apply health checks (plain ssh, no ansible)
```

Ansible is provided ad hoc through nix (`nix shell nixpkgs#ansible`); nothing
else is required locally beyond `ssh` and the private key
`~/.ssh/ssh-key-2023-12-26.key`.

## Infrastructure layer (OpenTofu)

`terraform/` manages the Hetzner Cloud resources themselves — the server,
its two primary IPs, the cloud firewall (22/tcp, 3128/tcp+udp) and the SSH
key — all imported from the pre-existing project on 2026-07-02 (state shows
them as adopted; nothing was recreated). Ansible remains the config layer
*inside* the box; OpenTofu owns everything *around* it.

```sh
just tf-plan              # preview infra drift/changes
just tf-apply             # apply them
```

The API token is read from `secrets/hcloud-token` (gitignored, chmod 600 —
same treatment as the Ansible secrets); an exported `$HCLOUD_TOKEN` takes
precedence if set.

State is local (`terraform/terraform.tfstate`, gitignored) — treat it as the
machine-local source of truth; only `.terraform.lock.hcl` is committed.
Gotchas baked into the config:

- Deletion is guarded twice: `prevent_destroy` stops tofu itself, and
  Hetzner-side `delete_protection` (plus `rebuild_protection` on the server,
  enabled 2026-07-02) blocks console/API/hcloud-CLI deletions. Any
  intentional teardown means flipping both layers off first.
- `ssh_keys`/`user_data` are create-time-only in the hcloud API and are
  `ignore_changes`d — they exist so a from-scratch rebuild picks up
  `cloud-init/user-data.yaml` automatically.
- There is deliberately **no `public_net` block** on the server: adding one to
  an adopted *running* server makes the provider power the box off and
  unassign/**delete** the live primary IP. The IPs are standalone resources;
  their assignment stays untouched. (Adding the block at *create* time — a
  disaster-recovery rebuild — is safe and reuses the IPs.)
- Both primary IPs are durable assets (`auto_delete=false` + delete
  protection, set 2026-07-02): the addresses outlive the server and get
  re-attached on a rebuild.

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
  `ansible/group_vars/all.yml` — bump it there and re-apply).

## Rebuild from scratch (disaster recovery)

1. Recreate through OpenTofu. (If this is an intentional rebuild rather than
   a dead box, first set `delete_protection`/`rebuild_protection` to `false`
   and `tf-apply` before deleting anything.) The primary IPs survive the box
   (`auto_delete=false` + delete protection), so only the server is replaced:
   `tofu state rm hcloud_server.vps`, delete its stale `import` block from
   `imports.tf`, and add a `public_net` block to the server resource
   referencing `hcloud_primary_ip.ipv4.id` / `hcloud_primary_ip.ipv6.id` —
   safe here because it applies at create time; the hazard documented in
   `main.tf` only concerns adding the block to a live adopted server. Then
   `just tf-apply` — the replacement comes up on the **same addresses**, with
   server type, image, location, firewall attachment, SSH key and
   `cloud-init/user-data.yaml` all from `terraform/main.tf`. If the create
   fails because cax11 is sold out (it often is), bump `server_type` to
   cax21. (sing-box is effectively IPv4-only: podman's default network has no
   IPv6 DNAT, so 3128 rules only matter for v4.)
2. `ansible/inventory.ini` needs no change — the addresses are reused.
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
  `ansible/group_vars/all.yml` + Hetzner console, applying, then removing the
  old one.
- `AllowTcpForwarding`/`AllowAgentForwarding` remain enabled deliberately
  (useful for tunnels); flip them in `ansible/roles/ssh/files/10-hardening.conf`
  if unused.
- Container supply chain: images are pulled unsigned
  (`policy.json = insecureAcceptAnything`, podman default) and tailscale tracks
  `:latest` nightly — accepted trade-off for hands-off updates.
- **Follow-ups after first apply** (one-time, manual):
  - Rotate the Tailscale OAuth key in the admin console (the old one sat
    world-readable in the quadlet since 2025) and update `secrets/secrets.yml`.
  - Consider rotating `shadowsocks_psk` (`openssl rand -base64 32`) and
    updating your client configs.
