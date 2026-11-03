#!/usr/bin/env bash
# OPTIONAL. Kernel/permission settings for an analysis/research workstation.
# NOT needed to run Nexon Launcher. These lower some default protections:
#   * kernel.yama.ptrace_scope = 0  -> any of your processes can ptrace your other processes
#   * input group                   -> your user can read every keyboard/mouse event (/dev/input)
#   * wireshark group               -> non-root packet capture
#   * kernel.core_pattern = core.%p -> core dumps in the working dir (disables apport capture)
# Only use on a machine you control, for software/traffic you own or may test.
set -euo pipefail
sudo -v
sudo tee /etc/sysctl.d/99-research.conf >/dev/null <<'EOF'
kernel.yama.ptrace_scope = 0
vm.swappiness = 10
kernel.perf_event_paranoid = 1
EOF
echo 'kernel.core_pattern = core.%p' | sudo tee /etc/sysctl.d/99-coredump.conf >/dev/null
sudo sysctl --system >/dev/null
echo "ptrace_scope=$(cat /proc/sys/kernel/yama/ptrace_scope) swappiness=$(cat /proc/sys/vm/swappiness)"
getent group wireshark >/dev/null || sudo dpkg-reconfigure -f noninteractive wireshark-common
sudo usermod -aG input,wireshark "$USER"
echo "Added $USER to input,wireshark. Log out and back in for groups to apply."
echo "Undo: sudo rm /etc/sysctl.d/99-research.conf /etc/sysctl.d/99-coredump.conf && sudo gpasswd -d \$USER input && sudo gpasswd -d \$USER wireshark"
