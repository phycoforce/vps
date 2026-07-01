#!/usr/bin/env bash
# Converge german-vps. Usage: ./scripts/apply.sh [--check --diff | --syntax-check | extra ansible args]
set -euo pipefail
cd "$(dirname "$0")/.."
exec nix shell nixpkgs#ansible --command ansible-playbook site.yml "$@"
