# NotchDash

Claude Code / Codex quota and system stats, living under your MacBook's notch.

[中文说明](README.md)

![Collapsed](docs/screenshot-collapsed.png)

Hover to expand:

![Expanded](docs/screenshot-expanded.png)

## First, the notch itself does not light up

The notch is the physical camera housing — there are **no pixels** there. Nothing can be
displayed on it, ever.

What this kind of tool actually does is draw a pure-black window directly below the notch
so it blends seamlessly with the notch's own black. NotchDash does the same.

## Features

- **Claude Code / Codex quota** — used or remaining percentage, reset countdown, colored by state
- **System stats** — CPU, memory, live network throughput
- **Stock indices** — A-shares, US and HK indices, colored by gain/loss
- **Carousel** — rotate quota and market data in the collapsed bar without changing its width
- **Auto-avoidance** — measures where your menu bar icons actually are, then picks a layout
  that does not collide with them

## Where the quota data comes from

Two channels. The **local one always wins**; the API is only a fallback when local data is
missing or stale:

| Tool | Primary (local, no credentials) | Fallback (network) |
|---|---|---|
| Claude Code | `rate_limits` from the official statusline payload (v2.1.6+), persisted by `scripts/statusline.sh` | `api.anthropic.com/api/oauth/usage` |
| Codex | `rate_limits` in `token_count` events inside `~/.codex/sessions/**/*.jsonl` | `chatgpt.com/backend-api/wham/usage` |

The primary channel only reads local files — no credentials, no network. The tradeoff is that
data stops updating while Claude Code / Codex is not running (the UI marks it "X minutes ago").
The fallback uses the login state already on your machine to ask the vendor directly.

**The fallback is on by default and can be turned off.** It relies on undocumented endpoints,
so it may break whenever the vendor changes them — which is exactly why it is only a fallback.

## Install

Only Command Line Tools required — **no full Xcode needed**:

```bash
xcode-select --install     # if you have not already
git clone <this repo>
cd NotchDash
./install.sh               # build and install to ~/Applications
./install.sh --autostart   # also register a launch agent
```

### Or grab a release build

Download the zip from [Releases](../../releases), unpack it and drag `NotchDash.app`
into Applications.

**The first launch will be blocked**, with a message claiming the app "is damaged and
should be moved to the Trash". That message is misleading — nothing is damaged, the app
simply is not signed or notarized (which requires a $99/year Apple Developer account).
Either of these clears it:

**Option 1: command line (fastest)**

```bash
xattr -dr com.apple.quarantine /Applications/NotchDash.app
```

This only strips the quarantine flag macOS attaches to downloaded files. Double-click works
afterwards.

**Option 2: System Settings**

1. Double-click `NotchDash.app`, dismiss the warning
2. Open System Settings → Privacy & Security, scroll down
3. Under "Security" you will see "NotchDash was blocked" — click **Open Anyway**
4. Confirm once more

> Right-clicking the icon and choosing Open **no longer works** on macOS 15 and later.

Building from source with `./install.sh` avoids all of this — locally compiled binaries carry
no quarantine flag.

### Feeding it Claude Code quota

Point your statusline at the bundled relay script in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/your/path/minitool/scripts/statusline.sh"
  }
}
```

It copies the quota data aside, then forwards the original input downstream, so **your
terminal statusline keeps working unchanged**. It auto-detects claude-hud; set
`NOTCHDASH_DOWNSTREAM` to use something else.

> Back up your original `command` value first. `uninstall.sh` restores it automatically
> if the change was made by these scripts.

## When the panel covers menu bar icons

Menu bar icons fill from the right, and once the right side is full they **skip over the notch
and continue on the left** — so both sides can collide with the panel.

NotchDash measures this itself: it reads each status item's coordinates through the
accessibility API, computes the free space on either side of the notch, and picks a layout
that fits:

| Layout | Chosen when |
|---|---|
| Split across the notch | Both sides have room (best looking) |
| All on the left | Right side too tight, left side fits |
| Below the notch | Neither fits — stays off the menu bar entirely, but covers ~21pt of window content |

#### Accessibility permission

Reading status item coordinates goes through the accessibility API, so it needs permission:

1. On first launch NotchDash asks once — click "Open System Settings"
2. Or go to System Settings → Privacy & Security → Accessibility manually
3. Find **NotchDash** in the list and switch it on
4. No restart needed, it takes effect within 20 seconds

**Declining is fine** — everything still works, you just pick the layout yourself from the
`⋯` menu → "Collapsed layout".

When you may need to re-authorize:

- **After updating the app** — macOS identifies apps by signature, so replacing the `.app`
  can invalidate the grant. The symptom is auto-layout silently stopping. Remove NotchDash
  from the list (select it, press `−`) and add it again
- **Two NotchDash entries in the list** — delete the stale one

To check whether it currently has permission, look at `accessibility_authorized` in
`~/.notchdash/status.json`, or see whether the menu shows "Auto" as
"needs Accessibility permission".

## Configuration

Almost everything is in the right-click menu: display mode, carousel, indices, layout.
The config file at `~/.notchdash/config.json` is the fallback:

```json
{
  "oauth_fallback": true,
  "show_remaining": true,
  "carousel": true,
  "carousel_interval": 10,
  "red_up": true,
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

- `red_up` — `true` means red for gains (Chinese convention), `false` means green for gains
- `custom_sources` — any shell command; the first line of stdout is displayed.
  ⚠️ These run as you do. Do not paste configs you do not trust.

## Privacy

- The primary channel only reads local files and never touches the network
- The fallback reads login state already present on your machine (Claude: Keychain item
  `Claude Code-credentials`; Codex: `~/.codex/auth.json`) and sends it **only to each vendor's
  own domain**. Nothing is stored, cached or forwarded anywhere else
- Tokens are never refreshed by this app — that is left to Claude Code / Codex themselves

## Adapting to your machine

Notch size, wing widths and panel width are all measured at runtime. No hardcoded model numbers:

- Notch dimensions come from `NSScreen.safeAreaInsets` and `auxiliaryTopLeft/RightArea`
- Collapsed wing width is derived from the actual rendered width of its content, so a different
  font, language or longer numbers will not clip
- Re-measures on resolution/scaling changes, display hotplug and lid open/close
- With an external display attached, the panel stays on the screen that has the notch
- Machines without a notch degrade to a small panel centered at the top of the screen

## Troubleshooting

```bash
./build/NotchDash.app/Contents/MacOS/NotchDash --probe          # all data sources
./build/NotchDash.app/Contents/MacOS/NotchDash --probe-oauth    # fallback channel only
./build/NotchDash.app/Contents/MacOS/NotchDash --probe-menubar  # menu bar space
```

The app also renders its own UI to a PNG — no screen recording permission needed:

```bash
NOTCHDASH_DEMO=expanded ./build/NotchDash.app/Contents/MacOS/NotchDash --snapshot /tmp/a.png
```

Runtime state is written to `~/.notchdash/status.json`.

## Notes on the implementation

- Swift + SwiftUI + AppKit; an `NSPanel` above the menu bar level
- **Deliberately avoids SwiftUI macros** (`@State` and friends): Command Line Tools ships no
  `SwiftUIMacros` plugin, so using them would force everyone to install the full Xcode
- The window stays at its maximum size and the content resizes inside it, so expanding and
  collapsing never resizes the window — no animation jitter

## License

MIT
