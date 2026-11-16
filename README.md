# Jarvis

A macOS menu bar monitor for CPU, memory, battery, temperature, Wi-Fi and the busiest apps. The menu bar shows CPU, memory and battery percentages; clicking it opens a popover with the detail.

Requires macOS 15 or later on Apple silicon, and Swift 6.2 to build.

## Install the downloaded app

1. Download `Jarvis.zip` from the [latest release](https://github.com/bikundo/jarvis-monitor/releases/latest) and unzip it.
2. Move `Jarvis.app` to the Applications folder and open it. macOS blocks it the first time, because the app is not notarized by Apple.
3. Open System Settings > Privacy & Security, scroll to the message about Jarvis and choose "Open Anyway".

After that it opens normally. The first time you open the popover, macOS asks for Location permission; see the Wi-Fi note below for why.

## Build from source

```sh
./Scripts/bundle.sh --install
```

This builds a release binary, assembles `build/Jarvis.app`, signs it with the first "Apple Development" identity in the keychain (override with `JARVIS_SIGNING_IDENTITY`, or it falls back to ad hoc signing), copies it to `/Applications` and launches it. Without `--install` it only builds. The script refuses to run on battery power.

Run the unit tests with `swift test`.

## What the popover shows

- CPU: total load split into apps and system, the last 60 samples, per-core load and processor temperature.
- Memory: used memory split into apps, system and compressed, plus free, cached, swap and memory pressure.
- Battery: level, time remaining, the last 24 hours of level, health, cycle count and the Mac's age.
- Wi-Fi: network name, signal quality, band, current download and upload speed, and data used since startup.
- Apps: the five busiest apps, sorted by CPU or memory.

Settings chooses which of CPU, memory and battery appear in the menu bar, and whether Jarvis opens at login.

## How it keeps its own cost low

- With the popover closed, each sample is two Mach calls (`host_statistics` for CPU ticks, `host_statistics64` for memory pages). The menu bar image is redrawn only when its text changes.
- One timer with leeway: every 3 s on mains, every 5 s on battery or in Low Power Mode, every 2 s while the popover is open, stopped while the display sleeps or the screen is locked.
- Battery state arrives through an IOKit notification; nothing polls it.
- Per-core load, swap, memory pressure, temperatures, Wi-Fi signal, network traffic and the app list are sampled only while the popover is open.
- The popover's SwiftUI views exist only while it is open.
- Jarvis makes no network requests.

## App list

macOS does not let an unprivileged app read the memory of processes owned by other users, such as WindowServer. Jarvis reads its own user's processes directly every 2 s and fills in the rest by running `/usr/bin/top` once when the popover opens and every 15 s while it stays open. CPU figures for those system processes are averages over that 15 s window. One `top` run costs roughly a second of CPU time, which is why it never runs with the popover closed. Helper processes are added to their app, so "Brave Browser" is one row.

## Temperature, Wi-Fi and battery history

- Processor temperature is the average of the chip's die sensors, read through IOKit's HID event system. Those functions are not public API.
- The Wi-Fi network name needs Location permission, because macOS gives it to no app without that. Jarvis does not read the location itself.
- macOS truncates per-interface byte counters to 32 bits for third-party apps, so the "data used since startup" figure comes from one `/usr/sbin/netstat` run each time the popover opens.
- macOS offers no battery level history, so Jarvis records the level itself and keeps the last 24 hours.
- "Age" counts from the creation date of `/private/var/db/.AppleSetupDone`, the day this copy of macOS was first set up.

## Where things are stored

Preferences and battery history are kept in `UserDefaults` for `app.jarvis.monitor`. Nothing is written to the keychain.

## Licence

MIT. See `LICENSE`.
