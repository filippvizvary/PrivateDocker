#!/bin/bash
# ============================================================
# HomeStack Test Runner
# Installs BATS if needed, then runs test suites
# Usage: ./tests/run_tests.sh [unit|integration|apps|all]
# ============================================================
set -euo pipefail

export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BATS_DIR="${SCRIPT_DIR}/.bats"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Install BATS if not present ---
install_bats() {
  if [[ -x "${BATS_DIR}/bats-core/bin/bats" ]]; then
    return 0
  fi

  echo -e "${BLUE}==>${NC} Installing BATS (Bash Automated Testing System)..."
  mkdir -p "$BATS_DIR"

  git clone --depth 1 https://github.com/bats-core/bats-core.git "${BATS_DIR}/bats-core" 2>/dev/null
  git clone --depth 1 https://github.com/bats-core/bats-support.git "${BATS_DIR}/bats-support" 2>/dev/null
  git clone --depth 1 https://github.com/bats-core/bats-assert.git "${BATS_DIR}/bats-assert" 2>/dev/null

  echo -e "${GREEN}✓${NC} BATS installed"
}

BATS_BIN="${BATS_DIR}/bats-core/bin/bats"

# --- Determine what to run ---
SUITE="${1:-all}"

install_bats

echo ""
echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       HomeStack Test Runner          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

FAILED=0

run_suite() {
  local name="$1"
  local dir="$2"

  if [[ ! -d "$dir" ]] || ! ls "$dir"/*.bats &>/dev/null; then
    echo -e "${YELLOW}⚠${NC}  No tests found in ${dir}"
    return 0
  fi

  echo -e "${BLUE}━━━ ${name} ━━━${NC}"
  if "$BATS_BIN" "$dir"/*.bats; then
    echo -e "${GREEN}✓${NC} ${name} passed"
  else
    echo -e "${RED}✗${NC} ${name} had failures"
    FAILED=1
  fi
  echo ""
}

case "$SUITE" in
  unit)
    run_suite "Unit Tests" "${SCRIPT_DIR}/unit"
    ;;
  integration)
    if ! docker info &>/dev/null 2>&1; then
      echo -e "${RED}✗${NC} Docker is not running — skipping integration tests"
      exit 1
    fi
    run_suite "Integration Tests" "${SCRIPT_DIR}/integration"
    ;;
  apps)
    if ! docker info &>/dev/null 2>&1; then
      echo -e "${RED}✗${NC} Docker is not running — skipping app health tests"
      exit 1
    fi
    run_suite "App Health Tests" "${SCRIPT_DIR}/apps"
    ;;
  all)
    run_suite "Unit Tests" "${SCRIPT_DIR}/unit"

    if docker info &>/dev/null 2>&1; then
      run_suite "Integration Tests" "${SCRIPT_DIR}/integration"
      run_suite "App Health Tests" "${SCRIPT_DIR}/apps"
    else
      echo -e "${YELLOW}⚠${NC}  Docker not available — skipping integration & app tests"
    fi
    ;;
  *)
    echo "Usage: $0 [unit|integration|apps|all]"
    exit 1
    ;;
esac

echo ""
if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}All test suites passed ✓${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed ✗${NC}"
  exit 1
fi
