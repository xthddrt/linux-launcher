#!/usr/bin/env bash
# Ubuntu 24.04 first-boot baseline for a dual-boot (Windows + Ubuntu) machine.
# Needs sudo. Run as your normal user (it calls sudo itself):
#
#   script -q -a ~/linux-setup-log.txt -c "bash linux/01-system-setup.sh"
#
# What it does:
#   1. Full system update, enables universe/multiverse and 32-bit (i386) packages
#   2. Baseline packages: build tools, Python, debuggers, network tools, Vulkan/Mesa,
#      Java, Flatpak, Wine (distro version) + winetricks, Steam, zram
#   3. Flatpak apps: ProtonUp-Qt, Lutris, Bottles
#   4. GRUB: always show the boot menu (10 s) and include Windows Boot Manager
#   5. Swap: 8 GB /swapfile (replaces the installer's /swap.img) + zram
#   6. Optional: mount the Windows C: partition read-only at /mnt/windows
#      (set WIN_UUID=<ntfs uuid from `lsblk -f`> to enable)
#
# Safe to re-run. Nothing here touches Windows partitions except the optional
# read-only mount.
set -euo pipefail
step() { printf '\n\033[1;35m==== %s  [%s]\033[0m\n' "$1" "$(date '+%F %T')"; }

[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root (it calls sudo itself)."; exit 1; }
sudo -v

step "1. System update"
sudo apt update
sudo apt full-upgrade -y
sudo add-apt-repository -y universe
sudo add-apt-repository -y multiverse
sudo dpkg --add-architecture i386
sudo apt update

step "2. Baseline packages"
# Allow non-root packet capture through the wireshark group (no prompt)
echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
sudo apt install -y \
  build-essential git curl wget unzip p7zip-full ca-certificates gnupg \
  lsb-release software-properties-common apt-transport-https \
  python3 python3-venv python3-pip python3-dev python3-full pipx \
  gdb strace ltrace binutils file xxd vim nano tmux htop btop tree jq \
  ripgrep fd-find "linux-headers-$(uname -r)" \
  tcpdump tshark wireshark mitmproxy nmap netcat-openbsd socat \
  conntrack iptables nftables \
  mesa-vulkan-drivers vulkan-tools mesa-utils vainfo libgl1-mesa-dri \
  libxcb-cursor0 alsa-utils pavucontrol cheese openjdk-21-jdk flatpak \
  os-prober efibootmgr zram-tools radare2

step "2b. Wine (distro version) + 32-bit graphics"
# wine/install-winehq-stable.sh later replaces the distro Wine 9.0 with WineHQ 11.
sudo apt install -y wine wine64 wine32:i386 winetricks \
  libgl1-mesa-dri:i386 libvulkan1:i386 mesa-vulkan-drivers:i386

step "2c. Steam (read and accept the Steam license yourself if a prompt appears)"
sudo apt install -y steam-installer

step "3. Flatpak: ProtonUp-Qt, Lutris, Bottles (large download)"
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
sudo flatpak install -y --noninteractive flathub net.davidotek.pupgui2 net.lutris.Lutris com.usebottles.bottles

step "4. GRUB: show the menu and include Windows Boot Manager"
sudo cp -n /etc/default/grub /etc/default/grub.bak-before-setup || true
sudo sed -i -E 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/; s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=10/' /etc/default/grub
if grep -qE '^#?GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
  sudo sed -i -E 's/^#?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
else
  echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub
fi
sudo update-grub
sudo grep -E "^menuentry '" /boot/grub/grub.cfg | cut -d"'" -f2

step "5. 8 GB swap file (+ zram)"
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  [ -f /swapfile ] || sudo fallocate -l 8G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
if [ -f /swap.img ]; then
  sudo swapoff /swap.img || true
  sudo sed -i -E '\#^/swap\.img[[:space:]]#d' /etc/fstab
  sudo rm -f /swap.img
fi
printf 'ALGO=zstd\nPERCENT=25\n' | sudo tee /etc/default/zramswap
sudo systemctl restart zramswap
swapon --show; free -h

step "6. Optional: Windows C: read-only at /mnt/windows"
if [ -n "${WIN_UUID:-}" ]; then
  sudo mkdir -p /mnt/windows
  mountpoint -q /mnt/windows || sudo mount -o ro "UUID=$WIN_UUID" /mnt/windows
  FST=$(findmnt -no FSTYPE /mnt/windows)
  grep -q "UUID=$WIN_UUID" /etc/fstab || echo "UUID=$WIN_UUID /mnt/windows $FST ro,nofail 0 0" | sudo tee -a /etc/fstab
  ls /mnt/windows | head
else
  echo "Skipped. To enable: WIN_UUID=<uuid of the Windows C: ntfs partition from 'lsblk -f'> bash $0"
fi

step "DONE. Reboot when convenient (new kernel/groups)."
