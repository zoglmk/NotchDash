# Configuration and internals

[← Back to README](../README.en.md)

Most options are reachable from the right-click menu. This document is for going deeper.

## Config file

Lives at `~/.notchdash/config.json`. Changes take effect within 20 seconds.

```json
{
  "oauth_fallback": true,
  "show_remaining": true,
  "carousel": true,
  "carousel_interval": 10,
  "red_up": true,
  "collapsed_layout": "left",
  "stocks": {
    "interval": 60,
    "items": [
      { "label": "S&P", "code": "gb_inx" },
      { "label": "Nasdaq", "code": "gb_ixic" }
    ]
  },
  "custom_sources": [
    { "label": "load", "command": "sysctl -n vm.loadavg | awk '{print $2}'", "interval": 20 }
  ]
}
```

| Field | Meaning |
|---|---|
| `oauth_fallback` | Whether the API fallback may be used. `false` means no network access and no credential reads at all |
| `show_remaining` | `true` shows remaining quota, `false` shows used quota |
| `carousel` / `carousel_interval` | Carousel switch and interval in seconds, minimum 2 |
| `red_up` | `true` colors gains red (Chinese convention), `false` colors gains green. Applies to both indices and custom sources |
| `collapsed_layout` | Collapsed layout: `left` (default) or `below` |

Whichever number is shown, the color always follows the used percentage. Below 30% remaining it turns red.

## Market indices

Tick common indices under "Indices" in the right-click menu, or use "Add symbol" for an individual stock; its name is fetched automatically. Refresh interval ranges from 10 seconds to 5 minutes. Presets cover the SSE Composite, SZSE Component, ChiNext, CSI 300, Hang Seng, Dow Jones, Nasdaq and S&P 500.

You can also edit the config file directly. Common codes:

| Code | Symbol | Code | Symbol |
|---|---|---|---|
| `s_sh000001` | SSE Composite | `gb_dji` | Dow Jones |
| `s_sz399001` | SZSE Component | `gb_ixic` | Nasdaq |
| `s_sz399006` | ChiNext | `gb_inx` | S&P 500 |
| `s_sh000300` | CSI 300 | `int_hangseng` | Hang Seng |

For individual stocks use the plain code, such as `sh600519` or `sz000001`.

Data comes from Sina Finance's public endpoint and needs no API key. During trading hours it is a snapshot; free endpoints typically lag by seconds to minutes, which together with the polling interval makes it near real time. Outside trading hours it shows the last close.

The bottom row of the expanded panel wraps to fit the panel width. Wider screens fit more per row, up to three rows.

## Custom sources

Each entry runs a shell command and displays the first line of stdout, up to 24 characters. A command running longer than 5 seconds is terminated. Output containing a signed percentage is colored as a gain or loss.

Commands run as the current user. Do not paste configurations from untrusted sources.

## Routing Claude Code quota through the local channel

By default Claude Code's quota is queried through the official API, which needs Keychain access and network access. To avoid both, switch to the statusline channel.

Claude Code puts quota data in the statusline payload. Point `~/.claude/settings.json` at this project's forwarding script to capture it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/your/path/NotchDash/scripts/statusline.sh"
  }
}
```

The script copies the quota data for this tool and forwards the original payload downstream, so your terminal statusline keeps working. It detects claude-hud automatically; for anything else set `NOTCHDASH_DOWNSTREAM`.

Back up your existing `command` value first. If the change was made by this project's script, `uninstall.sh` restores it.

The two channels compared:

| | statusline | API |
|---|---|---|
| Network access | No | Yes |
| Reads credentials | No | Yes, the existing local session |
| Freshness | Live while Claude Code runs | Always available |
| Needs setup | Yes | No |

Both can be enabled at once. The statusline channel wins, and the API takes over once its data goes stale. Codex quota is read straight from local session logs and needs no setup.

## Where the data comes from

| Tool | Local channel | API fallback |
|---|---|---|
| Claude Code | `rate_limits` in the statusline payload (v2.1.6+) | `api.anthropic.com/api/oauth/usage` |
| Codex | `rate_limits` in `token_count` events under `~/.codex/sessions/**/*.jsonl` | `chatgpt.com/backend-api/wham/usage` |

The local channel only reads local files, touching no credentials and no network. The tradeoff is that data stops updating when the tool is not running, and the panel marks how old it is.

The API fallback uses the session you already have (Claude reads the `Claude Code-credentials` Keychain entry, Codex reads `~/.codex/auth.json`) and sends it only to the respective official domain. Nothing is stored, written to disk or forwarded. This app never refreshes tokens; Claude Code and Codex maintain them.

The fallback relies on undocumented endpoints and may break when they change, which is why it is only a backup. Turn it off with `oauth_fallback`.

After switching accounts, the statusline channel reflects the new one immediately; the API fallback lags by at most one rate-limit window. Codex session logs record no account information, so the app keys off `account_id` in `~/.codex/auth.json`: when it changes, only logs written after the switch are used and the API is re-queried right away. Logging out deletes `auth.json`, and the panel then shows "未登录 Codex" instead of carrying over the previous account's numbers.

If Claude Code or Codex is not installed, that entry simply does not appear. With neither installed, the collapsed panel shows CPU and memory instead.

## What some states mean

**Quota shows "未开始" (not started)**: rate limit windows roll, starting from the first request of the cycle rather than resetting on a fixed schedule. Before the window starts, the server returns "now plus a full window" as a placeholder, which drifts forward with the clock, so a countdown would be meaningless. Send one message and the countdown settles.

**Codex shows stale**: normal if you have not used Codex recently. Local data older than 15 minutes counts as stale, and the API fallback takes over when enabled.

**Time instead of a percentage**: past 99.5% used, "how long until it comes back" is more useful than "0% left".

## Compatibility

Notch size, menu bar height and panel width are all measured at runtime. No machine-specific numbers are hard-coded.

- Notch size comes from `NSScreen.safeAreaInsets` plus `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
- Collapsed width follows the actual rendered width of the content, so changing font, language or digit count never clips it
- Resolution and scaling changes, external display hotplug and lid open/close all trigger a re-measure
- With an external display connected, the panel stays on the screen that has the notch
- Machines without a notch work too; the panel sits centered at the top of the screen

Requires macOS 13 or later.

## Debugging

```bash
NotchDash --probe           # print every data source's current state and failure reason
NotchDash --probe-oauth     # test the API fallback only
```

The panel can render itself to an image, no screen recording permission needed:

```bash
NOTCHDASH_DEMO=expanded NotchDash --snapshot /tmp/a.png
```

Runtime state is written to `~/.notchdash/status.json`.

A few switches exist to reproduce specific environments. Normal use needs none of them:

```bash
NOTCHDASH_SIMULATE=no-quota      # pretend Claude Code and Codex are not installed
NOTCHDASH_SIMULATE=codex-logout  # pretend Codex is logged out
NOTCHDASH_SIMULATE=empty-quota   # pretend both are installed but no quota data arrives
NOTCHDASH_FAKE="35,25"           # pin both remaining percentages, for checking color thresholds
```

## Implementation notes

Swift with SwiftUI and AppKit, using an `NSPanel` placed above the menu bar window level.

No SwiftUI macros (`@State` and friends): Command Line Tools ships without the `SwiftUIMacros` plugin, and using them would force a full Xcode install to build.

The window keeps a fixed maximum size and the content controls the drawn area, so expanding and collapsing never resizes the window.

The notch is the physical camera housing, an area with no pixels behind it. This tool draws a pure black window directly below it that joins the notch's own black, so it reads as if the notch got bigger.
