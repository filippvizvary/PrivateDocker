#!/bin/bash
set -euo pipefail

BOOTSTRAP_ENV="/etc/homestack/bootstrap.env"
DONE_FILE="/var/lib/homestack-firstboot.done"
LOG_FILE="/var/log/homestack-firstboot.log"

mkdir -p /var/lib
mkdir -p /etc/homestack

exec > >(tee -a "$LOG_FILE") 2>&1

echo "[$(date -Iseconds)] HomeStack first-boot start"

if [[ -f "$DONE_FILE" ]]; then
  echo "Already completed; exiting"
  exit 0
fi

if [[ -f "$BOOTSTRAP_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$BOOTSTRAP_ENV"
  set +a
fi

: "${NONINTERACTIVE:=1}"
: "${HOMESTACK_SETUP_EXISTING:=fail}"
: "${HOMESTACK_RECONFIGURE:=0}"
: "${HOMESTACK_DIR:=/homestack}"
: "${HOMESTACK_REPO_URL:=https://github.com/filippvizvary/homestack.git}"

if [[ -z "${HOMESTACK_REAL_USER:-}" ]]; then
  echo "HOMESTACK_REAL_USER is required in $BOOTSTRAP_ENV"
  exit 1
fi

if ! id "$HOMESTACK_REAL_USER" &>/dev/null; then
  echo "Configured HOMESTACK_REAL_USER '$HOMESTACK_REAL_USER' does not exist"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl ca-certificates python3 python3-venv python3-pip sqlite3

if [[ ! -d "$HOMESTACK_DIR/.git" ]]; then
  rm -rf "$HOMESTACK_DIR"
  git clone "$HOMESTACK_REPO_URL" "$HOMESTACK_DIR"
fi

cd "$HOMESTACK_DIR"

NONINTERACTIVE="$NONINTERACTIVE" \
HOMESTACK_SETUP_EXISTING="$HOMESTACK_SETUP_EXISTING" \
HOMESTACK_RECONFIGURE="$HOMESTACK_RECONFIGURE" \
HOMESTACK_REAL_USER="$HOMESTACK_REAL_USER" \
HOMESTACK_DIR="$HOMESTACK_DIR" \
TZ="${TZ:-}" \
PUID="${PUID:-}" \
PGID="${PGID:-}" \
HOMESTACK_APPS_REPO="${HOMESTACK_APPS_REPO:-}" \
bash ./setup.sh

touch "$DONE_FILE"
systemctl disable --now homestack-firstboot.service || true

echo "[$(date -Iseconds)] HomeStack first-boot completed"
