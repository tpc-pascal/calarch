#!/bin/bash
# ============================================================================
# CONFIG-LOAD.SH — Safe loader for calarch.conf
# ----------------------------------------------------------------------------
# Thay the `source calarch.conf`: gia tri co khoang trang (vd KERNEL_PARAMS)
# hoac chua '=' se lam `source` loi cu phap. Parser nay cat key/val o dau
# dau '=' dau tien, khong eval, khong source — an toan voi moi gia tri.
# Xu ly: bo comment/rong, chi nhan key hop le, boca cap ngoac kep,
# mo rong `$HOME` / `~` dau cau cho gia tri than thien.
# ============================================================================

calarch_load_config() {
    local cfg="${1:-$CONFIG_FILE}"
    [ -f "$cfg" ] || return 0

    local line key val
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" == *=* ]] || continue
        key=${line%%=*}
        val=${line#*=}
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

        # Bỏ khoang trang thua quanh key
        key=${key//[[:space:]]/}

        # Bỏ cặp ngoặc kép bao quanh (neu co)
        if [[ "$val" == \"*\" && "${#val}" -ge 2 ]]; then
            val=${val:1:${#val}-2}
        fi

        # Mo rong $HOME / ~ dau cau (khong mo rong bien khac — tranh injection)
        val=${val//\$HOME/$HOME}
        [[ "$val" == \~* ]] && val="$HOME${val:1}"

        printf -v "$key" '%s' "$val" 2>/dev/null || true
    done < "$cfg"
}

# Cho phép load truc tiep khi run: bash lib/config-load.sh [config]
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CONFIG_FILE="${1:-$SCRIPT_DIR/../calarch.conf}"
    calarch_load_config "$CONFIG_FILE"
fi
