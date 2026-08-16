# Changelog

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
- 
