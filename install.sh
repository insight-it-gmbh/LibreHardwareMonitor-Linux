#!/usr/bin/env bash
# Install lhm-linux as a systemd service.
#
#   sudo ./install.sh              install and start
#   sudo ./install.sh --uninstall  stop, disable and remove
set -euo pipefail

PREFIX="${LHM_PREFIX:-/opt/lhm-linux}"
UNIT="/etc/systemd/system/lhm-linux.service"
SERVICE="lhm-linux"
PORT="${LHM_PORT:-8085}"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<USAGE
Usage: sudo ./install.sh [--prefix DIR] [--port N]
       sudo ./install.sh --uninstall

  --prefix DIR   Install location (default: /opt/lhm-linux).
                 Use a writable data pool on appliances with a read-only
                 root filesystem, e.g. TrueNAS: --prefix /mnt/pool/lhm-linux
  --port N       Listen port (default: 8085, the LibreHardwareMonitor default)
USAGE
}

ACTION="install"
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) [ -n "${2:-}" ] || die "--prefix needs a directory"; PREFIX="$2"; shift 2 ;;
    --port)   [ -n "${2:-}" ] || die "--port needs a number"; PORT="$2"; shift 2 ;;
    --uninstall) ACTION="uninstall"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "must be run as root (try: sudo $0)"

if [ "$ACTION" = "uninstall" ]; then
  echo "Removing $SERVICE ..."
  # Read the real install path out of the unit before deleting it, so a
  # custom --prefix from install time is removed too.
  if [ -f "$UNIT" ]; then
    INSTALLED=$(sed -n 's|^ExecStart=.*python3 \(.*\)/server\.py|\1|p' "$UNIT")
    [ -n "$INSTALLED" ] && PREFIX="$INSTALLED"
  fi
  systemctl disable --now "$SERVICE" 2>/dev/null || true
  rm -f "$UNIT"
  rm -rf "$PREFIX"
  echo "  removed $PREFIX"
  systemctl daemon-reload
  echo "Done."
  exit 0
fi

echo "==> Checking prerequisites"
command -v python3 >/dev/null || die "python3 not found"
PY_OK=$(python3 -c 'import sys; print(1 if sys.version_info >= (3,9) else 0)')
[ "$PY_OK" = "1" ] || die "Python 3.9 or newer is required"
printf '    python3      %s\n' "$(python3 -V 2>&1 | cut -d' ' -f2)"

for tool in sensors nvidia-smi ipmitool smartctl; do
  if command -v "$tool" >/dev/null; then
    printf '    %-12s found\n' "$tool"
  else
    printf '    %-12s not found (related sensors will be skipped)\n' "$tool"
  fi
done

echo "==> Installing to $PREFIX"
install -d -m 0755 "$PREFIX"
install -m 0755 "$SRC_DIR/lhmlinux/server.py" "$PREFIX/server.py"

echo "==> Writing $UNIT"
sed -e "s|LHM_PORT=8085|LHM_PORT=$PORT|" \
    -e "s|/opt/lhm-linux|$PREFIX|g" \
    "$SRC_DIR/systemd/lhm-linux.service" > "$UNIT"
chmod 0644 "$UNIT"

echo "==> Enabling service"
systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null
systemctl restart "$SERVICE"

echo "==> Waiting for the first poll"
for i in $(seq 1 30); do
  if curl -sf --max-time 3 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then
    echo "    ready after ${i}s"
    break
  fi
  [ "$i" = "30" ] && die "service did not become ready — check: journalctl -u $SERVICE"
  sleep 1
done

COUNT=$(curl -s "http://127.0.0.1:$PORT/data.json" \
        | python3 -c 'import json,sys
def n(x):
    return ("SensorId" in x) + sum(n(c) for c in x.get("Children", []))
print(n(json.load(sys.stdin)))' 2>/dev/null || echo "?")

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
echo "LibreHardwareMonitor-Linux is running — $COUNT sensors detected."
echo "  Dashboard : http://${IP:-<host>}:$PORT/"
echo "  Clients   : http://${IP:-<host>}:$PORT   (LibreHardwareMonitor endpoint)"
echo "  Metrics   : http://${IP:-<host>}:$PORT/metrics.txt"
echo
echo "  Logs      : journalctl -u $SERVICE -f"

if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "^Status: active"; then
  echo
  echo "note: ufw is active. To allow access from the LAN:"
  echo "      sudo ufw allow $PORT/tcp comment 'lhm-linux'"
fi
