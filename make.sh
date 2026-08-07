#!/bin/bash
# ============================================================================
# MAKE.SH — Gom toan bo code script vao 1 file thuc thi duy nhat
# ----------------------------------------------------------------------------
# Chay: bash make.sh
# Output: calarch-v<VERSION>.run (self-extracting, chua TOAN BO code)
# Sau khi gom: xoa cac thu muc va file da duoc dong goi
# ============================================================================
set -euo pipefail
trap 'echo "Interrupted"; exit 1' INT TERM

VERSION="${VERSION:-1.0}"
NAME="calarch"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/${NAME}-v${VERSION}.run"
WORKDIR="$(mktemp -d)" || { echo "Cannot create temp dir"; exit 1; }
trap 'rm -rf "$WORKDIR"' EXIT

echo "=== Making calarch v${VERSION} ==="
cd "$SCRIPT_DIR"

# --- 1. Collect all tracked files ---
echo "Collecting files..."
if [ -d .git ]; then
    git ls-files > "$WORKDIR/filelist.txt"
    file_count=$(wc -l < "$WORKDIR/filelist.txt")
else
    find . -not -path './.git/*' -not -path './.opencode/*' \
        -not -name 'make.sh' -not -name '*.log' -not -name '*.run' \
        -type f > "$WORKDIR/filelist.txt"
    file_count=$(wc -l < "$WORKDIR/filelist.txt")
fi
echo "  ${file_count} files"

# --- 2. Compress ---
echo "Compressing..."
tar czf "$WORKDIR/payload.tar.gz" -T "$WORKDIR/filelist.txt"

# --- 3. Checksum ---
SHA256=$(sha256sum < "$WORKDIR/payload.tar.gz" | cut -d' ' -f1)
echo "  SHA256: ${SHA256}"

# --- 4. Base64 ---
echo "Encoding..."
base64 < "$WORKDIR/payload.tar.gz" > "$WORKDIR/payload.b64"
encoded_size=$(wc -c < "$WORKDIR/payload.b64")
echo "  Payload: $(( encoded_size / 1024 )) KB"

# --- 5. Build self-extracting executable ---
echo "Building ${OUTPUT_FILE}..."

cat > "$OUTPUT_FILE" << EXECSTUB
#!/bin/bash
# ============================================================================
# calarch v${VERSION} — Panasonic CF-XZ6 Full System Installer
# Chua toan bo code: auto-install, godmode setup, CPU affinity, thermal, HW
# SHA256: ${SHA256}
# ============================================================================
set -euo pipefail
trap 'echo "Interrupted"; exit 1' INT TERM

VERSION="${VERSION}"
NAME="${NAME}"
EXTRACT_DIR="/tmp/\${NAME}-\${VERSION}"
CACHE_FILE="/tmp/\${NAME}-v\${VERSION}.ok"

banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     calarch v\${VERSION} — Panasonic CF-XZ6                      ║"
    echo "║     Full installer: Arch + Hyprland + tools                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

cache_valid() {
    [ -f "\$CACHE_FILE" ] && [ -f "\$EXTRACT_DIR/start.sh" ]
}

detect_env() {
    if grep -q "ARCHISO\|archiso" /proc/cmdline 2>/dev/null || [ ! -f /etc/os-release ]; then
        if command -v pacstrap &>/dev/null; then echo "iso"; return; fi
    fi
    if command -v pacman &>/dev/null && grep -q "Arch Linux" /etc/os-release 2>/dev/null; then
        echo "installed"; return
    fi
    echo "unknown"
}

