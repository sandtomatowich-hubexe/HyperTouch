<p align="center">
  <strong>A safe and lightweight touch optimization framework for Poco X6 Pro 5G / Redmi K70E (duchamp).</strong>
</p>

<p align="center">
  <a href="https://github.com/sandtomatowich-hubexe/HyperTouch/releases/latest">Latest Release</a> •
  <a href="https://github.com/sandtomatowich-hubexe/HyperTouch">Source Code</a>
</p>

## HyperTouch

Touch + light performance tuning for **Poco X6 Pro 5G / Redmi K70E (duchamp)**.
Works with Magisk, KernelSU, KernelSU-Next, and SukiSU Ultra.

## What changed from Previous version?

1. **Structural bug:** `post-fs-data.sh`, `service.sh`, and `system.prop` were
   inside a `common/` subfolder. Magisk/KernelSU only auto-run those files
   when they sit at the module's root — nested in `common/`, they never
   executed. Everything is now at the top level.
2. **`update-binary` had an injected line** that silently opened
   `https://t.me/modulostk` on every install via `am start`, in the
   background, with no consent prompt. Removed — a module you ship under
   your own name shouldn't force-open a link on someone's phone.
3. **`action.sh` was referenced by `customize.sh` but didn't exist.** Added,
   and it now re-runs the tweaks on demand from the manager's Action button.
4. **`service.sh` had `SKIPUNZIP=0` before its own shebang** — that flag
   belongs in `customize.sh`, not here, and doing it this way had no effect.
   Removed.
5. **Battery temp spoof (`bms/temp` → 250) is now off by default**, gated
   behind `SPOOF_BATTERY_TEMP=1` in `settings.conf`. It hides real
   overheating from the system, so it's opt-in rather than forced.
6. All sysfs writes now go through a `write()` helper that checks `-w`
   first, so an unavailable node just gets skipped and logged instead of
   spamming logcat errors.
7. `module.prop` had placeholder joke branding and someone else's author
   tag. Replaced with real metadata.
8. Logic that used to only run at boot now lives in `apply.sh`, called by
   `service.sh` (boot), `action.sh` (manager button), and the WebUI
   ("Apply now") — so toggling a setting doesn't require a reboot.

## Feature status

| Feature | Status |
|---|---|
| Boosted touch report rate | Working — toggles `switch_report_rate` |
| Disable PowerKeeper throttling | Working |
| Battery temp override | Working, opt-in, off by default |
| Sensitivity / edge (glove) / palm rejection | **Not wired up yet** |

The sensitivity/edge/palm-reject sysfs nodes weren't in the original module
and I couldn't confirm the real attribute names for this kernel build from
public sources — guessing at magic values here isn't worth shipping.

**To unlock them:** run `tools/probe_touch.sh` as root (it only reads, never
writes) and share the output. Once the real node names are confirmed, they
drop straight into `settings.conf` (`TOUCH_SENSITIVITY_PATH`,
`TOUCH_EDGE_PATH`, `PALM_REJECT_PATH` + matching `_VALUE` fields) and
`apply.sh` picks them up automatically — no script changes needed.

```
adb shell su -c "sh /sdcard/probe_touch.sh" > probe_output.txt
```

## WebUI

Open the module in a WebUI-capable manager (KernelSU / KernelSU-Next /
SukiSU Ultra manager, or a standalone viewer like KsuWebUIStandalone/MMRL)
to get the control panel. Stock Magisk's own manager doesn't render
WebUIs, so on plain Magisk you'd edit `settings.conf` directly and use the
Action button (if supported) or reboot.

## Known device-specific bits worth double-checking

- `persist.vendor.qti.inputopts.enable` in `system.prop` is a Qualcomm
  property — duchamp is MediaTek (Dimensity 8300-Ultra), so it's a harmless
  no-op here. Left in in case you reuse this on a Qualcomm variant later,
  but worth removing if you want the prop list to only contain things that
  actually do something on this chip.
- CPU governor paths assume the stock 1+3+4 cluster layout
  (`policy0`/`policy4`/`policy7`). If your kernel renumbers policies this
  will silently no-op on the missing ones (thanks to the `write()` guard)
  rather than error.
