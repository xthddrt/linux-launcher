#!/usr/bin/env bash
# Quick, read-only health check of the setup. No sudo needed.
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
info() { printf '  ..   %s\n' "$*"; }
chk()  { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

echo "System"
info "$(lsb_release -ds 2>/dev/null), kernel $(uname -r)"
chk "UEFI boot" test -d /sys/firmware/efi
chk "8 GB /swapfile active" sh -c "swapon --show=NAME --noheadings | grep -qx /swapfile"
chk "GRUB menu visible (GRUB_TIMEOUT_STYLE=menu)" grep -q '^GRUB_TIMEOUT_STYLE=menu' /etc/default/grub
chk "os-prober enabled (Windows in GRUB)" grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
info "free on /: $(df -h / | awk 'NR==2{print $4}')"

echo "Graphics"
chk "Vulkan sees an Intel/AMD/NVIDIA GPU" sh -c "vulkaninfo --summary 2>/dev/null | grep -qiE 'deviceName.*(Intel|AMD|Radeon|NVIDIA)'"
chk "OpenGL hardware renderer" sh -c "glxinfo -B 2>/dev/null | grep -qiE 'renderer string.*(Intel|AMD|Radeon|NVIDIA)'"

echo "Wine"
if command -v wine >/dev/null; then info "$(wine --version)"; else bad "wine not installed"; fi
chk "Wine 10 or newer (needed for Nexon Launcher)" sh -c "wine --version | grep -qE 'wine-(1[0-9]|[2-9][0-9])\.'"
chk "winetricks installed" command -v winetricks

echo "Nexon Launcher"
P="$HOME/.wine-nexon/drive_c/Program Files (x86)/Nexon/Nexon Launcher"
chk "prefix ~/.wine-nexon exists" test -d "$HOME/.wine-nexon"
chk "launcher installed" test -f "$P/bin/nexon_client/nexon_client.exe"
chk "launch script ~/.local/bin/nexon-launcher" test -x "$HOME/.local/bin/nexon-launcher"
chk "app.asar patched (crash fix)" grep -aq "linux/wine fix" "$P/bin/nexon_client/resources/app.asar"
chk "nxl:// links go to the launcher" sh -c "xdg-mime query default x-scheme-handler/nxl | grep -q nexon-launcher-wine"

echo "Optional tools"
chk "python venv ~/venvs/rev imports" ~/venvs/rev/bin/python -c "import Crypto, capstone, keystone, mitmproxy, scapy, PySide6"
chk "gdb" gdb --version
chk "tshark" tshark --version
info "ptrace_scope=$(cat /proc/sys/kernel/yama/ptrace_scope) (0 only if linux/03-research-tuning.sh was used)"
