set default-list
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

ansible := 'nix shell nixpkgs#ansible --command'

[doc('Converge the server (idempotent, re-run any time)')]
apply *args:
    {{ ansible }} ansible-playbook site.yml {{ args }}

[doc('Dry run with diff (command-based tasks may still show as changed)')]
check:
    {{ ansible }} ansible-playbook site.yml --check --diff

[doc('Syntax-check the playbook')]
syntax:
    {{ ansible }} ansible-playbook site.yml --syntax-check
