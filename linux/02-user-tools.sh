#!/usr/bin/env bash
# User-level tools (no sudo needed, except the JDK hint at the end):
#   * Python analysis venv at ~/venvs/rev
#   * Ghidra (latest release) in ~/tools, checksum-verified, pointed at the right JDK
# Run after linux/01-system-setup.sh:   bash linux/02-user-tools.sh
set -euo pipefail
step() { printf '\n\033[1;35m==== %s\033[0m\n' "$1"; }
mkdir -p ~/venvs ~/tools ~/research/captures

step "Python venv (~/venvs/rev)"
[ -d ~/venvs/rev ] || python3 -m venv ~/venvs/rev
~/venvs/rev/bin/pip install -q --upgrade pip setuptools wheel
# triton-library = Jonathan Salwan's Triton (NOT the OpenAI GPU compiler called "triton")
~/venvs/rev/bin/pip install -q pycryptodome PySide6 evdev capstone keystone-engine \
  mitmproxy scapy pyelftools ipython triton-library pwntools websocket-client
~/venvs/rev/bin/python -c "import Crypto, capstone, keystone, mitmproxy, scapy, PySide6, evdev, elftools, pwn, triton; print('python toolchain: OK')"
QT_QPA_PLATFORM=offscreen ~/venvs/rev/bin/python -c "from PySide6.QtWidgets import QApplication; QApplication([]); print('Qt: OK')"

step "Ghidra (latest release)"
cd ~/tools
REL=$(curl -fsSL https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest)
URL=$(python3 -I -c 'import json,sys; d=json.load(sys.stdin); print([a["browser_download_url"] for a in d["assets"] if a["name"].endswith(".zip")][0])' <<<"$REL")
SHA=$(python3 -I -c 'import json,sys,re; b=json.load(sys.stdin)["body"]; print(re.search(r"[0-9a-f]{64}", b).group(0))' <<<"$REL")
ZIP=$(basename "$URL"); DIRNAME=${ZIP%_[0-9]*.zip}
if [ ! -d "$DIRNAME" ]; then
  curl -fSL -o "$ZIP" "$URL"
  echo "$SHA  $ZIP" | sha256sum -c -
  unzip -q "$ZIP" && rm "$ZIP"
fi
GH=~/tools/$DIRNAME
JMIN=$(sed -n 's/^application.java.min=//p' "$GH/Ghidra/application.properties")
JHOME=/usr/lib/jvm/java-${JMIN}-openjdk-amd64
if [ -d "$JHOME" ]; then
  sed -i "s|^JAVA_HOME_OVERRIDE=.*|JAVA_HOME_OVERRIDE=$JHOME|" "$GH/support/launch.properties"
  echo "Ghidra uses $JHOME. Start it with: $GH/ghidraRun"
else
  echo "Ghidra needs Java $JMIN. Install it, then re-run this script:"
  echo "  sudo apt install -y openjdk-${JMIN}-jdk"
fi
