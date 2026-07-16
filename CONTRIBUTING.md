## Dong gop

### Yeu cau

- Bash 5.0+, `set -euo pipefail`
- Tuan thu coding convention cua du an
- Moi PR vao nhanh `dev`

### Coding Convention

- Khong comment giai thich code (tru khi that su can)
- Function name: `snake_case`
- Bien local: `local_name`
- Hang: `UPPER_CASE`
- Kiem tra `set -euo pipefail` o dau moi script
- Dung `has() { command -v "$1" &>/dev/null; }` de kiem tra lenh

### Cau truc thu muc

```
calarch/
├── start.sh                     # Unified TUI — entry point duy nhat
├── lib/                         # Thu vien chinh
│   ├── post-install.sh          # Post-install setup
│   ├── tui-core.sh              # TUI engine
│   ├── system.sh                # System monitor
│   ├── settings.sh              # Settings panel
│   ├── mount.sh                 # Drive manager
│   ├── wallpaper.sh             # Wallpaper changer
│   ├── focus.sh                 # Focus mode
│   ├── notes.sh                 # Notes manager
│   ├── games.sh                 # Games launcher
│   ├── refind-sync.sh           # rEFInd sync
│   ├── profiles.sh              # Profile manager
│   ├── safety.sh                # Safety engine
│   ├── core.sh                  # Config I/O + Safety + Profile
│   ├── dashboard.sh             # Legacy dashboard
│   ├── ... (cac script khac)
├── installer/                   # Legacy installer
│   └── auto-install-arch.sh
├── calarch.conf                 # Config trung tam
├── make.sh                      # Builder
```

### Chay thu

```bash
cd calarch
bash lib/tui.sh                  # Kiem tra dialog co san
bash lib/core.sh get KERNEL_PARAMS  # Doc config
bash start.sh                    # Mo TUI
```

### Build

```bash
VERSION=1.0.5 bash make.sh
# Output: calarch-v1.0.5.run
```

### Commit

- 1 commit duy nhat cho 1 feature
- Title format: `feat: v<version> - <mo ta>`
- VD: `feat: v1.0.5 - unified TUI, new docs, post-install standalone`
