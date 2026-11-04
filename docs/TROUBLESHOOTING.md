# Troubleshooting: Nexon Launcher on Wine

Every problem hit while getting the launcher working, in the order they appeared, with the
root cause and how it was found. Useful if a Nexon update or Wine change breaks things again.

## How the launcher is built

```
nexon_launcher.exe        Python updater (PyInstaller). Updates files, then starts:
bin/nexon_client/
  nexon_client.exe        Electron 22.3.27 (Chromium 108), renamed electron.exe
  resources/app.asar      Electron main-process code + preload scripts
bin/front_end             app path passed to nexon_client.exe
nexon_runtime.exe         small helper the client spawns ("<n> stdio")
```

The UI itself is a **remote web page**: `https://nxl.nxfs.nexon.com/nxl/login`, which embeds
the account login from `www.nexon.com` in an iframe. On Windows the main process is started as
`nexon_client.exe "C:\...\bin\front_end"`; an `nxl://...` link is passed as `--nxl=nxl://...`.

## 1. `Fatal Python error: init_sys_streams: can't initialize sys standard streams`

- **Symptom:** launching `nexon_launcher.exe` from a shortcut/terminal: nothing appears.
- **Cause:** with stdin/stdout closed or redirected, Wine gave the Python launcher invalid
  Windows handles (`OSError: [WinError 6] Invalid handle`).
- **Fix:** start through `wine start /d <dir> <exe>`, which sets up proper handles.

## 2. DXVK fails, GPU process crashes

- **Symptom:** `DXVK: ... Device does not support required feature 'khrLoadStoreOpNone'`,
  `Failed to initialize DXVK`, then `Unhandled page fault`.
- **Cause:** `winetricks dxvk` installs the newest DXVK (3.x), which needs
  `VK_KHR_load_store_op_none`; Ubuntu's Wine 9.0 `winevulkan` doesn't expose it.
- **Fix:** `winetricks -f dxvk2030` (DXVK 2.3).

## 3. Per-app DLL overrides ignored

- **Symptom:** `AppDefaults\nexon_client.exe\DllOverrides` with `d3d11=builtin` had no effect
  (`WINEDEBUG=+loaddll` still showed `d3d11.dll ... native`).
- **Cause:** winetricks writes global overrides as `*d3d11=native`. The `*` form (any path)
  beats a plain `d3d11` entry.
