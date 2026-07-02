# One-time adoption of the pre-existing Hetzner resources (imported
# 2026-07-02). Harmless to keep once applied; delete whenever.

import {
  to = hcloud_ssh_key.aaron
  id = "100618746"
}

import {
  to = hcloud_firewall.vps
  id = "2327163"
}

import {
  to = hcloud_primary_ip.ipv4
  id = "96905687"
}

import {
  to = hcloud_primary_ip.ipv6
  id = "96905688"
}

import {
  to = hcloud_server.vps
  id = "105837787"
}
