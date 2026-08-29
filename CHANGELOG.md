# Changelog

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