- **Fix:** use the `*d3d11`, `*dxgi`, `*d3d10core`, `*d3d9` names in the AppDefaults key
  (now set to empty, see #8).

## 4. Blank window on Wine 9.0 (cross-process child windows)

- **Symptom:** `X11DRV_vkCreateWin32SurfaceKHR Failed to allocate client window`,
  `wglSetPixelFormatWINE failed to set pixel format`.
- **Cause:** Chromium's GPU process draws into a child window owned by the browser process.
  Wine 9.0 can't render GL/Vulkan into another process's child window (added in Wine 10).
- **Workaround on 9.0:** `--in-process-gpu`. **Real fix:** WineHQ 10+.

## 5. Renderer crash at `0x03B34D01`: the main bug

- **Symptom (Wine 9.0):** `Unhandled page fault on read access to 00000010 at address 03B34D01`
  in a renderer, Wine crash dialog, window stays blank except title/footer.
- **Symptom (Wine 11):** no dialog. The login page "hangs": idle CPU, doesn't answer
  DevTools, `did-finish-load` never fires. Wine still lists the renderer, but its
  `CrRendererMain` thread is gone and the Linux process is missing. The crash killed the
  thread and Chromium was never told.
- **Not the cause (ruled out):** GPU (`--disable-gpu`), sandbox (`--no-sandbox`), site
  isolation, V8 JIT (`--js-flags=--jitless`), fonts, AudioContext, canvas/WebGL, focus(),
  sync IPC from the preload, network (no pending requests).
- **How it was found:**
  1. `nexon_client.exe` is stock Electron: its PE debug directory names
     `electron.exe.pdb`, id `8F610232F969EA184C4C44205044422E1`.
  2. Electron's symbol server has the matching breakpad file:
     `https://symbols.electronjs.org/electron.exe.pdb/<id>/electron.exe.sym`.
  3. Crash RVA = `0x03B34D01 - 0x400000` = `0x3734D01`, which falls in
     `blink::NGInlinePaintContext::ScopedLineBox::ScopedLineBox(NGInlineCursor const&, NGInlinePaintContext*)`.
  4. That code belongs to the `TextDecoratingBox` Blink runtime feature (string present in the exe).
- **Fix:** `--disable-blink-features=TextDecoratingBox`. The page then loads completely.

## 6. `wmic csproduct` errors

- `getUuidFromWmic ... wmic csproduct get name,identifyingnumber,uuid ... Alias not found`
  in `nexon_runtime_debug.log`. Wine 9.0's `wmic` lacks the alias; **Wine 11 supports it**
  (it reports the machine's real SMBIOS values).

## 7. Promotion pop-up can't be closed

- The front end asks the main process to open a `cross_promotion` window (802x526). The patch
  renames that `case` so `open_window` logs `window name is not valid: cross_promotion` and
  returns.

## 8. Black box at the top-left of the screen

- **Symptom:** a black rectangle sits at the top-left corner while the launcher runs, the
  size of the launcher (1024x720) or of its 800x300 "starting game" window, which appears
  when you press Play. It stays after those windows close. Seen on GNOME Wayland (XWayland), Wine 11.
- **Cause:** for GPU drawing, winex11 puts each window's Direct3D/GL output in a child
  "client" window inside a 1x1 holder window at 0,0. When the launcher's windows close or
  hide, those surfaces stay mapped and GNOME keeps drawing them at the corner.
  `xwininfo -root -tree` shows them as unnamed `nexon_client.exe` windows at `+0+0`.
  The game's own windows aren't involved: they are all unmapped or inside the game window.
- **Not a fix:** unmapping the stale surface or cycling the holder only works until
  the next window opens. Unmapping the holder also blanks the launcher.
- **Fix:** disable Direct3D for `nexon_client.exe` only: set `*d3d11`, `*dxgi`, `*d3d10core`
  and `*d3d9` to an empty value under `HKCU\Software\Wine\AppDefaults\nexon_client.exe\DllOverrides`
  (`install.sh` step 3). Chromium then draws in software and creates no client surfaces.
  It takes effect only after a full restart of the launcher (`wineserver -k`, then start it).
  Games keep DXVK.
- **Undo** (back to Wine's built-in Direct3D):
  `for d in d3d11 dxgi d3d9 d3d10core; do WINEPREFIX=~/.wine-nexon wine reg add 'HKCU\Software\Wine\AppDefaults\nexon_client.exe\DllOverrides' /v "*$d" /d builtin /f; done`

## Debugging toolbox

- **Launcher debug log:** create an empty file `enable_debug` in
  `C:\Program Files (x86)\Nexon\Nexon Launcher\`; full logs go to `nexon_runtime_debug.log`
  in that folder. Delete the file afterwards.
- **Chromium log:** `--enable-logging --log-file=C:\nx-chrome.log` (stderr isn't passed
  through `wine start`). Page console messages show up as `CONSOLE(...)`.
- **DevTools:** `--remote-debugging-port=9222 --remote-debugging-address=127.0.0.1`, then
  `curl http://127.0.0.1:9222/json`. Electron doesn't support `Target.createTarget`.
- **Main-process inspector:** `--inspect=9229`. Evaluate with
  `process.mainModule.require('electron')`; `webContents.debugger` gives CDP on a page before
  it loads (`Page.addScriptToEvaluateOnNewDocument`). Useful for tracing which API a page is
  stuck in. Load `about:blank` first after killing a hung renderer, or debugger commands wait forever.
- **Which DLLs load:** `WINEDEBUG=+loaddll`.
- **Native stacks:** `printf 'bt all\nquit\n' | wine winedbg` covers every process it can read.
  A process it can't attach to (`error 299`) may already be dead on the Linux side: compare
  `winedbg 'info proc'` with `ps`.
- **Crash handler for 32-bit apps** lives under
  `HKLM\Software\Wow6432Node\Microsoft\Windows NT\CurrentVersion\AeDebug`.
- **Window screenshots without GNOME screenshot access:** `xwininfo -root -tree` to find the
  XWayland window, then `xwd -id <win>`.

## Harmless messages

- `ntlm_auth was not found` (install `winbind` to silence)
- `err:ole:... class {...} not registered`
- `react-i18next:: It seems you are still using the old wait option`
