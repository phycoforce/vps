set default-list
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

tofu := 'nix shell nixpkgs#opentofu --command'

[doc('Apply Hetzner infra changes (token: secrets/hcloud-token, or $HCLOUD_TOKEN)')]
apply *args:
    HCLOUD_TOKEN=${HCLOUD_TOKEN:-$(cat ../secrets/hcloud-token)} {{ tofu }} tofu apply {{ args }}

[doc('Re-init providers after changing versions.tf')]
init:
    {{ tofu }} tofu init

[doc('Preview Hetzner infra changes (token: secrets/hcloud-token, or $HCLOUD_TOKEN)')]
plan *args:
    HCLOUD_TOKEN=${HCLOUD_TOKEN:-$(cat ../secrets/hcloud-token)} {{ tofu }} tofu plan {{ args }}
