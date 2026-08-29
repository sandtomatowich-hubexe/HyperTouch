# HyperTouch

Touch response and system responsiveness tuning for supported Android devices, built without requiring kernel modifications — everything runs as a Magisk/KernelSU module against existing driver and userspace interfaces.

Works with **Magisk**, **KernelSU**, **KernelSU-Next**, and **SukiSU Ultra** and all included forks.
WebUI needs one of the KernelSU-family managers (or a standalone viewer like KsuWebUIStandalone/MMRL) — plain Magisk manager doesn't render WebUIs , unless you use **KSU WebUI**.

## Features

| Feature | Layer | Status | Notes |
|---|---|---|---|
| Boosted touch report rate | Kernel (sysfs) | ✅ Working | `duchamp` confirmed, `rodin` experimental — see [Device support](#device-support) |
| Disable PowerKeeper throttling | System | ✅ Working | No-ops safely on non-HyperOS ROMs |
| Battery temp override | Kernel (sysfs) | ✅ Working, opt-in | Off by default — hides real overheating from the system |
| Fast CPU response | Kernel (sysfs) | ✅ Working | schedutil rate-limit tuning, confirmed/named-experimental devices only |
| GPU floor | Kernel (sysfs) | ✅ Working, opt-in | Reads real OPP steps at runtime rather than guessing a frequency |
| Smooth Touch (animation scale) | Userspace | ✅ Working | Kernel-independent, works on any device/ROM |
| Priority Apps (background exemption) | Userspace | ✅ Working | Kernel-independent, works on any device/ROM |
| Disable MIUI Optimization | System | 🧪 Experimental | May need a reboot — see [TG Lag Fix](#tg-lag-fix) |
| TG Lag Fix | Userspace + System | 🧪 Experimental, rebuilt | Now layers Priority Apps + MIUI Optimization — see [below](#tg-lag-fix) |
| WebUI | — | ✅ Working | Multi-page: Home, Tweaks, Apps, Settings — dark/light/system, Monet accent, wallpapers |

## Installation

1. Flash `HyperTouch.zip` in your manager.
2. Reboot, **or** open the module's Action/WebUI afterward to apply without rebooting.
3. Updating later preserves your `settings.conf` automatically — it isn't reset to defaults.

## WebUI

Four pages, reachable from the floating nav:

| Page | Contains |
|---|---|
| **Home** | Quick toggles for the tweaks you'll touch most, plus Apply Now |
| **Tweaks** | Every device-level setting, grouped by category |
| **Apps** | TG Lag Fix + custom Priority Apps list |
| **Settings** | Appearance, module info, Reset/Revert, links |

**Appearance** (Settings → Appearance) has three independent controls — Mode (Dark/Light/System, System follows the device live), Accent (Default or Monet, pulled from your wallpaper via `cmd overlay lookup` where the ROM exposes it), and Wallpaper (a few built-in generated patterns behind the glass surfaces). **Motion** (Settings → Motion) controls the WebUI's own interface animations, separate from the Smooth Touch device tweak.

## settings.conf reference

Edit by hand or through the WebUI — both write the same file, so nothing gets out of sync.

| Key | Values | Default | Reboot needed? |
|---|---|---|---|
| `REPORT_RATE_MODE` | `0` stock / `1` boosted | `1` | No |
| `DISABLE_POWERKEEPER` | `0` / `1` | `1` | No |
| `SPOOF_BATTERY_TEMP` | `0` / `1` | `0` | No |
| `FAST_CPU_RESPONSE` | `0` / `1` | `1` | No |
| `GPU_FLOOR` | `0` / `1` | `0` | No |
| `SMOOTH_TOUCH_MODE` | `0` stock / `1` fast / `2` instant | `1` | No |
| `DISABLE_MIUI_OPT` | `0` / `1` | `0` | Recommended |
| `PRIORITY_APPS` | space-separated package names | blank | No |
| `TG_LAG_FIX` | `0` / `1` | `0` | Recommended |
| `FORCE_EXPERIMENTAL` | `0` / `1` | unset | No |

Everything applies live through `apply.sh` except the two rows marked above — `DISABLE_MIUI_OPT` (and `TG_LAG_FIX`, which sets it) ties into ART/app-compilation behavior that doesn't reliably take effect without a reboot.

## Management CLI

`action.sh` is what runs when you tap **Action** in your manager, and also works from a terminal:

```
action.sh                    re-apply current settings
action.sh status              show current settings + device profile
action.sh enable <feature>    boost | powerkeeper | battery-spoof |
                              fast-cpu | gpu-floor | miui-opt | tg-fix
action.sh disable <feature>   (same feature names)
action.sh reset               restore settings.conf to shipped defaults
action.sh revert              temporarily undo tweaks (settings kept)
action.sh help                 usage
```

## Device support

Hardware-specific tweaks only run on devices with a real profile behind them — never a blind guess at an unrelated device's register layout:

| Profile | Devices | What runs |
|---|---|---|
| `confirmed` | `duchamp` | Everything, verified against real hardware |
| `experimental-named` | `rodin` | Everything, but touch/GPU paths are unverified — reuses duchamp's CPU policy layout because both chips genuinely share the same 1+3+4 cluster topology (published spec, not a guess) |
| `experimental` | anything else | Kernel-independent features only (Smooth Touch, Priority Apps, PowerKeeper, MIUI Optimization) — hardware sysfs paths skipped |

Set `FORCE_EXPERIMENTAL=1` in `settings.conf` to try the hardware paths on any device anyway. They're guarded by a `-w` check either way, so a wrong guess just no-ops rather than doing something unexpected — but it's still a guess, not a confirmation.

## TG Lag Fix

Sluggish scrolling in Telegram (and some other apps) after HyperOS updates is a real, community-reported issue — but the root cause hasn't been pinned down by Xiaomi or the community. The first version of this fix only exempted Telegram from Doze/App Standby/PowerKeeper background limits — tested on real hardware, and it made no noticeable difference, because that only affects background execution, not how an already-foregrounded app renders and scrolls.

Rebuilt version: `TG_LAG_FIX` now also disables MIUI Optimization, a community-reported lever that's more plausibly related to foreground app behavior since it affects ART/app compilation rather than background scheduling. Still experimental, still not guaranteed — this is a second real attempt at a genuinely hard-to-diagnose problem, not a confirmed fix. `Disable MIUI Optimization` is also available standalone in Tweaks → System, in case it helps general smoothness beyond just Telegram.

## Contributing

**Adding a new device:** run `tools/probe_device.sh` as root and open an issue with the output. Confirmed devices get a case-statement entry in `apply.sh` with their own paths — not guesses.

```
adb shell su -c "sh /sdcard/probe_device.sh" > probe_device.txt
```

## Upcoming Device Support

Based on our latest testing, support for additional devices featuring MediaTek and Qualcomm Snapdragon SoCs is coming soon.
Compatibility is currently being tested and optimized to ensure a stable experience across a wider range of devices.

## Credits

Built by Sep.
