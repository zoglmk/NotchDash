# NotchDash

Shows Claude Code / Codex quota, system stats and stock indices under the MacBook notch.

[中文](README.md)

## What it looks like

Collapsed, it shows just the key numbers beside the notch, blending into its black:

![collapsed](docs/screenshot-collapsed.png)

Hover to expand the full panel:

![expanded](docs/screenshot-expanded.png)

## Features

- **Quota**: remaining or used percentage for Claude Code and Codex, reset countdown, colored by state. When quota runs out it switches to showing when it comes back
- **System stats**: CPU, memory, live network speed
- **Market indices**: Chinese A-shares, Hong Kong and US markets, colored by gain or loss, with either color convention
- **Carousel**: the collapsed panel can alternate between quota and indices without changing width
- **Custom sources**: display the output of any shell command

It works without Claude Code or Codex installed, if you only want the indices.

## Installation

### From releases

Download the zip from [Releases](https://github.com/zoglmk/NotchDash/releases), unpack it and drag `NotchDash.app` into Applications, then double-click.

The first launch reports "NotchDash is damaged and can't be opened". That is the standard wording for unsigned apps; see the FAQ below.

### From source

Only Command Line Tools are needed, not a full Xcode install.

```bash
xcode-select --install          # if not already installed
git clone https://github.com/zoglmk/NotchDash.git
cd NotchDash
./install.sh                    # build and install into /Applications
./install.sh --autostart        # also register a login item
```

Builds from source are not blocked by Gatekeeper.

### After opening

No configuration needed. Quota, system stats and indices show up right away. The first quota read may raise a Keychain prompt; click Allow. The app uses it to read Claude Code's existing session to query quota, and never stores or forwards it.

Everything else lives in the right-click menu: indices, carousel, gain/loss colors, collapsed layout and display mode. For finer control, or to avoid network and credential access entirely, see [Configuration and internals](docs/configuration.en.md).

## FAQ

### "NotchDash is damaged and can't be opened"

This project is not signed or notarized (that needs a $99/year developer account), so downloaded builds are blocked by Gatekeeper. The file is not actually damaged.

From the command line:

```bash
xattr -dr com.apple.quarantine /Applications/NotchDash.app
```

Or through System Settings: double-click the app, click Done in the dialog, open System Settings → Privacy & Security, scroll down to the Security section, click "Open Anyway" and confirm.

Since macOS 15, right-clicking and choosing Open no longer works.

### Claude Code shows "waiting for statusline"

Neither channel returned data. Run `NotchDash --probe-oauth` to see why, usually a denied Keychain prompt or an expired session; signing into Claude Code again fixes it. If you turned off `oauth_fallback`, the statusline channel is required, see [Configuration and internals](docs/configuration.en.md).

It also shows up when Claude Code has just started and has not answered anything yet. Send one message.

### The panel covers menu bar icons

Menu bar icons fill from the right, and once the right side is full they skip over the notch and continue on the left, so the left side can collide too. Switch layouts under "Collapsed layout" in the `⋯` menu:

| Layout | What it does |
|---|---|
| All on the left (default) | The panel only extends to the left of the notch, never to the right |
| Below the notch | Stays off the menu bar entirely, but covers about 21pt of window content |

If icons fill up the left side, switch to below the notch, which never collides with any icon.

### Quitting

Right-click the panel, or expand it and click `⋯` in the top right, then choose "退出 NotchDash". `pkill -f NotchDash` works too.

## Uninstall

```bash
./uninstall.sh
```

Stops the process, removes the login item and the app, and restores the statusline entry in `~/.claude/settings.json`. The config and cache directory `~/.notchdash/` is kept.

## More

- [Configuration and internals](docs/configuration.en.md): config fields, index codes, the statusline channel, data sources and privacy, debugging
- Requires macOS 13 or later. Machines without a notch work too; the panel sits centered at the top of the screen

## License

MIT
