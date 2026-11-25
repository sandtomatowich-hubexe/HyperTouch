<div align="center">
  <h1>HyperTouch</h1>
  <img src="https://raw.githubusercontent.com/sandtomatowich-hubexe/HyperTouch/main/assets/hypertouch-logo.png" alt="HyperTouch" width="300">
</div>

<p align="center">

[![Release](https://img.shields.io/github/v/release/sandtomatowich-hubexe/HyperTouch?include_prereleases&label=release&logo=github)](https://github.com/sandtomatowich-hubexe/HyperTouch/releases)
![License](https://img.shields.io/github/license/sandtomatowich-hubexe/HyperTouch?label=license)
[![Downloads](https://img.shields.io/github/downloads/sandtomatowich-hubexe/HyperTouch/total?label=downloads&logo=github)](https://github.com/sandtomatowich-hubexe/HyperTouch/releases)

![Android](https://img.shields.io/badge/Android-14%2B-3DDC84?logo=android&logoColor=white)
![Root](https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20APatch-blue)
![Device](https://img.shields.io/badge/Device-duchamp%20%7C%20rodin-orange)

</p>

# What is HyperTouch?


<p align="center">
  <img
    src="https://raw.githubusercontent.com/sandtomatowich-hubexe/sandtomatowich-hubexe/main/hypertouch-card.svg"
    alt="HyperTouch"
    width="100%"
  />
</p>


`HyperTouch` is a Touch response and system responsiveness tuning module made for **Poco X6 Pro / Redmi K70E (duchamp)**, with experimental support for **Poco X7 Pro (rodin)** (touch boost unverified) — built without requiring kernel modifications. Everything runs as a Magisk/KernelSU module against existing driver and userspace interfaces.

Works with **Magisk**, **KernelSU**, **KernelSU-Next**, **SukiSU Ultra**, and **APatch**. The WebUI specifically needs a manager with a KSU-bridge WebView (KernelSU Next, MMRL, APatch's own, or a standalone viewer like KsuWebUIStandalone) — plain Magisk has no in-app WebView, so `action.sh` from a root shell is the way to control the module there instead.

## Features

| Feature | Layer | Status | Notes |
|---|---|---|---|
| Boosted touch report rate | Kernel (sysfs) | ✅ Working on duchamp · 🧪 unverified on rodin | Node auto-detected (`goodix_ts_report_rate` or `switch_report_rate`) — see [Device support](#device-support) |
| Disable PowerKeeper throttling | System | ✅ Working | No-ops safely on non-HyperOS ROMs |
| PowerKeeper full disable | System | ✅ Working | Community-verified fix for apps HyperOS caps to 60Hz — also disables Game Turbo boost profiles, same package. See [TG Lag Fix](#tg-lag-fix) |
| Battery temp override | Kernel (sysfs) | ✅ Working, opt-in | Off by default — hides real overheating from the system |
| Fast CPU response | Kernel (sysfs) | ✅ Working | Lowers the schedutil rate limit (uses `up/down_rate_limit_us` if the kernel has them, otherwise the single `rate_limit_us`); warns if the kernel exposes neither. Only on devices with a hardware profile |
| GPU floor | Kernel (sysfs) | ✅ Working on duchamp, opt-in · untested on rodin | Reads real OPP steps at runtime rather than guessing a frequency |
| Priority Apps (background exemption) | Userspace | ✅ Working | Kernel-independent, works on any device/ROM |
| Parallel Animation | System | ✅ Working | Real `deviceLevelList` mechanism — see [below](#parallel-animation) |
| Launcher Animation | System | ✅ Working | Same idea, scoped to `com.miui.home` — no launcher modification |
| Force 120Hz Everywhere | System | ✅ Working, opt-in | Pins min/peak refresh rate — real, deliberate battery cost |
| VM/ZRAM tuning | Kernel (early boot) | ✅ Working, opt-in | Off by default — swappiness, read-ahead, scheduler autogroup |
| TG Lag Fix | Userspace + System | 🧪 Experimental, rebuilt | Layers Priority Apps + PowerKeeper full-disable — see [below](#tg-lag-fix) |
| WebUI | — | ✅ Working | Card-dashboard design, swipe navigation, activity log — see [below](#webui) |
| Keep tweaks applied | Userspace | ✅ Working, on by default | Xiaomi's services rewrite some values while the phone runs (after screen off/on, games, charging). A small background check every 30s re-applies **only** the touch report rate and the CPU rate limit if they were changed. It does not touch the thermal profile, governors or any Settings key. See [Keep Tweaks Applied](#keep-tweaks-applied) |
| Restore to originals | All | ✅ Working | Every value is saved before it's changed and put back on revert, uninstall, or when you switch the feature off — see [How restore works](#how-restore-works) |

Smooth Touch (animation-scale tuning) was removed as of v3.0.0 (fully, including its leftover config/script code, in v3.1.5) — it's redundant with the equivalent controls already in Developer Options.

## Installation

1. Flash `HyperTouch.zip` in your manager. The install log reports your device profile, root manager, and which touch report-rate node was found on your build.
2. Reboot once after the first flash. After that, every setting applies live through the Action button or WebUI — no more reboots needed (one exception: see [below](#settingsconf-reference)).
3. Updating later preserves both your `settings.conf` and your WebUI appearance preferences automatically — neither resets to defaults.

## WebUI

Four tabs in the bottom nav, plus a Priority Apps page reached by tapping the Priority Apps quick-action on Home:

| Page | Contains |
|---|---|
| **Home** | Live status (report rate, PowerKeeper, refresh rate, device, kernel) and one-tap Quick Actions |
| **Tweaks** | Every device-level setting, grouped by what it touches (Sampling, System, CPU & GPU Tuning, Parallel Animation, Memory/ZRAM) |
| **Priority Apps** | TG Lag Fix + custom Priority Apps list — reached from Home, not a separate tab |
| **Settings** | Appearance, motion, page transitions, module reset/revert |
| **About** | Module and device info, links |

**Appearance** (Settings → Appearance) — Mode (Light/Dark/System, System follows the device live), Accent Color (Signature or Monet, pulled from your wallpaper via `cmd overlay lookup` where the ROM exposes it), and Wallpaper (a few built-in generated patterns behind the glass surfaces).

**Motion** (Settings → Motion) — Full/Reduced/Off, controls the WebUI's own interface animation speed, separate from any device-level tweak.

**Page Transition** (Settings → Page Transition) — how pages animate in when you switch tabs or swipe: **miuix** (spring/scale entrance), **AOSP** (shared-axis slide), **Scale**, or **None**. Pairs with **Exit Direction** (follow gesture / always right / always left), which governs which way miuix/AOSP slide when you tap a tab rather than swipe.

**Activity Log** — tap the terminal icon top-left of the app bar to open a slide-over log of every toggle, Apply/Reset/Revert, and load error this session, each timestamped. It persists to `webui/activity.log` on the module itself, so it's still there if you close and reopen the WebUI — useful for figuring out what changed right before something broke.

The nav bar and app bar use real `backdrop-filter` blur — the app bar's blur intensifies once you've actually scrolled, rather than staying flat regardless of position.

## settings.conf reference

Edit by hand or through the WebUI — both write the same file, so nothing gets out of sync.

`settings.conf` is **parsed, never executed**: only the keys below are read, each value is validated (`0`/`1` flags, a numeric swappiness, and package names that must be dot-separated `[A-Za-z0-9_]` segments), and anything invalid is ignored with a log line. Unknown or removed keys such as `SMOOTH_TOUCH_MODE` are ignored. This matters because the scripts run as root.

| Key | Values | Default | Reboot needed? |
|---|---|---|---|
| `REPORT_RATE_MODE` | `0` stock / `1` boosted | `1` | No |
| `DISABLE_POWERKEEPER` | `0` / `1` | `1` | No |
| `POWERKEEPER_FULL_DISABLE` | `0` / `1` | `0` | No |
| `SPOOF_BATTERY_TEMP` | `0` / `1` | `0` | No |
| `FAST_CPU_RESPONSE` | `0` / `1` | `1` | No |
| `KEEP_APPLIED` | `0` / `1` | `1` | No |
| `GPU_FLOOR` | `0` / `1` | `0` | No |
| `PARALLEL_ANIM` | `0` / `1` | `0` | Applied live; reboot guarantees it |
| `LAUNCHER_ANIM_RATE` | `0` / `1` | `0` | No — launcher auto-restarts |
| `FORCE_120HZ` | `0` / `1` | `0` | No |
| `PRIORITY_APPS` | space-separated package names | blank | No |
| `TG_LAG_FIX` | `0` / `1` | `0` | No |
| `VM_TWEAKS_ENABLED` | `0` / `1` | `0` | No (early-boot, next apply/boot) |
| `SWAPPINESS` | `0`–`100` in the WebUI (up to `200` accepted by hand) | `60` | No (early-boot, next apply/boot) |
| `FORCE_EXPERIMENTAL` | `0` / `1` | unset | No (no WebUI toggle; the WebUI keeps it when it saves) |

Smooth Touch (`SMOOTH_TOUCH_MODE`) is fully removed as of v3.1.5 — the setting is ignored if still present in an old `settings.conf`, and nothing in HyperTouch touches the system animation scales any more.

Everything applies live through `apply.sh`/the WebUI — no reboot needed after the first flash, with two exceptions:

- `PARALLEL_ANIM` (`deviceLevelList`) — HyperOS's animation-tier logic sits close to `system_server`, with no single safe userspace process this module can restart to force an immediate re-read the way it can for the launcher. It's applied immediately and HyperOS picks it up within its own refresh window in practice, but a reboot is still the only *guaranteed* immediate way to see it.
- Nothing else requires a reboot as of this version — `LAUNCHER_ANIM_RATE` now force-restarts the launcher itself (instant, safe — Android relaunches it automatically since it's the home app), and `VM_TWEAKS_ENABLED`/`SWAPPINESS` now apply live to the same `/proc`/sysfs nodes in addition to running at next boot via `post-fs-data.sh`, so toggling them takes effect immediately rather than only after a restart.

## Management CLI

`action.sh` is what runs when you tap **Action** in your manager, and also works from a terminal:

```
action.sh                    re-apply current settings
action.sh status              show current settings + device profile
action.sh enable <feature>    boost | powerkeeper | powerkeeper-full |
                              battery-spoof | fast-cpu | gpu-floor |
                              parallel-anim | launcher-anim | force-120hz |
                              keep-applied | tg-fix
action.sh disable <feature>   (same feature names)
action.sh reset               restore settings.conf to shipped defaults
action.sh revert              temporarily undo tweaks (settings kept)
action.sh help                 usage
```

## Keep Tweaks Applied

HyperTouch applies its tweaks at boot and whenever you press Apply/Action. Xiaomi's own services (the touch HAL, thermal engine, power HAL) can rewrite some of the same values afterwards, which used to make tweaks quietly fall back to stock after a while.

With `KEEP_APPLIED=1` (default), `watch.sh` runs in the background and every 30 seconds compares the touch report rate and the CPU rate limit with the configured values using shell builtins only (no process is spawned while nothing has changed). Only if one has drifted does it re-write those two values. It does **not** re-assert the thermal profile, governors, GPU floor or any Settings-provider value, so it doesn't fight Xiaomi's thermal engine or Game Turbo.

- `action.sh revert` stops it, so a revert stays reverted; Apply, Action, or a reboot starts it again.
- It stops on its own if the module is disabled or removed, or if `KEEP_APPLIED=0`.
- Turn it off in Tweaks → Keep Tweaks Applied, or with `action.sh disable keep-applied`.

## How restore works

Before HyperTouch changes anything it saves the original value, once, in `.state/` inside the module folder. `action.sh revert`, uninstall, and switching a feature off all put back **that saved value** — never a hardcoded guess at stock.

| What | Saved | Restored |
|---|---|---|
| Kernel nodes (sysfs/proc) | the node's value, plus its real path in a `.node` file | written back to that exact path |
| Settings keys (`deviceLevelList`, launcher rate, min/peak refresh rate) | the value, or a marker if it was **unset** | written back, or deleted if it was unset |
| PowerKeeper | whether the package and the state-machine component were already disabled | re-enabled only if they were enabled before; left disabled if you had disabled them |
| Priority Apps | Doze-whitelist membership and the standby bucket | removed from the whitelist (unless it was already there), both AppOps set back to default, bucket put back |
| Touch report rate | its formatted readback (`touch report rate::480HZ`) | mapped back to the write value that reproduces it (480HZ → 1, 240HZ → 0) |

`.state` is carried across module updates, so an update never mistakes already-tweaked values for the originals. On uninstall, root managers usually run `uninstall.sh` early at the next boot, before the package manager and settings exist, so the restore waits for boot to finish and then runs in the background.

HyperTouch no longer touches the system animation scales or `persist.sys.miui_optimization`, and neither revert nor uninstall changes them.

Two limits: state captured by v3.1.0 has no `.node` files and gets them on the first apply after updating; and if another module or app had already changed a value before HyperTouch first ran, that changed value is what gets recorded as the original.

## Device support

Hardware-specific tweaks only run on devices with a real profile behind them — never a blind guess at an unrelated device's register layout:

| Profile | Devices | What runs |
|---|---|---|
| `confirmed` | `duchamp` (Poco X6 Pro) | Everything, verified against real hardware |
| `experimental-named` | `rodin` (Poco X7 Pro) | Everything runs, but touch boost is **unverified**: the Goodix node accepts 0/1 and reads back 240/480Hz, yet a tester saw no real 480Hz effect, and the Rodin Essential project documents that its 240/480Hz control goes through Xiaomi's touch HAL rather than this node. CPU/GPU governors are left as the vendor set them (Rodin's Mali governor is `dummy`; some kernels use `sugov_ext`) |
| `experimental` | anything else | Kernel-independent features only (Priority Apps, PowerKeeper) — hardware sysfs paths skipped |

Set `FORCE_EXPERIMENTAL=1` in `settings.conf` to try the hardware paths on any device anyway. They're guarded by a `-w` check either way, so a wrong guess just no-ops rather than doing something unexpected — but it's still a guess, not a confirmation.

This applies independently of ROM: hardware tweaks are gated on the device code (`duchamp`/`rodin`), not on running HyperOS specifically. Only the HyperOS/MIUI-only pieces (PowerKeeper, `deviceLevelList`-based animation tuning) are ROM-gated, and those already no-op safely on AOSP-based ROMs.

**Touch report-rate node**: two different Goodix driver builds expose this under different sysfs node names — `switch_report_rate` (confirmed on HyperOS/duchamp) or `goodix_ts_report_rate` (reported on some AOSP-based builds, unconfirmed on any specific ROM at time of writing). `apply.sh` checks for both at apply-time and uses whichever actually exists, rather than hardcoding one and silently failing on the other. A node accepting the write and reading back 480HZ only shows the value was accepted — on rodin the real touch rate did not change in a measuring app (see Device support), so treat the readback with care there. FocalTech-panel units have neither node and skip the touch boost.

## TG Lag Fix

Sluggish scrolling in Telegram (and some other apps) after HyperOS updates is a real, community-reported issue — but the root cause hasn't been pinned down by Xiaomi or the community, and this has already gone through one wrong guess:

1. **v2.2**: exempted Telegram from Doze/App Standby/PowerKeeper background limits, then also tried disabling MIUI Optimization. Tested on real hardware — neither moved the needle. MIUI Optimization is now removed from HyperTouch entirely.
2. **v2.3**: `TG_LAG_FIX` now bundles the *verified* PowerKeeper full-disable instead (see [Features](#features)) — HyperOS caps some apps to 60Hz even on 120Hz phones via PowerKeeper specifically, which is a much more direct match for "scrolling doesn't feel as smooth as it should" than a background-execution toggle ever was. `PowerKeeper full disable` is also available standalone in Tweaks → System if you want it without the Telegram-specific framing.

**Trade-off to know about**: `com.miui.powerkeeper` is also the package behind Game Turbo's boost/Wild Boost profiles — they're not a separate app, they're a feature inside PowerKeeper. Fully disabling the package (whether via `TG_LAG_FIX` or the standalone toggle) disables Game Turbo's boost profiles along with it. There's no way to keep one and not the other with this approach, since it's one `pm disable-user` on one package.

One thing no root tweak can reach: Telegram's own animated chat background is a real, developer-acknowledged performance cost (confirmed on Telegram's own bug tracker), and the community workaround is a static wallpaper set *inside Telegram itself* (Settings → Chat Settings). That's in-app rendering, not something HyperTouch can touch from the outside — worth trying alongside the toggle above, not instead of it.

## Parallel Animation

<a id="parallel-animation"></a>
HyperOS gates certain animations (parallel-rendered transitions, some launcher effects) behind a device's assigned "animation tier," read from the `deviceLevelList` Settings key. duchamp is hardware-capable but classified below the tier that unlocks it by default (rodin units probed so far already report this value, so it is a no-op there). `PARALLEL_ANIM` sets it directly: `settings put system deviceLevelList "v:1,c:3,g:3"`. Applied immediately; a reboot is the only way to *guarantee* HyperOS has re-read it, since there's no single safe process this module can restart to force that the way it can for the launcher below.

`LAUNCHER_ANIM_RATE` is the same idea scoped specifically to the stock launcher (`com.miui.home`) via `miui_home_animation_rate` — a Settings key the launcher itself reads at runtime. Toggling it force-restarts `com.miui.home`, which Android relaunches automatically (it's the home app), so this one is a genuine instant hot-reload — no manual force-stop or reboot needed.

## Force 120Hz Everywhere

Pins `min_refresh_rate` and `peak_refresh_rate` to 120Hz, the same mechanism AOSP's own Developer Options uses for "Force peak refresh rate" — HyperOS doesn't expose an equivalent toggle on its own. This stops the display from adaptively dropping to a lower rate on static or low-motion content, at a real, deliberate battery cost — that's the entire point of the feature, not a side effect to be optimized away. `apply.sh` first checks the panel's supported modes (rounded, so a reported 119.99 counts as 120) and skips if it tops out below ~118Hz; if it can't read the modes at all it tries anyway. After writing, it **reads the values back** and reports a failure (and exits with code 2) if the system rejected or overrode them, instead of claiming success.

## Contributing

**Adding a new device:** run `tools/probe_device.sh` as root and open an issue with the output. It is read-only and collects the touch node, CPU clusters and schedutil settings, GPU devfreq, thermal/battery nodes, refresh modes and PowerKeeper, with no personal data. A hardware profile is only marked `confirmed` after the effect has been measured on a real device (readback alone is not enough). Confirmed devices get a case-statement entry in `apply.sh` with their own paths — not guesses.

```
adb shell su -c "sh /sdcard/probe_device.sh" > probe_device.txt
```

If your device's touch report-rate node turns out to be neither `switch_report_rate` nor `goodix_ts_report_rate`, that's also worth an issue — `apply.sh` currently only checks those two.

## Known limitations

- **Keep Tweaks Applied** can't help with values the system changes *during* a game faster than every 30 seconds, and it only covers the two values above.
- **Rodin touch boost is unverified** (see Device support). FocalTech-panel units are unsupported for touch.
- Priority Apps restores AppOps to *default*, not to any custom per-app mode you had set.
- If two HyperTouch operations overlap, the second waits for the first (up to 2 minutes) and then gives up with an error rather than running at the same time.

## Upcoming Device Support

Based on our latest testing, support for additional devices featuring MediaTek and Qualcomm Snapdragon SoCs is coming soon. Compatibility is currently being tested and optimized to ensure a stable experience across a wider range of devices.

## Credits

Built by Sep.