main() {
    banner

    local env=\$(detect_env)

    # --- Find payload ---
    local PL
    PL=\$(grep -n '^#__PAYLOAD__\$' "\$0" 2>/dev/null | tail -1 | cut -d: -f1)
    if [ -z "\$PL" ]; then
        echo "ERROR: Corrupt package (no payload)"
        exit 1
    fi
    PL=\$((PL + 1))

    # --- Extract (cached or fresh) ---
    if cache_valid; then
        echo "  Cached: \${EXTRACT_DIR}"
    else
        echo "  Extracting to: \${EXTRACT_DIR}"
        rm -rf "\$EXTRACT_DIR"
        mkdir -p "\$EXTRACT_DIR"

        # Decoder fallback
        local decoder=""
        for d in "base64 -d" "openssl base64 -d -A" "python3" "perl"; do
            command -v \${d%% *} &>/dev/null && decoder="\$d" && break
        done
        if [ -z "\$decoder" ]; then
            echo "ERROR: No decoder (need base64, openssl, or python)"
            exit 1
        fi

        # Extractor fallback
        local extractor=""
        for e in "tar xzf -" "bsdtar xzf -" "gzip -dc | tar xf -"; do
            command -v "\${e%% *}" &>/dev/null && extractor="\$e" && break
        done
        if [ -z "\$extractor" ]; then
            echo "ERROR: No extractor (need tar or gzip)"
            exit 1
        fi

        # Extract helper with git clone fallback
        extract_or_clone() {
            eval "\$extractor" -C "\$EXTRACT_DIR" 2>/dev/null && return 0
            echo "ERROR: Extraction failed. Trying git clone..."
            rm -rf "\$EXTRACT_DIR" 2>/dev/null || true
            mkdir -p "\$EXTRACT_DIR"
            git clone --depth=1 https://github.com/tpc-pascal/calarch.git "\$EXTRACT_DIR" 2>/dev/null || {
                echo "ERROR: All methods failed (extraction + git clone)"
                exit 1
            }
        }

        if [ "\$decoder" = "python3" ]; then
            python3 -c "import sys,base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))" < <(tail -n +\$PL "\$0") | extract_or_clone
        elif [ "\$decoder" = "perl" ]; then
            perl -MMIME::Base64 -e 'print decode_base64(join"",<>)' < <(tail -n +\$PL "\$0") | extract_or_clone
        else
            tail -n +\$PL "\$0" | \$decoder | extract_or_clone
        fi

        touch "\$CACHE_FILE"
    fi

    # Symlink
    rm -f "/tmp/\${NAME}" 2>/dev/null || true
    ln -sf "\$EXTRACT_DIR" "/tmp/\${NAME}" 2>/dev/null || true

    cd "\$EXTRACT_DIR" || cd "\$(dirname "\$0")" || exit 1

    # --- Auto-detect mode ---
    local mode="\${1:-auto}"

    if [ "\$mode" = "auto" ]; then
        if [ "\$env" = "iso" ]; then
            mode="post-install"
        elif [ "\$env" = "installed" ]; then
            mode="setup"
        else
            mode="help"
        fi
    fi

    case "\$mode" in
        post-install|--post-install)
            echo "  Mode: POST-INSTALL"
            echo "  Env:  \${env}"
            exec bash lib/post-install.sh post-install "\${@:2}"
            ;;
        setup)
            echo "  Mode: GODMODE SETUP"
            echo "  Env:  Installed Arch"
            exec bash start.sh "\${@:2}"
            ;;
        shell)
            exec bash --rcfile <(echo "PS1='[calarch] \\\w\\\$ '")
            ;;
        check)
            echo "  Env:      \${env}"
            echo "  Version:  \${VERSION}"
            echo "  Cache:    \$(cache_valid && echo "Valid at \${EXTRACT_DIR}" || echo "None")"
            echo "  Files:    \$(find . -type f 2>/dev/null | wc -l)"
            echo "  Commands: post-install, setup, refind, refind-sync, fix-partuuid, shell, check, help"
            ;;
        refind|--refind)
            echo "  Mode: REFIND CONFIG"
            exec bash lib/post-install.sh refind "\${@:2}"
            ;;
        refind-sync|--refind-sync)
            echo "  Mode: REFIND KERNEL SYNC"
            exec bash lib/refind-sync.sh --mnt "\${2:-}" "\${@:3}"
            ;;
        fix-partuuid|--fix-partuuid)
            echo "  Mode: FIX PARTUUID"
            exec bash lib/post-install.sh fix-partuuid "\${2:-}" "\${3:-}" "\${@:4}"
            ;;
        help|--help|-h)
            echo "Usage: \$0 [mode]"
            echo ""
            echo "Modes (auto-detect if omitted):"
            echo "  post-install  calarch setup tren he thong da mount"
            echo "  setup         Unified TUI menu"
            echo "  refind        Sinh refind_linux.conf"
            echo "  refind-sync   Dong bo kernel ra ESP + entry + hook"
            echo "  fix-partuuid  Sua PARTUUID trong refind_linux.conf"
            echo "  shell         Bash trong extracted environment"
            echo "  check         Kiem tra trang thai"
            echo "  help          This help"
            echo ""
            echo "Detected environment: \${env}"
            ;;
        *)
            echo "Unknown: \$mode. Try: \$0 help"
            exit 1
            ;;
    esac
}

main "\$@"
exit 0

#__PAYLOAD__
EXECSTUB

# Append payload
cat "$WORKDIR/payload.b64" >> "$OUTPUT_FILE"
chmod +x "$OUTPUT_FILE"

final_size=$(wc -c < "$OUTPUT_FILE")
echo ""
echo "=== Built: $(basename "$OUTPUT_FILE") ==="
echo "  Size: $(( final_size / 1024 )) KB"
echo "  SHA256: ${SHA256}"

echo ""
echo "=== Done ==="
echo "  Output: $(basename "$OUTPUT_FILE")"
echo "  Size:   $(( final_size / 1024 )) KB"
echo "  Usage:  ./$(basename "$OUTPUT_FILE") help"
echo ""
