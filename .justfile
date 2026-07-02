#!/usr/bin/env -S just --justfile

set default-list
set lazy
set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

# Ansible Recipes
[group: 'Ansible']
mod ansible "ansible"

# Terraform Recipes
[group: 'Terraform']
mod tf "terraform"

[doc('Post-apply health checks (plain ssh, no ansible needed)')]
verify:
    ./scripts/verify.sh
