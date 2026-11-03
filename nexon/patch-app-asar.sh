#!/usr/bin/env bash
# Patch the locally installed Nexon Launcher's app.asar (Electron app code) for Wine.
# Installed to ~/.local/bin/nexon-launcher-patch by nexon/install.sh.
#
# Two same-length byte edits (file size and asar index stay valid):
#   1. Crash fix: replace the unused "disable-gpu file" check in main.js with
#        app.commandLine.appendSwitch('disable-blink-features', 'TextDecoratingBox')
#      so every way of starting the launcher (desktop entry, nxl:// links,
#      Nexon's own shortcuts) gets the fix.
#   2. No promotion pop-up: rename the 'cross_promotion' window case so the
#      launcher treats it as an unknown window and never opens it.
#
# A backup of the unpatched file is kept as app.asar.orig.
# Usage: nexon-launcher-patch            apply (idempotent)
#        nexon-launcher-patch --restore  put the original back
set -euo pipefail
PREFIX="${WINEPREFIX:-$HOME/.wine-nexon}"
A="$PREFIX/drive_c/Program Files (x86)/Nexon/Nexon Launcher/bin/nexon_client/resources/app.asar"
[ -f "$A" ] || { echo "app.asar not found: $A"; exit 1; }

if [ "${1:-}" = "--restore" ]; then
  [ -f "$A.orig" ] || { echo "no backup ($A.orig)"; exit 1; }
  cp -p "$A.orig" "$A"; echo "restored original app.asar"; exit 0
fi

pgrep -f '^C:.*\\nexon_client\.exe' >/dev/null && { echo "Close Nexon Launcher first (or run: WINEPREFIX=$PREFIX wineserver -k)"; exit 1; }

python3 -I - "$A" <<'PY'
import sys, shutil, os
p = sys.argv[1]
d = open(p, 'rb').read(); n0 = len(d)
old1 = b"if (fs.existsSync(path.join(global.setupDir, 'disable-gpu'))) {\n    app.commandLine.appendSwitch('disable-gpu');\n}"
new1 = b"app.commandLine.appendSwitch('disable-blink-features', 'TextDecoratingBox') // linux/wine fix".ljust(len(old1), b' ')
old2 = b"case 'cross_promotion':"
new2 = b"case 'cross_promotioX':"
done = []
if new1 in d and new2 in d:
    print("already patched"); sys.exit(0)
if old1 in d or old2 in d:
    # keep a backup of the unpatched file (refreshed if Nexon updated app.asar)
    if new1 not in d and new2 not in d:
        shutil.copy2(p, p + '.orig')
if d.count(old1) == 1:
    d = d.replace(old1, new1); done.append("crash fix (TextDecoratingBox)")
elif new1 not in d:
    print("WARNING: crash-fix pattern not found (Nexon changed main.js?). "
          "The nexon-launcher script still passes the flag, so launching through it works.")
if d.count(old2) == 1:
    d = d.replace(old2, new2); done.append("promotion pop-up disabled")
elif new2 not in d:
    print("WARNING: promotion pattern not found (Nexon changed windows-handler.js?).")
assert len(d) == n0, "size changed - refusing to write"
open(p, 'wb').write(d)
print("patched:", ", ".join(done) if done else "nothing to change")
PY
