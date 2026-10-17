# nightwatch

Bed-viewing mode for a KDE Plasma 6 (Wayland) desktop: dim and warm one monitor
for watching video in the dark, and make sure nothing stays lit all night if you
fall asleep.

The problem it solves: any video player holds a Wayland idle inhibitor while it
plays, so Plasma's own dim and screen-off timers never fire during playback.
Fall asleep mid-episode and both screens stay on until morning. `nightwatch on`
arms its own cutoff timer that **pauses MPRIS players first** (pausing is what
releases the inhibitor) and only then blanks the screens. After that the normal
power timers work again.

## Pieces

| Path | What it is |
|---|---|
| `plasmoid/` | The "Night Viewing" panel widget, id `com.dakotatalley.nightwatch`. |
| `plasmoid/contents/code/nightwatch` | The bash script that does the work. It ships inside the widget package, and the widget calls it from there. |
| `package.sh` | Builds `dist/nightwatch-<version>.plasmoid` for sharing. |
| `install.sh` | Development install: symlinks the widget and the `nightwatch` command to this repo. |

## Install

To use it, build the package and install it the normal Plasma way:

```sh
./package.sh
kpackagetool6 -t Plasma/Applet -i dist/nightwatch-*.plasmoid   # -u to upgrade
```

or Add Widgets → Get New → Install Widget From Local File. Then add "Night
Viewing" to a panel. For the `nightwatch` command on your PATH, link
`~/.local/share/plasma/plasmoids/com.dakotatalley.nightwatch/contents/code/nightwatch`
into `~/.local/bin`.

To work on it, run `./install.sh` instead. It links
`~/.local/share/plasma/plasmoids/com.dakotatalley.nightwatch` and
`~/.local/bin/nightwatch` to this repo, so edits here take effect directly. After
changing QML, run `systemctl --user restart plasma-plasmashell`.

Versions before 2.0 used the id `org.kde.nightwatch`, which is reserved for KDE's
own projects. Upgrading from those means removing the old widget from the panel
and adding the new one; its settings do not carry over.

## Usage

```
nightwatch on [2h] [2000] [4]  dim + warm, arm the cutoff (duration, kelvin, %)
nightwatch off                 restore day settings, cancel the cutoff
nightwatch toggle [...]        on if off, off if on
nightwatch extend [30m]        push the cutoff further out
nightwatch now                 run the cutoff immediately
nightwatch status / state      human-readable / one key=value line for the widget
```

Pass `none` as the duration for no cutoff.

Widget: left click opens the popup (sleep timer, warmth, brightness, "+30 min",
"Sleep now"); middle click toggles. The timer dropdown re-arms from now, while
"+30 min" extends the existing deadline so repeated taps add up.

## How it works

- **Brightness** is set per connector with `kscreen-doctor
  output.<connector>.brightness.<pct>`. KWin passes this to PowerDevil, which
  writes it to the monitor over DDC/CI. `org.kde.ScreenBrightness` isn't used
  because it identifies monitors only by a `Label` (the model name), which is
  identical for two monitors of the same model.
- **Warmth** is KWin's Night Light (`kwinrc [NightColor]`). It is global, so it
  tints every screen.
- **Cutoff** is a transient `systemd-run --user` timer named `nightwatch-cutoff`.
- **State** (the restore point) lives in `${XDG_STATE_HOME:-~/.local/state}/nightwatch`.
  Re-running `on` while already on keeps the original restore point, so `off`
  still restores the real daytime values.

## Configuration

Right-click the widget → Configure Night Viewing:

- **Watch on**: lists every connected monitor by model and connector (for
  example "U2720Q (DP-1)"). The default, Automatic, picks the first
  connected monitor. A saved monitor that is unplugged stays selected and is
  shown as "not connected".
- **Other screens**: whether every other monitor goes to 0% while night viewing
  is on. This works with any number of monitors.

Monitors are stored by **connector**, not by name, so two identical models are
still told apart. Moving a cable to a different port means choosing the monitor again.

From a terminal, the same choices are options before the command:

```sh
nightwatch --display HDMI-A-1 --others leave on 2h 2000 4
nightwatch status       # lists connectors; * marks the watched monitor
```

`NIGHTWATCH_DISPLAY` and `NIGHTWATCH_OTHERS` set the same defaults.

The widget's text is wrapped in `i18n()`, so it can be translated. Plasma uses
the translation domain `plasma_applet_com.dakotatalley.nightwatch`. No
translations exist yet.

## Gotchas (KDE 6.7 / 6.8)

None of these are visible from the GUI or the man pages.

- **`kwriteconfig6` needs `--notify`**, or KWin ignores the change.
  `qdbus6 ... /KWin reconfigure` does not pick up Night Light edits.
- Night Light has only four keys: `Active` (needs `--type bool`), `Mode`
  (`Constant` | `DarkLight`), `DayTemperature`, `NightTemperature`. The
  temperature floor is 1000 K.
- **A plasmoid can't rely on `PATH` to find a script.** plasmashell gets the
  systemd user `PATH`, which has no `~/.local/bin`. Commands fail silently in
  `Plasma5Support.DataSource`, so the widget just looks dead. That's why the
  script ships inside the package and the widget resolves it with
  `Qt.resolvedUrl()`.
- **A `.plasmoid` is a zip**, so the script is always run as `bash <script>`
  (including from the systemd cutoff timer) rather than relying on its
  executable bit surviving.
- `kscreen-doctor --dpms-excluded` is broken in 6.7.5: it turns the whole
  `--dpms off` into a silent no-op. Plain `--dpms off` works and wakes on mouse
  movement.
- Bare `mpv` has no MPRIS support; install `mpv-mpris` for the cutoff to pause it.
- `systemd-run --description=` applies to the timer as well as the service, so
  "Started nightwatch cutoff" in the journal means *armed*, not *fired*. Check
  `journalctl --user -u nightwatch-cutoff.service`.

## Known issues

- **PowerDevil may miss a monitor at login.** With
  `--disable-watch-displays` in `~/.config/ddcutil/ddcutilrc` (a common fix for
  monitors that wake themselves in a loop), PowerDevil only looks for DDC displays at startup.
  A monitor slow to answer then is never registered, and KWin shows it as
  "Brightness control: unsupported". When the *watched* monitor is connected
  but in that state, `on`/`off` restart PowerDevil and wait up to 10 s for it.
  This happens at most twice per login (a counter in
  `$XDG_RUNTIME_DIR/nightwatch-heal-failures`, so it resets when you log in
  again). A monitor that is simply not connected never triggers a restart, and
  neither does the widget's 5-second `state` poll.
- **Toggling causes ~3 s of desktop lag.** This comes from Night Light's fade,
  not the script: KWin fades in ~70 steps and blocks its main thread ~30–85 ms
  on each one (measured on KWin 6.8.0 with a 60 Hz HDMI monitor). The fade is
  hardcoded and the D-Bus `preview` method fades too. A possible fix is to
  replace Night Light with the monitor's own RGB gain over DDC (VCP
  `0x16`/`0x18`/`0x1A`), which applies in one write and would warm only the
  watched monitor.

## License

MIT, see [LICENSE](LICENSE). `package.sh` also puts a copy inside the `.plasmoid`.
