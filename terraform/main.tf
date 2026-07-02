resource "hcloud_ssh_key" "aaron" {
  name       = "ssh-key-2023-12-26"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7Mg+TFga/96tbbiMYsj/JMscDNl3N1aAVFQ3p827amq6C2gwE9DTKRofRxKJvGCXO4EuDMaFVgy3Myn52SgYPiIsa37m2wZrZWzCIFrf2eL1YVTrJnx2Qr0GKZPngc95mcAhvjxiQLkwMfRBMDj5n3A6dbIsupIyPhvtgB2v2YrFgdcjJcO37tGLZRcu8Ok5CMlpEW9KQJPGO5PX3sFZK5ybQon9bJDzsYUcYQMp/mnhA1+6CBvcQNOP2m8E4pi66Kg67olOZq0bPoZkoU98W+mwfPfPEUlK4zadX4uwOOyVoCBXBjIphK5+JD97tddhZIrsdALqxn7lDNsOucqD5"
}

# Ingress mirrors ufw on the host: ssh + sing-box. 3128/udp matters — without
# it shadowsocks UDP relay silently degrades (see README security notes).
resource "hcloud_firewall" "vps" {
  name = "firewall-1"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "3128"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "3128"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Delete-protected and auto_delete=false: the addresses are durable assets
# that outlive the server. Re-attach them on a rebuild via a create-time
# public_net block — see README disaster recovery.
resource "hcloud_primary_ip" "ipv4" {
  name              = "primary_ip-96905687"
  type              = "ipv4"
  location          = "nbg1"
  auto_delete       = false
  delete_protection = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_primary_ip" "ipv6" {
  name              = "primary_ip-96905688"
  type              = "ipv6"
  location          = "nbg1"
  auto_delete       = false
  delete_protection = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_server" "vps" {
  name         = "ubuntu-4gb-nbg1-4"
  server_type  = "cax11"
  image        = "ubuntu-24.04"
  location     = "nbg1"
  firewall_ids = [hcloud_firewall.vps.id]

  # Hetzner requires these two to be equal for servers.
  delete_protection  = true
  rebuild_protection = true

  # Create-time only: the API never returns these for the imported box, so
  # they're ignore_changes'd below. They exist to make a from-scratch rebuild
  # (README "disaster recovery") reproducible through tofu.
  ssh_keys  = [hcloud_ssh_key.aaron.id]
  user_data = file("${path.module}/../cloud-init/user-data.yaml")

  # No public_net block, deliberately. The primary IPs above are already
  # assigned to this server; adding the block to an adopted RUNNING server
  # makes the provider power the box off and unassign/delete the live primary
  # IP (updatePublicNet in the provider has no same-ID check). Omitting it
  # suppresses all public_net diffs — assignment stays as-is. Adding the
  # block at CREATE time (a rebuild) is safe and reuses the IPs.

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ssh_keys, user_data]
  }
}
