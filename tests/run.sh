#!/bin/bash
# Test runner — chay bo test calarch
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BATS="${BATS:-bats}"

echo "=== Calarch Test Suite ==="
echo "Root: $ROOT"
echo ""

# Check bats
if ! command -v "$BATS" &>/dev/null; then
    if command -v npm &>/dev/null; then
        echo "Installing bats via npm..."
        npm install -g bats 2>/dev/null || true
    fi
    if ! command -v bats &>/dev/null; then
        echo "bats not found. Install: npm install -g bats"
        echo "Or: apt install bats"
        exit 1
    fi
    BATS="bats"
fi

echo "Using: $BATS"
echo ""

# Run syntax tests first
echo "--- Syntax check ---"
ERRORS=0
while IFS= read -r -d '' f; do
    case "$f" in */web.sh) continue ;; esac
    if bash -n "$f" 2>/dev/null; then
        echo "  [OK] $f"
    else
        echo "  [FAIL] $f"
        ERRORS=$((ERRORS + 1))
    fi
done < <(find "$ROOT" -name '*.sh' -print0)

if [ $ERRORS -gt 0 ]; then
    echo "  $ERRORS file(s) failed syntax check"
fi
echo ""

# Run bats tests if available
if command -v "$BATS" &>/dev/null; then
    echo "--- Unit tests ---"
    exec "$BATS" "$ROOT/tests/"*.bats
else
    if [ $ERRORS -gt 0 ]; then
        exit 1
    fi
    echo "bats not available — syntax check only"
fi
