# Internet Status

A lightweight macOS menu bar app that continuously monitors your internet connection quality and displays it as a colored sphere.

## Why?

Sometimes you need a quick, always-visible indicator of how your internet is doing — no dashboards, no terminal windows, just a glance at the menu bar:

- **On a plane** with spotty Wi-Fi — know instantly when the connection drops or degrades
- **Working from a cafe or hotel** — catch connectivity issues before your video call does
- **Debugging network problems** — see packet loss and latency trends at a glance without running a terminal ping
- **Tethering from your phone** — monitor whether your mobile connection is holding up

## How It Works

The app pings a target host once per second and tracks results over a configurable sample window.

**Color** indicates packet loss:
| Color | Packet Loss |
|-------|------------|
| Green | 0% |
| Yellow | > 0 – 20% |
| Orange | > 20 – 80% |
| Red | > 80% |

**Size** indicates average latency — the sphere shrinks as latency increases (relative to a background ring at full size so the change is visible). Full size at your configured minimum ping, half size at your configured maximum.

**Hover** over the icon to see a ping summary: packet loss %, sample count, and avg/min/max latency.

## Controls

- **Left-click** the icon to pause/resume pinging (grey sphere when paused)
- **Right-click** to open the settings menu:
  - **Ping Target** — google.com, 1.1.1.1, 8.8.8.8, 9.9.9.9, 208.67.222.222
  - **Ping Range** — configures which latency range maps to icon size
  - **Sample Window** — number of packets to consider (5, 10, 30, 60, 300)
  - **Launch at Login** — enabled by default

## Building

Requires Xcode command line tools (`xcode-select --install`).

```bash
make        # build
make run    # build and launch
make clean  # remove build artifacts
```

The compiled app is at `build/Internet Status.app` — you can copy it to `/Applications` if you like.

## Technical Details

- **Language:** Swift + AppKit (no SwiftUI, no Electron, no frameworks)
- **Binary size:** ~95 KB
- **Memory:** ~10 MB typical
- **CPU:** near zero — one lightweight `ping -c 1` per second
- **macOS 13+** required (uses `SMAppService` for login item management)
- Single-instance enforced — launching a second copy exits immediately
