# german-vps automation — `just --list` for available recipes.

ansible := "nix shell nixpkgs#ansible --command"

# Converge the server (idempotent, re-run any time)
apply *args:
    {{ansible}} ansible-playbook site.yml {{args}}

# Dry run with diff (command-based tasks may still show as changed)
check:
    {{ansible}} ansible-playbook site.yml --check --diff

# Syntax-check the playbook
syntax:
    {{ansible}} ansible-playbook site.yml --syntax-check

# Post-apply health checks (plain ssh, no ansible needed)
verify:
    ./scripts/verify.sh
