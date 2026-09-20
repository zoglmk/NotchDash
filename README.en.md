# NotchDash

Displays Claude Code / Codex quota, system stats and market indices under the MacBook notch.

[中文说明](README.md)

## Screenshots

Collapsed, showing only key numbers beside the notch and blending into its black:

![Collapsed](docs/screenshot-collapsed.png)

Hover to expand:

![Expanded](docs/screenshot-expanded.png)

The notch is the physical camera housing. There are no pixels there and nothing can be
displayed on it. What this tool does is draw a black window directly below the notch so that
it joins the notch's own black, making the notch appear larger.

## Features

- Claude Code and Codex quota: remaining or used percentage, reset countdown, colored by
  state. Switches to showing the recovery time once the quota runs out
- System stats: CPU, memory, live network throughput
- Market indices: A-shares, Hong Kong and US, colored by gain or loss
- Carousel: alternates between quota and market data in the collapsed bar without changing
  its width
- Auto-avoidance: reads where menu bar icons actually are and picks a layout that does not
  overlap them
- Custom sources: display the output of any shell command

## Installation

### From source

Only Command Line Tools is required. A full Xcode installation is not needed.

```bash
xcode-select --install          # if not already installed
git clone https://github.com/zoglmk/NotchDash.git
cd NotchDash
./install.sh                    # build and install to ~/Applications
./install.sh --autostart        # also register a launch agent
```

### From releases

