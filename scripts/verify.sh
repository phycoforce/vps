#!/usr/bin/env bash
# Post-apply health check for german-vps. Run from the workstation:
#   ./scripts/verify.sh
# All remote checks share one multiplexed SSH connection — ufw's `limit 22/tcp`
# would otherwise rate-ban us for opening ~20 connections in a row.
set -u

HOST=91.98.64.214
KEY=~/.ssh/ssh-key-2023-12-26.key
CTL=$(mktemp -u /tmp/verify-ssh-XXXXXX)
SSH="ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=10 \
     -o ControlMaster=auto -o ControlPath=$CTL -o ControlPersist=60 aaron@$HOST"
trap '$SSH -O exit 2>/dev/null' EXIT

pass=0 fail=0
ok()   { printf ' \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf ' \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
check(){ local desc=$1; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }

echo "== Connectivity =="
check "SSH reachable as aaron"            $SSH true
check "sing-box port 3128/tcp reachable"  nc -z -w 5 "$HOST" 3128

echo "== sshd effective config =="
sshd_t=$($SSH 'sudo -n sshd -T 2>/dev/null' || true)
grep -q '^passwordauthentication no' <<<"$sshd_t" && ok "PasswordAuthentication no" || bad "PasswordAuthentication no"
grep -q '^permitrootlogin no'        <<<"$sshd_t" && ok "PermitRootLogin no"        || bad "PermitRootLogin no"
grep -q '^allowusers aaron'          <<<"$sshd_t" && ok "AllowUsers aaron"          || bad "AllowUsers aaron"
$SSH 'test ! -e /root/.ssh/authorized_keys' && ok "root authorized_keys removed" || bad "root authorized_keys removed"

echo "== Firewall / fail2ban =="
ufw_out=$($SSH 'sudo -n ufw status' || true)
grep -q  'Status: active'                <<<"$ufw_out" && ok "ufw active"                  || bad "ufw active"
grep -Eq '^22/tcp\s+LIMIT'               <<<"$ufw_out" && ok "ufw limits 22/tcp"           || bad "ufw limits 22/tcp"
grep -Eq '3128.*ALLOW FWD'               <<<"$ufw_out" && ok "ufw route-allows 3128 (DNAT)" || bad "ufw route-allows 3128 (DNAT)"
check "netavark FORWARD rules present"  $SSH 'sudo -n iptables -S FORWARD | grep -q NETAVARK'
check "fail2ban sshd jail active"       $SSH 'sudo -n fail2ban-client status sshd'
check "rollback guard not armed"        $SSH '! systemctl is-active --quiet ufw-rollback-guard.timer'

echo "== Containers =="
check "tailscale container running" $SSH 'sudo -n podman ps --format "{{.Names}}" | grep -q tailscale'
check "sing-box container running"  $SSH 'sudo -n podman ps --format "{{.Names}}" | grep -q sing-box'
check "tailscale logged in"         $SSH 'sudo -n podman exec systemd-tailscale tailscale status --peers=false'
check "podman-auto-update.timer on" $SSH 'systemctl is-enabled --quiet podman-auto-update.timer'
check "squid quadlet gone"          $SSH 'test ! -e /etc/containers/systemd/squid.container'
check "/opt/squid gone"             $SSH 'test ! -e /opt/squid'

echo "== Secrets hygiene =="
check "no inline TS_AUTHKEY in quadlet" $SSH '! grep -q "^Environment=TS_AUTHKEY=" /etc/containers/systemd/tailscale.container'
check "quadlet uses EnvironmentFile"    $SSH 'grep -q "^EnvironmentFile=" /etc/containers/systemd/tailscale.container'
check "tailscale env file is 0600"      $SSH 'stat -c %a /etc/default/tailscale-container | grep -qx 600'
check "sing-box config is 0600"         $SSH 'sudo -n stat -c %a /opt/sing-box/config.json | grep -qx 600'
check "no squid creds in root history"  $SSH 'sudo -n bash -c "! grep -q squidproxy /root/.bash_history"'

echo "== OS updates / misc =="
check "unattended-upgrades timer on" $SSH 'systemctl is-enabled --quiet apt-daily-upgrade.timer'
check "swap active"                  $SSH 'swapon --show=NAME --noheadings | grep -q /swapfile'
if $SSH 'sudo -n pro api u.pro.status.is_attached.v1 2>/dev/null' | grep -q '"is_attached": *true'; then
  ok "Ubuntu Pro attached"
else
  printf ' \033[33mWARN\033[0m Ubuntu Pro not attached (add token to secrets/secrets.yml and re-apply)\n'
fi

echo
echo "$pass passed, $fail failed"
exit $((fail > 0))
