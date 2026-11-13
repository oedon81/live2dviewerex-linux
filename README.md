# Live2DViewerEX on Linux (KDE Plasma)

Run **Live2DViewerEX** (Steam) as a real, live, interactive wallpaper on **KDE Plasma 6 (Wayland)**.

Live2DViewerEX is Windows-only and normally can't act as a wallpaper on Linux. Under Proton you get either nothing or
a window covering your desktop. This port fixes that:

- ✅ The model is your actual wallpaper: desktop icons, widgets and panels stay on top.
- ✅ **Wallpaper mode** works (needed for the Control Panel's **Background** tab), and so does **Desktop** mode.
- ✅ Click, drag, right-click and scroll on the desktop reach the model and its on-screen buttons.
- ✅ Right-clicking the desktop still opens Plasma's normal desktop menu.
- ✅ A native Plasma tray icon: left-click opens the Control Panel, right-click opens the menu.

> You need to own Live2DViewerEX on Steam. This repo contains no part of the app, only small helpers around it.
> It is not affiliated with Pavo Studio.

## Requirements

- KDE Plasma 6 on Wayland (tested on Fedora, Plasma 6.8)
- Steam, with Live2DViewerEX installed and run once with Proton (Proton Experimental tested)
- `python3` with PyGObject. It is usually already installed; if not:
  - Fedora: `sudo dnf install python3-gobject`
  - Arch: `sudo pacman -S python-gobject`
  - Debian/Ubuntu: `sudo apt install python3-gi`

## Install (2 minutes)

**1. Download and run the installer** (close Live2DViewerEX first):

```bash
git clone https://github.com/oedon81/live2dviewerex-linux.git && cd live2dviewerex-linux && ./install.sh
```

No git? Click **Code → Download ZIP** above, extract it, open a terminal in the folder and run `./install.sh`.

**2. Set the Steam launch option.** You only do this once. In Steam, right-click **Live2DViewerEX → Properties →
General → Launch Options** and paste the line below. The installer has already copied it to your clipboard.

```
bash -c 'exec "${@/launcher.exe/progman_shim.exe}"' -- %command%
```

**3. Start Live2DViewerEX from Steam.** In its Control Panel, set **Launch Mode** to **Wallpaper**, or **Desktop**
if you prefer. That's it.

The installer switches your desktop's wallpaper type to **"Live2DViewerEX (live)"**. Your current picture is kept
and shown whenever the viewer is closed.

## Update

```bash
cd live2dviewerex-linux && git pull && ./install.sh
```

## Uninstall

```bash
./uninstall.sh
```

Then clear the Launch Options in Steam. Files the installer replaced the first time are backed up in
`~/.local/share/l2dex/backup-*`.

## Tips

- **Meta+Alt+L** shows the real viewer window as a normal window, and hides it again.
- Right-click the desktop → **Desktop and Wallpaper** to set the still picture, and choose which of clicks,
  right-clicks and the wheel are passed to the viewer.
- Tray menu → **Frame Rate: Match Monitor** runs the viewer at your screen's refresh rate. The Control Panel's slider stops at 120.

## Troubleshooting

| Problem | Fix |
|---|---|
| Live2DViewerEX doesn't start or shows `DESKWND_NOT_FOUND` | The Steam Launch Options are missing or wrong (step 2). Run `./install.sh` again while the viewer is closed. |
| Installer says "Live2DViewerEX was not found" | Run `L2DEX_DIR="/path/to/steamapps/common/Live2DViewerEX" ./install.sh` |
| Wallpaper stays on the still picture | System Settings → Window Management → KWin Scripts: enable **Live2DViewerEX wallpaper helper**. Check the wallpaper type is **Live2DViewerEX (live)**. |
| The viewer's window covers the desktop icons | The KWin effect isn't loaded: run `./install.sh` again. |
| Clicks don't reach the model | `busctl --user call local.l2dex.Bridge /Bridge local.l2dex.Bridge Status` should say `true <port>`. |
| Stuck in a mode that won't launch | Edit `steamapps/common/Live2DViewerEX/bin/system.dat` while the viewer is closed. Set `"launchMode"` to `1` (Desktop). 0 = Wallpaper, 2 = Desktop (Compat), 3 = Window. Turn off Steam Cloud for the app first, or it may restore the old file. |

Not tested yet: more than one monitor, and display scaling other than 100 %. Reports are welcome.

## How it works

```
 Steam ── progman_shim.exe ── launcher.exe ── lwtray.exe ── lw.exe (Unity player)
            ▲ UDP 48398: "c X Y", "run lwui"    │ its wallpaper window      ▲ ws://127.0.0.1:<bin/app_port>/api
            │                                   ▼                           │ {"msg":1918,"data":[1,x,y]} ...
 l2dex-bridge ◄── cursor ── KWin script: keeps that window over its screen, under everything
   (D-Bus)    ◄── buttons ─ Plasma wallpaper plugin: shows the window's live picture under the icons
      │                     KWin effect: stops drawing the real window on screen
      └── native tray icon and menu (StatusNotifierItem)
```

| Part | Installed to | Job |
|---|---|---|
| `shim/progman_shim.exe` | the Live2DViewerEX folder | Steam starts it instead of `launcher.exe`. It fakes Explorer's desktop windows that the viewer needs: `Progman` with `SHELLDLL_DefView` and `WorkerW` children, laid out like Windows 11 24H2. In Wallpaper mode the player draws into `WorkerW`, and the shim keeps that sized to the screen. The shim also moves Wine's cursor and starts the viewer's tools for the bridge. |
| `kwin/` | `~/.local/share/kwin/scripts/` | Keeps the viewer's window (`UnityContainer` in Desktop mode, `Program Manager` in Wallpaper mode) over its screen, below all windows and without focus. Tells the wallpaper plugin which window to show and sends the cursor position to the bridge. |
| `effect/` | `~/.local/share/kwin/effects/` | Draws that window at opacity 0. Its screencast stream is unaffected, so the wallpaper still gets the picture. |
| `wallpaper/` | `~/.local/share/plasma/wallpapers/` | Wallpaper type "Live2DViewerEX (live)". Shows the window's live picture via PipeWire, or a still picture when the viewer is closed. Reports desktop clicks to the bridge without taking them. |
| `bridge/l2dex-bridge` | `~/.local/bin/` + D-Bus service | Starts on demand and exits 20 s after the viewer closes. On Windows, the viewer's global mouse hook reports clicks and cursor moves; the bridge sends the same messages instead. It also provides the tray icon. |

Viewer messages, found by reading `lwtray.exe` and the player's `Assembly-CSharp.dll`:

| Message | Meaning |
|---|---|
| 1918 `[1, x, y]` | Cursor position |
| 1910 `true` / 1911 | Left button down / up |
| 1912 / 1913 | Right button down / up |
| 1917 / 1916 | Wheel |
| 3900 `true` | Adjust model |
| 1990 / 1991 | Pause / resume |

Adding 2000000 to a message number sends it to the tray program instead. For example, 1999 = exit and 1992 `<mode>` = restart.

Rebuilding the shim after editing `shim/progman_shim.cs`: `shim/build.sh`. It needs the .NET SDK in `~/.dotnet` and
Proton Experimental. A prebuilt `progman_shim.exe` is included, so users don't need this.

Launch option extras: put `L2D_SHIM_LOG=1` in front for a shim log, or `L2D_WINE_TRAY=1` for Wine's own tray icon.

## Known limits

- The Plasma tray menu has no Launch Mode entry; change the mode in the Control Panel.
- Dragging on the desktop also draws Plasma's selection rectangle. The viewer also sees clicks on icons, the same as on Windows.
- The viewer's global keyboard hotkeys only work while one of its own windows has focus.

## License

MIT. See [LICENSE](LICENSE).