Download the zip from [Releases](https://github.com/zoglmk/NotchDash/releases), unpack it and
move `NotchDash.app` into Applications. The first launch needs one extra step, see
Troubleshooting below.

### Connecting Claude Code quota

Claude Code exposes quota through its statusline payload. Point it at the relay script in
`~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/your/path/NotchDash/scripts/statusline.sh"
  }
}
```

The script copies the quota data for this tool, then forwards the original input downstream,
so your terminal statusline keeps working as before. It detects claude-hud automatically; set
`NOTCHDASH_DOWNSTREAM` to use a different program.

Back up your existing `command` value first. If the change was made by the scripts in this
project, `uninstall.sh` restores it automatically.

Codex requires no additional setup.

## Troubleshooting

### "NotchDash is damaged and can't be opened"

This project is not signed or notarized, which requires an Apple Developer account at $99 per
year. Downloaded builds are blocked by Gatekeeper. The file is not damaged; this is the
standard macOS wording for unsigned applications.

Option 1, command line:

```bash
xattr -dr com.apple.quarantine /Applications/NotchDash.app
```

Option 2, System Settings:

1. Double-click the app, dismiss the warning
2. Open System Settings → Privacy & Security and scroll down
3. Click "Open Anyway" under Security
4. Confirm once more

Right-clicking the icon and choosing Open no longer works on macOS 15 and later. Builds
compiled from source are unaffected.

### Automatic layout does not work

Auto-avoidance needs Accessibility permission to read the coordinates of menu bar icons.

1. The app asks once on first launch; click "Open System Settings"
2. Or open System Settings → Privacy & Security → Accessibility manually
3. Find NotchDash in the list and switch it on
4. No restart required, it takes effect within 20 seconds

The app works without this permission; you simply pick the layout yourself from the
"Collapsed layout" submenu.

Updating the app may invalidate the grant. macOS identifies applications by signature, so
replacing the `.app` can silently disable auto-layout. Select NotchDash in the list, remove it
with the `−` button and add it again. If two NotchDash entries appear, delete the stale one.

The current state is recorded as `accessibility_authorized` in `~/.notchdash/status.json`.

### Claude Code stays on "waiting for statusline"

The statusline is not pointing at the relay script, or the current session has not produced
its first model response yet.

### Codex shows "stale"

Normal if Codex has not been used recently. Local data older than 15 minutes is considered
stale, and the API fallback takes over when enabled.

### The panel covers menu bar icons

Menu bar icons fill from the right, and once the right side is full they skip over the notch
and continue on the left, so both sides can collide with the panel. With Accessibility
permission granted, the app measures the free space on each side and picks a layout:

| Layout | Used when |
|---|---|
| Split across the notch | Both sides have room |
| All on the left | Right side too tight, left side fits |
| Below the notch | Neither fits. Stays off the menu bar but covers about 21pt of window content |

It can also be set manually from the menu.

### Quitting

Right-click the panel, or click `⋯` after expanding, and choose "Quit NotchDash". Running
`pkill -f NotchDash` also works.

## Configuration

Most options are available from the right-click menu, including display mode, carousel,
indices and layout. The config file is `~/.notchdash/config.json` and changes take effect
within 20 seconds.

```json
{
  "oauth_fallback": true,
  "show_remaining": true,
  "carousel": true,
  "carousel_interval": 10,
  "red_up": false,
  "auto_layout": true,
  "collapsed_layout": "split",
  "stocks": {
    "interval": 60,
    "items": [
      { "label": "S&P", "code": "gb_inx" },
      { "label": "NASDAQ", "code": "gb_ixic" }
    ]
  },
  "custom_sources": [
    { "label": "Load", "command": "sysctl -n vm.loadavg | awk '{print $2}'", "interval": 20 }
  ]
}
```

| Field | Description |
|---|---|
| `oauth_fallback` | Whether the API fallback is allowed. Set to `false` for no network access and no credential reads |
| `show_remaining` | `true` shows remaining quota, `false` shows used quota |
| `carousel` / `carousel_interval` | Carousel switch and interval in seconds, minimum 2 |
| `red_up` | `true` colors gains red (Chinese convention), `false` colors gains green |
| `auto_layout` | Whether to pick the layout from measured menu bar usage. Requires Accessibility permission |
| `collapsed_layout` | Layout used when auto-layout is off: `split`, `left` or `below` |

Regardless of display mode, colors are always computed from the used percentage. Anything
below 30% remaining turns red.

### Market indices

Select common indices from the "Indices" submenu, or use "Add symbol" to enter an individual
stock; its name is fetched automatically. Refresh interval ranges from 10 seconds to 5 minutes.

Common codes:

| Code | Symbol | Code | Symbol |
|---|---|---|---|
| `gb_dji` | Dow Jones | `s_sh000001` | SSE Composite |
| `gb_ixic` | NASDAQ | `s_sz399001` | SZSE Component |
| `gb_inx` | S&P 500 | `int_hangseng` | Hang Seng |

Individual stocks use their plain code, such as `sh600519` or `sz000001`.

Data comes from a public Sina Finance endpoint and requires no API key. During trading hours
it is a quote snapshot; free endpoints typically lag by seconds to minutes, and with the
polling interval on top the result is near real time. Outside trading hours it shows the last
close.

### Custom sources

Each entry runs a shell command and displays the first line of stdout, up to 24 characters.
A command is terminated if it runs longer than 5 seconds. Output containing a signed
percentage is colored as a gain or loss.

Commands run as your user. Do not use configurations from untrusted sources.

## Data sources

Quota data has two channels. The local one takes priority; the API is used only when local
data is missing or stale:

| Tool | Local channel | API fallback |
|---|---|---|
| Claude Code | `rate_limits` in the statusline payload (v2.1.6+) | `api.anthropic.com/api/oauth/usage` |
| Codex | `rate_limits` in `token_count` events in `~/.codex/sessions/**/*.jsonl` | `chatgpt.com/backend-api/wham/usage` |

The local channel only reads files on your machine, with no credentials and no network
access. The tradeoff is that data stops updating while the corresponding program is not
running; the UI shows the last update time.

The API fallback uses login state already present on your machine (Claude reads the Keychain
item `Claude Code-credentials`, Codex reads `~/.codex/auth.json`) and sends it only to each
vendor's own domain. Nothing is stored, cached or forwarded. This app never refreshes tokens;
that is left to Claude Code and Codex.

The fallback relies on undocumented endpoints and may break when vendors change them, which
is why it is only a fallback. It can be disabled with `oauth_fallback`.

After switching accounts, the Claude Code statusline channel reflects the new account
immediately, while the API fallback may lag by one rate-limit window (5 minutes). Codex
session logs contain no account information, so the app uses `account_id` from
`~/.codex/auth.json` as the reference: when it changes, only logs written after that point are
used, and the API is queried again immediately.

## Compatibility

Notch dimensions, menu bar height and panel width are all measured at runtime. No model
specific values are hardcoded.

- Notch dimensions come from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea`
- Collapsed width is derived from the actual rendered width of the content, so a different
  font, language or number of digits will not clip
- Re-measured on resolution and scaling changes, display hotplug, and lid open or close
- With an external display attached, the panel stays on the screen that has the notch
- Machines without a notch are supported; the panel is centered at the top of the screen

Requires macOS 13 or later.

## Debugging

```bash
NotchDash --probe           # print every data source with its state and failure reason
NotchDash --probe-oauth     # test the API fallback only
NotchDash --probe-menubar   # print menu bar free space and the layout decision
```

The UI can render itself to an image without screen recording permission:

```bash
NOTCHDASH_DEMO=expanded NotchDash --snapshot /tmp/a.png
```

Runtime state is written to `~/.notchdash/status.json`.

Running these from a terminal inherits the terminal's permissions, which may differ from those
of the app launched by double-clicking.

## Uninstall

```bash
./uninstall.sh
```

Stops the process, removes the launch agent and the app, and restores the statusline entry in
`~/.claude/settings.json`. The config directory `~/.notchdash/` is kept.

## Implementation notes

Swift with SwiftUI and AppKit, using an `NSPanel` placed above the menu bar window level.

SwiftUI macros (`@State` and similar) are deliberately avoided: Command Line Tools ships no
`SwiftUIMacros` plugin, so using them would require a full Xcode installation to build.

The window stays at its maximum size and the content controls the drawn area, so expanding and
collapsing never resizes the window.

## License

MIT
