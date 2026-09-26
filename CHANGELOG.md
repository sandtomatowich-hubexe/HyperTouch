# Changelog

## v3.0.1 — hotfix

- Fixed real navigation lag in the WebUI: `backdrop-filter` on the app bar and nav bar was set to *transition*, which forces a full re-blur of everything underneath on every animation frame — very expensive, and was firing on every scroll frame and every tab switch at once. Blur intensity now switches in one step instead of animating; blur radius also reduced (was pushed higher than necessary in a previous round)
- Fixed "Boosted" text rendering dark/illegible in dark mode: `<button class="hero">` was picking up the browser's default UA button text color instead of the theme's text color — inherited CSS color doesn't override a browser default on the same element. All buttons now explicitly inherit color/background from their parent context
- Fixed ROM version showing only the short marketing name ("OS3.0") instead of the full build string ("OS3.0.304.0WNLCNXM") — now prefers `ro.mi.os.version.incremental`/`ro.build.version.incremental` when available, in both `apply.sh` and the WebUI
- Fixed broken refresh-rate detection producing nonsense output ("mode 3Hz") in `module.prop`'s live description — the `dumpsys SurfaceFlinger` regex this relied on doesn't match reliably across devices
- Removed refresh-rate from `module.prop`'s description entirely; replaced with the actual touch report rate read back directly from the touch driver node (e.g. "480HZ"), which reports a real, confirmed value on read rather than being inferred from our own config
- WebUI's Home page "Refresh Rate" stat replaced with "Touch Rate" for the same reason — reads the real node instead of the unreliable display-refresh-rate probe
- Updated the PowerKeeper Full Disable warning (WebUI, `apply.sh` log output, README) to explicitly mention that it also disables Game Turbo's boost/Wild Boost profiles — confirmed they're part of the same `com.miui.powerkeeper` package, not a separate app, so there's no way to keep one and not the other with a full package disable

## v3.0.0

Full WebUI rebuild — new visual design, new navigation model, several real bugs fixed along the way. Backend (`apply.sh`/`action.sh`/`settings.conf`) is unchanged in behavior except where noted; this is primarily a WebUI release.

**Redesign**
- Entirely new card-dashboard visual style: rounded cards, indigo/blue gradient accent, floating glass nav — replaces the old flat-list layout
- Navigation restructured to 4 tabs (Home, Tweaks, Settings, About) plus a Priority Apps page reached via a Home quick-action tap; previously a flat Home/Tweaks/Apps/Settings tab set
- Home page now shows live stats (report-rate status, PowerKeeper mode, refresh rate, device, kernel) and one-tap Quick Actions instead of a plain settings list
- About page reorganized into icon-led grouped cards (Module / Device / Links) instead of plain key-value rows
- Device name now shown as a friendly marketing name ("Poco X6 Pro", "Poco X7 Pro") instead of the raw `ro.product.model` code; raw code still shown on the About page for support/debugging

**Motion & navigation**
- Added real swipe-gesture navigation between tabs (drag left/right on Home/Tweaks/Settings/About), not just tap
- Added 4 page-transition styles under Settings → Page Transition: miuix (spring/scale), AOSP (shared-axis slide), Scale, and None
- Added Exit Direction control (follow gesture / always right / always left) governing which way miuix/AOSP transitions slide
- Fixed real lag in the previous WebUI: every card on a page independently ran its own entrance animation on every tab switch, all firing at once — now the page transitions as one unit, with a lightweight CSS-only staggered card entrance that can't get stuck (a prior `IntersectionObserver`-based version of this was removed after it caused visible text/card overlap — observing an element the same tick it goes from hidden to visible gave the browser a stale bounding box, leaving some cards permanently offset)
- Fixed the WebUI's document not actually being scrollable in some cases — `html, body` were set to a hard `height:100%` (clips content) instead of `min-height:100%`, which also silently broke the scroll-reactive nav bar blur below

**Glass / visual polish**
- Top app bar and bottom nav bar now use real `backdrop-filter` blur (live glass), not a flat translucent fill
- Top app bar blur now intensifies with a hairline shadow once the page has actually scrolled, instead of a constant flat blur regardless of scroll position
- Bottom nav bar blur intensity increased substantially for a stronger live-glass effect

