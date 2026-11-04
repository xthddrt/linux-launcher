# linux-launcher

Set up an Ubuntu 24.04 dual-boot machine and run the **Nexon Launcher** on Linux with Wine.

Out of the box the launcher does not work under Wine: it crashes at startup, then shows a
blank window, then a frozen login screen. This repo has the scripts and the fixes that get
it to a working, logged-in launcher, plus the Linux baseline setup the machine was built with.

> **Games are a separate question.** This gets the *launcher* working (log in, browse,
> install). Many Nexon games ship kernel-mode anti-cheat, which Wine/Proton cannot run;
> those games may refuse to start no matter how Wine is configured. Check a game on
> [ProtonDB](https://www.protondb.com/) before relying on it.

## Tested on

| | |
|---|---|
| Machine | Acer Aspire C24-1650 all-in-one (Intel Tiger Lake, Intel UHD Graphics, Intel AX201 Wi-Fi), 8 GB RAM |
| OS | Ubuntu 24.04.5 LTS, dual boot with Windows 11, GNOME on Wayland |
| Wine | **WineHQ 11.0 stable** (Ubuntu's Wine 9.0 does not work, see below) |
| Launcher | Nexon Launcher 4.7.11 (Electron 22.3.27 / Chromium 108) |

## Quick start

```bash
git clone https://github.com/xthddrt/linux-launcher.git
cd linux-launcher

# 1. Linux baseline (packages, GRUB menu with Windows, 8 GB swap). Needs sudo.
bash linux/01-system-setup.sh

# 2. Replace Ubuntu's Wine 9.0 with WineHQ 11 stable. Needs sudo.
bash wine/install-winehq-stable.sh

# 3. Nexon Launcher: download NexonLauncherSetup.exe from nexon.com first.
bash nexon/install.sh ~/Downloads/NexonLauncherSetup.exe

# 4. Check everything
bash linux/verify.sh
```

Then start **"Nexon Launcher (Wine)"** from the app menu (or run `~/.local/bin/nexon-launcher`).
The launcher logs you in through your web browser; the `nxl://` link the site sends back is
routed to the launcher automatically.

If you only want the launcher and already have Ubuntu set up, steps 2 and 3 are enough
(you need `winetricks` installed: `sudo apt install winetricks`).

## What's in here

```
linux/
  01-system-setup.sh     updates, base packages, Wine deps, Steam/Lutris/Bottles, GRUB, swap   (sudo)
  02-user-tools.sh       optional: Python analysis venv, Ghidra (checksum-verified)
  03-research-tuning.sh  optional: ptrace/input/wireshark permissions for a research box       (sudo)
  verify.sh              read-only health check
wine/
  install-winehq-stable.sh   adds the official WineHQ repo, installs winehq-stable (11.x)       (sudo)
nexon/
  install.sh             creates ~/.wine-nexon, DXVK, overrides, runs the installer, patches, installs launcher
  nexon-launcher         the launch script (installed to ~/.local/bin)
  patch-app-asar.sh      the app.asar patch (installed as ~/.local/bin/nexon-launcher-patch)
docs/
  TROUBLESHOOTING.md     every problem hit, its root cause, how it was found, and the fix
```

## The fixes, in short

| Problem | Cause | Fix |
|---|---|---|
| `Fatal Python error: init_sys_streams` when starting `nexon_launcher.exe` | Wine handed the Python launcher invalid stdio handles | Start programs with `wine start` |
| Graphics errors / DXVK fails (`khrLoadStoreOpNone`) | DXVK 3.x needs Vulkan features Wine 9.0 doesn't pass through | DXVK **2.3** for games |
| Black box at the top-left of the screen (launcher size, or 800x300 when you press Play) | Wine leaves the launcher's GPU drawing surfaces on screen under GNOME/XWayland | Direct3D off for `nexon_client.exe` only, so the launcher draws in software |
| Blank window, crash at `03B34D01`, renderer silently dies | Blink bug in `NGInlinePaintContext::ScopedLineBox` (text-decoration painting) hit by the login page | `--disable-blink-features=TextDecoratingBox` |
| Many small crashes, `wmic csproduct` errors, cross-process drawing failures | Ubuntu's Wine 9.0 is too old | WineHQ **11.0** stable |
| Promotion pop-up that can't be closed | Front end opens a `cross_promotion` window | Patched out in `app.asar` |
| Browser login can't return to the launcher | No Linux handler for `nxl://` | `x-scheme-handler/nxl` → `nexon-launcher` (passes `--nxl=...` like Nexon's launcher does) |

Details and the debugging trail: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

### About the app.asar patch

`nexon/patch-app-asar.sh` makes two **same-length** byte edits to the launcher's own
`app.asar` (your installed copy; nothing from Nexon is redistributed here):

1. Replaces an unused "disable-gpu marker file" check in `main.js` with
   `app.commandLine.appendSwitch('disable-blink-features', 'TextDecoratingBox')`, so *every*
   way of starting the launcher gets the crash fix.
2. Renames the `cross_promotion` window case so the promotion window is never opened.

The original is kept as `app.asar.orig`. Undo with `nexon-launcher-patch --restore`.

## Updating the launcher

Starting via `nexon-launcher` skips Nexon's Python updater (it starts the UI directly with the
fix). To update:

```bash
nexon-launcher --update
```

This runs Nexon's updater once, closes it, re-applies the patch, and starts the launcher.
If the patch reports "pattern not found", Nexon changed their code: the crash-fix flag is
still passed by the script, but the promotion block may need updating.

## Uninstall

```bash
WINEPREFIX=~/.wine-nexon wineserver -k
rm -rf ~/.wine-nexon ~/.local/bin/nexon-launcher ~/.local/bin/nexon-launcher-patch \
       ~/.local/share/applications/nexon-launcher-wine.desktop
# Optional: go back to Ubuntu's Wine
sudo apt remove winehq-stable && sudo rm /etc/apt/sources.list.d/winehq-noble.sources
```

## Linux baseline notes

`linux/01-system-setup.sh` is the first-boot setup for a dual-boot machine (Ubuntu installed
next to Windows on free space, UEFI, Secure Boot off). It:

- shows the GRUB menu for 10 s and adds **Windows Boot Manager** (os-prober)
- replaces the installer's 4 GB `/swap.img` with an **8 GB `/swapfile`** plus zram
- installs Wine 32/64-bit support, Vulkan/Mesa tools, Steam, Lutris, Bottles, ProtonUp-Qt
- optionally mounts Windows C: **read-only** (`WIN_UUID=<uuid> bash linux/01-system-setup.sh`)

If Windows' clock is wrong after using Ubuntu, run this once in Windows as administrator:
`reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f`

`linux/03-research-tuning.sh` is **optional and unrelated to the launcher**. It lowers some
protections (ptrace, raw input access) for analysis work; read the header before using it.
