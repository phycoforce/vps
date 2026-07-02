# german-vps automation — `just --list` for available recipes.

ansible := "nix shell nixpkgs#ansible --command"
tofu := "nix shell nixpkgs#opentofu --command"

# Converge the server (idempotent, re-run any time)
apply *args:
    cd ansible && {{ansible}} ansible-playbook site.yml {{args}}

# Dry run with diff (command-based tasks may still show as changed)
check:
    cd ansible && {{ansible}} ansible-playbook site.yml --check --diff

# Syntax-check the playbook
syntax:
    cd ansible && {{ansible}} ansible-playbook site.yml --syntax-check

# Post-apply health checks (plain ssh, no ansible needed)
verify:
    ./scripts/verify.sh

# Preview Hetzner infra changes (token: secrets/hcloud-token, or $HCLOUD_TOKEN)
tf-plan *args:
    cd terraform && HCLOUD_TOKEN=${HCLOUD_TOKEN:-$(cat ../secrets/hcloud-token)} {{tofu}} tofu plan {{args}}

# Apply Hetzner infra changes (token: secrets/hcloud-token, or $HCLOUD_TOKEN)
tf-apply *args:
    cd terraform && HCLOUD_TOKEN=${HCLOUD_TOKEN:-$(cat ../secrets/hcloud-token)} {{tofu}} tofu apply {{args}}

# Re-init providers after changing versions.tf
tf-init:
    cd terraform && {{tofu}} tofu init
