# HyperTouch

Touch response and system responsiveness tuning for **Poco X6 Pro 5G / Redmi K70E (duchamp)**, built without requiring kernel modifications — everything runs as a Magisk/KernelSU module against existing driver and userspace interfaces.

Works with **Magisk**, **KernelSU**, **KernelSU-Next**, and **SukiSU Ultra**. WebUI needs one of the KernelSU-family managers (or a standalone viewer like KsuWebUIStandalone/MMRL) — plain Magisk manager doesn't render WebUIs.

## Features

| Feature | Layer | Status | Notes |
|---|---|---|---|
| Boosted touch report rate | Kernel (sysfs) | ✅ Working | `duchamp` only — see [Device support](#device-support) |
| Disable PowerKeeper throttling | System | ✅ Working | No-ops safely on non-HyperOS ROMs |
| Battery temp override | Kernel (sysfs) | ✅ Working, opt-in | Off by default — hides real overheating from the system |
| Smooth Touch (animation scale) | Userspace | ✅ Working | Kernel-independent, works on any device/ROM |
| Priority Apps (background exemption) | Userspace | ✅ Working | Kernel-independent, works on any device/ROM |
| TG Lag Fix | Userspace | 🧪 Experimental | Convenience preset of Priority Apps — see [below](#tg-lag-fix) |
| Touch sensitivity / edge (glove) / palm rejection | Kernel (sysfs) | ⏳ Pending | Needs real node names — see [Contributing](#contributing) |
| WebUI (Material / MIUI themes) | — | ✅ Working | Multi-page: Home, Tweaks, Apps, Settings |

## Installation

1. Flash `HyperTouch.zip` in your manager.
2. Reboot, **or** open the module's Action/WebUI afterward to apply without rebooting.
3. Updating later preserves your `settings.conf` automatically — it isn't reset to defaults.

## WebUI

Four sections, reachable from the bottom nav:

| Page | Contains |
|---|---|
| **Home** | Quick toggles for the tweaks you'll touch most, plus Apply Now |
| **Tweaks** | Every device-level setting, grouped by category |
| **Apps** | TG Lag Fix + custom Priority Apps list |
| **Settings** | UI style (Material/MIUI), module info, Reset/Revert, links |

Switch **Material ↔ MIUI** anytime from Settings → Appearance — it's a full visual reskin (color, corner radius, iconography), not just an accent swap, and takes effect instantly.

## settings.conf reference

Edit by hand or through the WebUI — both write the same file, so nothing gets out of sync.

| Key | Values | Default | Reboot needed? |
|---|---|---|---|
| `REPORT_RATE_MODE` | `0` stock / `1` boosted | `1` | No |
| `DISABLE_POWERKEEPER` | `0` / `1` | `1` | No |
| `SPOOF_BATTERY_TEMP` | `0` / `1` | `0` | No |
| `TOUCH_SENSITIVITY_PATH` / `_VALUE` | sysfs path / value | blank | No |
| `TOUCH_EDGE_PATH` / `_VALUE` | sysfs path / value | blank | No |
| `PALM_REJECT_PATH` / `_VALUE` | sysfs path / value | blank | No |
| `SMOOTH_TOUCH_MODE` | `0` stock / `1` fast / `2` instant | `1` | No |
| `PRIORITY_APPS` | space-separated package names | blank | No |
| `TG_LAG_FIX` | `0` / `1` | `0` | No |
| `UI_STYLE` | `material` / `miui` | `material` | No (WebUI only) |
| `FORCE_EXPERIMENTAL` | `0` / `1` | unset | No |

Everything here applies live through `apply.sh` — nothing in this table needs a reboot.

## Management CLI

`action.sh` is what runs when you tap **Action** in your manager, and also works from a terminal:

```
action.sh                   re-apply current settings
action.sh status             show current settings + device profile
action.sh enable <feature>   boost | powerkeeper | battery-spoof | tg-fix
action.sh disable <feature>  (same feature names)
action.sh reset-touch        clear sensitivity/edge/palm-reject values
action.sh reset              restore settings.conf to shipped defaults
action.sh revert             temporarily undo tweaks (settings kept)
action.sh help                usage
```

## Device support

Hardware-specific tweaks (report rate, CPU/GPU governors, thermal, battery spoof) only run on devices with a **confirmed profile** — right now, just `duchamp`. On anything else the module still works, just in a reduced **experimental** mode:

| Profile | What runs |
|---|---|
| `confirmed` (duchamp) | Everything |
| `experimental` (anything else) | Smooth Touch, Priority Apps, PowerKeeper — hardware sysfs paths skipped |

Set `FORCE_EXPERIMENTAL=1` in `settings.conf` to try duchamp's hardware paths on another device anyway. They're guarded by a `-w` check either way, so a wrong guess just no-ops rather than doing something unexpected — but it's still a guess, not a confirmation.

## TG Lag Fix

<a id="tg-lag-fix"></a>
Sluggish scrolling in Telegram (and some other apps) after HyperOS updates is a real, community-reported issue — but the root cause hasn't been pinned down by Xiaomi or the community. `TG_LAG_FIX` exempts Telegram from Doze/App Standby/PowerKeeper background limits, which is the only safe userspace lever available without an Xposed-level hook into the renderer. It's a background-execution fix, not a rendering fix — worth testing, not guaranteed. Use the general **Priority Apps** list for the same treatment on any other app.

## Contributing

**Unlocking touch tuning:** run `tools/probe_touch.sh` as root (read-only, never writes) and open an issue with the output. Once real node names are confirmed, they go straight into `settings.conf`.

**Adding a new device:** run `tools/probe_device.sh` as root and open an issue with the output. Confirmed devices get a case-statement entry in `apply.sh` with their own paths — not guesses.

```
adb shell su -c "sh /sdcard/probe_touch.sh"  > probe_touch.txt
adb shell su -c "sh /sdcard/probe_device.sh" > probe_device.txt
```

## Upcoming Device Support
Based on our latest testing, support for additional devices featuring MediaTek and Qualcomm Snapdragon SoCs is coming soon.
Compatibility is currently being tested and optimized to ensure a stable experience across a wider range of devices.

## Credits

Built by Sep.