**New: Activity log**
- Added a terminal-icon button (top-left of the app bar) opening a slide-over Activity Log panel
- Logs every setting toggle, Apply/Reset/Revert action, and load error with a timestamp and status color
- Persists to `webui/activity.log` on the module itself, so history survives closing and reopening the WebUI — useful for debugging what actually changed before something broke

**Removed**
- Smooth Touch section removed from Tweaks entirely — redundant with Developer Options' own animation-scale controls. `SMOOTH_TOUCH_MODE` remains in `settings.conf`/`apply.sh` for backward compatibility; nothing in the WebUI writes to it anymore
- Tweaks tab icon changed from a terminal/prompt glyph to a tuning-sliders icon — the old one visually collided with the new Activity Log button, which uses the terminal glyph now

**New: VM/ZRAM tuning surfaced in the WebUI**
- Tweaks → Memory/ZRAM section for `VM_TWEAKS_ENABLED` and `SWAPPINESS` (both added to the backend in v2.4, previously had no WebUI control)

**Touch report-rate node auto-detection**
- `apply.sh` now checks for `goodix_ts_report_rate` first, falling back to `switch_report_rate`, instead of hardcoding one path — some AOSP-based Goodix driver builds reportedly expose the former; HyperOS/duchamp confirmed only has the latter
- `customize.sh` probes and reports which node it found directly in the flash log, so you know at install time rather than only after the first apply

**Installer (`customize.sh`)**
- Now detects the root manager (KernelSU/APatch/Magisk) and notes that the WebUI specifically needs a KSU-bridge WebView, which plain Magisk doesn't have
- Added an architecture check (informational — nothing in this module is actually arch-specific, but flags unexpected ABIs)
- `webui/ui.conf` (WebUI appearance preferences) now carried forward on updates, same as `settings.conf` already was
- Explicit permissions set on `webui/` so it has the module's own ownership/context from install rather than whatever context first-run `app.js` would leave it with

## v2.4

- Fixed `write()` silently reporting success when a node passed the writability check but the actual write failed (permission denied mid-write, read-only remount, write-once node) — now reports the real outcome
- Fixed PowerKeeper revert/uninstall: re-enabling only the `.statemachine.PowerStateMachineService` component didn't bring the package back after `POWERKEEPER_FULL_DISABLE` had disabled it entirely — both revert and uninstall now re-enable the package itself first
- Revert now restores actual pre-tweak values (CPU governor, GPU governor/floor, CPU rate limits, thermal `sconfig`, `deviceLevelList`, `miui_home_animation_rate`, and the battery temp spoof node) instead of only covering PowerKeeper/animation-scale/touch-rate — each node's original value is captured once, the first time apply.sh touches it, and restored from that on revert
- Fixed GPU frequency parsing only splitting on spaces — `available_frequencies` delimited by tabs/newlines on some kernels broke floor detection
- Fixed refresh-rate detection reading the display's max advertised mode instead of the currently active one (was `dumpsys display`'s per-mode fps list, sorted for the highest value — now reads SurfaceFlinger's active-mode line directly)
- Fixed a race between config writes (WebUI toggles, `action.sh enable/disable/reset`) and `apply.sh` reading `settings.conf` — both now share one lock (`lock.sh`), where before only `apply.sh`'s own run was guarded and a config write could land mid-read
- Lock now checks whether the process holding it is still alive (via its PID) and reclaims immediately if not, rather than always waiting out the full stale-lock timeout
- Fixed Telegram being added twice to the effective priority-apps list if it was already present in `PRIORITY_APPS` and `TG_LAG_FIX` was also on
- `service.sh`'s boot-completed wait now times out (10 min) instead of waiting forever if `sys.boot_completed` never reaches `1`
- VM/ZRAM tweaks (swappiness, read-ahead, page-cluster, scheduler autogroup) are now off by default and gated behind `VM_TWEAKS_ENABLED` — previously ran unconditionally on every device regardless of profile; `swappiness` is now configurable via `SWAPPINESS` (was hardcoded to 100)
- `read_ahead_kb` tuning (when enabled) is now scoped to `zram`/`mmcblk`/`sd*` queues instead of every writable block-device queue on the system
- `settings.conf` schema bumped to version 4 for the two new VM/ZRAM keys

## v2.3

