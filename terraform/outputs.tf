# Read from the server, not the hcloud_primary_ip resources: after a rebuild
# the server carries fresh auto-generated IPs and these stay correct, and
# ipv6_address is a connectable host address (::1) rather than the /64 network.
output "server_ipv4" {
  value = hcloud_server.vps.ipv4_address
}

output "server_ipv6" {
  value = hcloud_server.vps.ipv6_address
}

output "server_status" {
  value = hcloud_server.vps.status
}
