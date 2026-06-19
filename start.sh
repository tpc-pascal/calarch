#!/bin/bash
# ============================================================================
# START.SH — Thin wrapper -> dashboard.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DASHBOARD_SH="$SCRIPT_DIR/lib/dashboard.sh"
CORE="$SCRIPT_DIR/lib/core.sh"

# First-boot mode
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "first-boot" ]; then
  [ -f "$SCRIPT_DIR/lib/install.sh" ] && bash "$SCRIPT_DIR/lib/install.sh"
  exit 0
fi

# Boot guard + i_am_alive
"$CORE" boot_check 2>/dev/null || true
"$CORE" i_am_alive 2>/dev/null || true

# Launch dashboard
exec bash "$DASHBOARD_SH" "$@"