- Removed MIUI Optimization entirely — tested, didn't help TG lag, and users reported it made the UI worse to live with
- Added PowerKeeper full-disable — community-verified fix for HyperOS capping some apps to 60Hz on 120Hz phones; `TG_LAG_FIX` now bundles this instead of the removed MIUI Optimization
- Fixed Parallel Animation — v2.2's property-name guess was wrong; real mechanism is `settings put system deviceLevelList "v:1,c:3,g:3"`
- Added Launcher Animation — same `deviceLevelList`-style mechanism, scoped to `com.miui.home` via `miui_home_animation_rate`, no launcher decompiling/patching involved
- Fixed module.prop's refresh-rate readout showing 60Hz on a 120Hz phone (was reading the first `dumpsys display` match, not the active one)
- module.prop now shows real RAM usage
- Fixed a screen-recorder black-screen issue — `debug.sf.enable_hwc_vds` was forcing virtual displays (what screen recorders create) through a hardware-composer path that doesn't fully support them on this device; removed, along with a dead Qualcomm-only prop that never applied to duchamp/rodin's MediaTek chip anyway
- Redesigned every WebUI icon — accurate shapes (proper CPU chip, gauge, parallel-lines, activity+floor for GPU), color-coded per category, no more duplicate icons across unrelated features
- Nav bar: more compact, fixed empty-corner spacing, brought back the v1 sweep-dot indicator as a live reactive dashboard

## v2.2

- Removed the placeholder touch-tuning nodes (sensitivity/edge/palm-reject) — never got confirmed real paths, so they were dead weight
- Added real Duchamp Tuning: Fast CPU Response (schedutil rate limits) and GPU Floor (reads actual OPP steps at runtime, not a hardcoded guess)
- Experimental support for `rodin` (POCO X7 Pro / Redmi Turbo 4) — reuses duchamp's CPU policy layout since both chips share the same 1+3+4 cluster topology; touch/GPU paths unverified
- Rebuilt TG Lag Fix: the background-exemption-only version was tested and made no real difference, so it now also disables MIUI Optimization (a foreground-focused lever), available standalone too
- Added experimental Parallel Animation toggle
- module.prop's description now updates live on every apply — touch mode, refresh rate, kernel version, device profile
- New wallpaper style: Pulse
- Page-transition animation and tactile tap feedback on cards
- Fixed: settings could appear to silently revert after tapping Action — `settings.conf`/`ui.conf` writes are now atomic (temp file + rename), and `apply.sh` now locks against concurrent runs

## v2.1

**WebUI rebuild.**

- Complete redesign: Home / Tweaks / Apps / Settings pages, floating icon-only nav
- Appearance: Dark / Light / System mode (System follows the device live, no reload)
- Monet dynamic accent — pulls today's Material You color from your wallpaper where the ROM exposes it, falls back cleanly where it doesn't
- Wallpaper patterns behind the glass surfaces (None / Signal / Aurora / Grid)
- Motion control (Full / Reduced / Off) for the WebUI's own interface animations — separate from the Smooth Touch device tweak
- True squircle corners and a real liquid-glass floating nav bar
- Split into `index.html` / `theme.css` / `style.css` / `app.js` for maintainability

**Fixes:**
- Segmented control buttons (Stock/Fast/Instant etc.) had uneven spacing on some devices
- Visual artifact on the active nav item's rounded corner
- The manager's Action button appeared to do nothing — `apply.sh` only logged to logcat and never printed to the console it actually reads from

## v2.0

**Major update.**

- Smooth Touch: userspace animation-scale control (Stock/Fast/Instant), kernel-independent — works on any device
- Priority Apps: exempt any package from Doze / App Standby / PowerKeeper background limits
- TG Lag Fix: experimental one-tap preset of Priority Apps for reported Telegram scroll stutter
- Device profile framework — hardware-specific tweaks only run on confirmed devices; unconfirmed devices get kernel-independent features only, not guessed sysfs paths
- Settings now survive module updates (previously reset to shipped defaults on every reinstall)
- Full management CLI (`action.sh status|enable|disable|reset|revert`)
- Battery temp override changed from forced-on to opt-in

## v1.0

**Initial rebuild.**

- Fixed structural bug: core scripts sat in a `common/` subfolder and never actually ran
- Removed an undisclosed Telegram redirect that fired on every install
- Corrected branding and module metadata
- Boosted touch report rate toggle
- PowerKeeper bypass
- First WebUI control panel
