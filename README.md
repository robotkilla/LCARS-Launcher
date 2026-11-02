# LCARS Launcher

Fullscreen launcher for Omarchy Quattro (`wesley.lcars-launcher`). Classic LCARS chrome — wide left rail, elbow caps, and square-cut bars — in the palette from [thelcars.com](https://www.thelcars.com/). It is an `overlay` plugin and runs inside the `omarchy-shell` process that is already on the desktop.

It walks the same system menu as stock Omarchy, including `~/.config/omarchy/extensions/omarchy-menu.jsonc`, and lists installed applications. Typing searches the menu you are in and everything under it. Favorites and frecency are kept between sessions.

The upper rail shows the hostname from `/etc/hostname`, the clock, and the IPv4 address of the default route.

## Requirements

Omarchy Quattro, with `omarchy-shell` running. The plugin installs no packages and starts no second Quickshell.

## Install

Omarchy asks you to confirm before it clones a plugin. Plugins run unsandboxed, as your user, inside `omarchy-shell`.

```sh
omarchy plugin add https://github.com/<github-user>/LCARS-Launcher.git --enable
```

Use the public GitHub repository root, with `.git` and with no extra path. The plugin id is `wesley.lcars-launcher`.

The same install is **Setup › Plugins › Add Plugin**. Paste the repository URL and enable LCARS Launcher when asked.

Installing does not change keybindings, `shell.json`, or anything under `/usr/share/omarchy`.

## Open it

```sh
omarchy-shell shell toggle wesley.lcars-launcher '{}'
omarchy-shell shell summon wesley.lcars-launcher '{"menu":"apps"}'
omarchy-shell shell hide wesley.lcars-launcher
```

`{}` opens the system menu. `{"menu":"apps"}` opens Apps. `toggle` closes the overlay when it is already open. `hide` always closes it.

## Keys

- **Enter** or **Right** opens the highlighted submenu, or runs the highlighted command. Right does this when the query is empty, so it does not move the caret while you are typing.
- **Backspace** or **Left** goes up one menu when the query is empty.
- **Esc** clears the query. With an empty query, Esc closes the overlay.
- **Up** and **Down** move the highlight. **Page Up** and **Page Down** move it by a page.
- **Ctrl+F**, **Ctrl+D**, or **Ctrl+P** pins or unpins the highlighted row. A filled mark means the row is a favorite.
- Click a row to activate it.

A failed `when:` expression hides that row. A true `checked:` expression adds a mark. Both run together, once, through `bash`. Until that batch finishes, a `when:` row stays visible.

Menu commands run with `bash -lc`, the same way the stock Omarchy menu runs them. Applications launch with `uwsm-app -- gtk-launch`.

## Put it on Super+Space

Add this to `~/.config/hypr/bindings.lua` yourself. The plugin never writes that file.

```lua
-- SUPER+SPACE was the Omarchy menu (omarchy-menu toggle).
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "LCARS launcher", "omarchy-shell shell toggle wesley.lcars-launcher '{}'")

-- SUPER+ALT+SPACE was the Apps menu (omarchy-menu toggle apps).
hl.unbind("SUPER + ALT + SPACE")
o.bind("SUPER + ALT + SPACE", "LCARS launcher", [[omarchy-shell shell toggle wesley.lcars-launcher '{"menu":"apps"}']])
```

Then run `hyprctl reload` and `hyprctl configerrors`.

Super+Space opens the system menu. Super+Alt+Space opens Apps. Either chord closes the overlay when it is already open. Super+Shift+Space, Super+Ctrl+Space, and Super+Shift+Ctrl+Space stay on the top bar, the background switcher, and the theme menu.

## Remove

```sh
omarchy plugin remove wesley.lcars-launcher
```

**Setup › Plugins › Remove Plugin** does the same thing. Omarchy disables the plugin and deletes the installed copy. A git install leaves the upstream repository in place.

If you added the keybindings above, delete those lines from `~/.config/hypr/bindings.lua` and reload Hyprland. Otherwise those chords still call a plugin that is gone.

Favorites and frecency stay in `~/.local/state/omarchy/lcars-launcher-usage.json`. Delete that file when you want the launcher to forget them.

## License and dependencies

Plugin code is MIT. See [LICENSE](LICENSE).

Antonio Regular and Antonio Bold are bundled in `fonts/` and remain under the [SIL Open Font License 1.1](fonts/OFL.txt). Copyright 2013 The Antonio Project Authors ([antonioFont](https://github.com/googlefonts/antonioFont)). Designed by Vernon Adams. The font files are unmodified and are not covered by the MIT license.

Nothing else is downloaded. At runtime the overlay uses programs that already ship with Omarchy:

- `bash`, for menu `when:` and `checked:` checks, and for menu actions
- `uwsm-app` and `gtk-launch`, to start applications
- `ip`, to read the IPv4 address on the rail

It writes one file, `~/.local/state/omarchy/lcars-launcher-usage.json`.

`Model.test.js` is a source-tree check and needs Node. The running plugin does not.

## Files

```
manifest.json                 plugin contract
Launcher.qml                  overlay entry point
Model.js                      menu tree, search, frecency, favorites
Model.test.js                 node checks for Model.js
components/                   frame, bars, and result rows
fonts/Antonio-Regular.ttf     bundled Antonio, SIL OFL 1.1
fonts/Antonio-Bold.ttf
fonts/OFL.txt                 font license
LICENSE                       MIT license for the plugin code
```

Before publishing, from the repository root:

```sh
omarchy plugin validate .
```

QML saved under `~/.config/omarchy/plugins/wesley.lcars-launcher/` reloads on its own. After a change to `Model.js`, run `omarchy restart shell`.
