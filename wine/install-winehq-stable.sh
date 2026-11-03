#!/usr/bin/env bash
# Replace Ubuntu's Wine 9.0 with WineHQ stable (11.0) from the official WineHQ repo.
# Steps follow https://gitlab.winehq.org/wine/wine/-/wikis/Debian-Ubuntu
set -euo pipefail
echo "Current: $(wine --version 2>/dev/null || echo none)"
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/winehq-archive.key
sudo curl -fsSL -o /etc/apt/sources.list.d/winehq-noble.sources \
  https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
sudo apt update
sudo apt install -y --install-recommends winehq-stable
hash -r
echo "Installed: $(wine --version)"
echo "WINEHQ-DONE"
