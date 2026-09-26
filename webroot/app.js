// HyperTouch — app.js
"use strict";
(function(){
  var MODDIR = "/data/adb/modules/hypertouch";
  var CONF = MODDIR + "/settings.conf";
  var UICONF = MODDIR + "/webui/ui.conf";
  var LOGFILE = MODDIR + "/webui/activity.log";
  var cbSeq = 0;

  // ============================================================
  // Activity log — every setting change, apply/revert/reset, and
  // load error gets a line here. Kept in-memory for the session and
  // persisted to a small rotating file so it's useful for debugging
  // ("what did the WebUI actually send to apply.sh") even after the
  // page is closed and reopened. Capped at LOG_MAX entries; oldest
  // drop off rather than growing the file forever.
  var LOG_MAX = 200;
  var logEntries = []; // {ts, level, msg}
  var logLoaded = false;

  function logLine(level, msg){
    var entry = {ts: Date.now(), level: level, msg: msg};
    logEntries.push(entry);
    if (logEntries.length > LOG_MAX) logEntries.shift();
    renderLog();
    persistLog();
    if (els.shellBtn) els.shellBtn.classList.add("has-activity");
  }
  function logOk(msg){ logLine("ok", msg); }
  function logErr(msg){ logLine("err", msg); }
  function logInfo(msg){ logLine("info", msg); }

  function fmtTime(ts){
    var d = new Date(ts);
    var h = d.getHours(), m = d.getMinutes(), s = d.getSeconds();
    function pad(n){ return (n < 10 ? "0" : "") + n; }
    return pad(h) + ":" + pad(m) + ":" + pad(s);
  }

  function renderLog(){
    if (!els.shellBody) return;
    if (logEntries.length === 0){
      els.shellBody.innerHTML = '<div class="shell-empty">No activity yet this session.</div>';
      return;
    }
    var html = "";
    for (var i = logEntries.length - 1; i >= 0; i--){
      var e = logEntries[i];
      html += '<div class="shell-entry lvl-' + e.level + '">' +
        '<span class="dotmark"></span>' +
        '<span class="t">' + fmtTime(e.ts) + '</span>' +
        '<span class="m">' + escapeHtml(e.msg) + '</span>' +
        '</div>';
    }
    els.shellBody.innerHTML = html;
  }
  function escapeHtml(s){
    return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
  }

  var persistTimer = null;
  function persistLog(){
    // Debounced: several toggles in quick succession shouldn't each
    // fire their own disk write.
    if (persistTimer) clearTimeout(persistTimer);
    persistTimer = setTimeout(function(){
      var lines = logEntries.map(function(e){
        return e.ts + "\t" + e.level + "\t" + e.msg.replace(/\n/g, " ");
      }).join("\n");
      var tmp = LOGFILE + ".tmp";
      var cmd = "mkdir -p " + MODDIR + "/webui 2>/dev/null; cat > '" + tmp + "' << 'HT_LOG_EOF'\n" + lines + "\nHT_LOG_EOF\nmv -f '" + tmp + "' '" + LOGFILE + "'";
      ksuExec(cmd);
    }, 500);
  }

  async function loadPersistedLog(){
    if (logLoaded) return;
    logLoaded = true;
    var r = await ksuExec("cat " + LOGFILE + " 2>/dev/null");
    if (r.errno === 0 && r.stdout){
      var parsed = r.stdout.split("\n").filter(Boolean).map(function(line){
        var parts = line.split("\t");
        return {ts: parseInt(parts[0], 10) || Date.now(), level: parts[1] || "info", msg: parts.slice(2).join("\t")};
      }).filter(function(e){ return !isNaN(e.ts); });
      logEntries = parsed.slice(-LOG_MAX);
      if (logEntries.length) { renderLog(); if (els.shellBtn) els.shellBtn.classList.add("has-activity"); }
    }
  }

  function openShell(){
    els.shellScrim.hidden = false;
    els.shellPanel.hidden = false;
    // next frame so the transform transition actually runs
    requestAnimationFrame(function(){
      els.shellScrim.classList.add("open");
      els.shellPanel.classList.add("open");
    });
    loadPersistedLog();
  }
  function closeShell(){
    els.shellScrim.classList.remove("open");
    els.shellPanel.classList.remove("open");
    setTimeout(function(){
      els.shellScrim.hidden = true;
      els.shellPanel.hidden = true;
    }, 240);
  }

  function ksuExec(cmd){
    return new Promise(function(resolve){
      if (!window.ksu || typeof window.ksu.exec !== "function"){
        resolve({errno:-1, stdout:"", stderr:"ksu bridge unavailable"});
        return;
      }
      var name = "__ht_cb_" + (cbSeq++);
      window[name] = function(code, stdout, stderr){
        delete window[name];
        resolve({errno:code, stdout:stdout || "", stderr:stderr || ""});
      };
      try { window.ksu.exec(cmd, name); }
      catch(e){ delete window[name]; resolve({errno:-1, stdout:"", stderr:String(e)}); }
    });
  }

  function parseConf(text){
    var out = {};
    text.split("\n").forEach(function(line){
      line = line.trim();
      if (!line || line[0] === "#") return;
      var i = line.indexOf("=");
      if (i < 0) return;
      out[line.slice(0,i).trim()] = line.slice(i+1).trim();
    });
    return out;
  }

  // ============================================================
  // Device-tweak state (settings.conf).
  // ============================================================
  var state = {
    REPORT_RATE_MODE:"1", DISABLE_POWERKEEPER:"1", SPOOF_BATTERY_TEMP:"0",
    FAST_CPU_RESPONSE:"1", GPU_FLOOR:"0", POWERKEEPER_FULL_DISABLE:"0",
    SMOOTH_TOUCH_MODE:"1", PARALLEL_ANIM:"0", LAUNCHER_ANIM_RATE:"0",
    PRIORITY_APPS:"", TG_LAG_FIX:"0",
    VM_TWEAKS_ENABLED:"0", SWAPPINESS:"60",
    CONF_VERSION:"4"
  };

  // ============================================================
  // WebUI-only preferences (webui/ui.conf) — separate file, never
  // touched by apply.sh/action.sh. Purely cosmetic, purely ours.
  // ============================================================
  var uiState = {
    MODE:"light",          // light | dark | system
    ACCENT_SOURCE:"fixed", // fixed | monet
    WALLPAPER:"none",      // none | signal | aurora | grid
    ANIM:"full",           // full | reduced | off
    TRANSITION:"miuix",    // miuix | aosp | scale | none
    EXIT_DIR:"gesture"     // gesture | right | left
  };

  var els = {}; // populated in init()

  // ---- mode resolution (system = live prefers-color-scheme) ----
  var darkMQ = window.matchMedia("(prefers-color-scheme: dark)");
  function resolvedMode(){
    if (uiState.MODE === "system") return darkMQ.matches ? "dark" : "light";
    return uiState.MODE;
  }
  function applyMode(){
    document.documentElement.dataset.mode = resolvedMode();
  }
  darkMQ.addEventListener("change", function(){
    if (uiState.MODE === "system") applyMode();
  });

  function applyWallpaper(){
    document.documentElement.dataset.wallpaper = uiState.WALLPAPER;
    var layer = document.getElementById("wallpaperLayer");
    if (layer) layer.className = "wallpaper wp-" + uiState.WALLPAPER;
  }

  function applyAnim(){
    document.documentElement.dataset.anim = uiState.ANIM;
  }

  function applyTransition(){
    document.documentElement.dataset.transition = uiState.TRANSITION;
  }

  // ---- Monet: best-effort, silent fallback ----
  // Reads the live Material You accent Android generates from the
  // wallpaper. Confirmed working on stock AOSP 12+ via `cmd overlay
  // lookup`; HyperOS has its own theming engine so this may or may not
  // return a color there — if it doesn't, this quietly no-ops and the
  // signature default gradient stays active instead of breaking anything.
  async function tryApplyMonet(){
    if (uiState.ACCENT_SOURCE !== "monet"){
      document.documentElement.style.removeProperty("--accent-1");
      document.documentElement.style.removeProperty("--accent-2");
      return;
    }
    var r1 = await ksuExec("cmd overlay lookup android android:color/system_accent1_500 2>/dev/null");
    var r2 = await ksuExec("cmd overlay lookup android android:color/system_accent1_300 2>/dev/null");
    function extract(r){
      if (r.errno === 0 && r.stdout){
        var m = r.stdout.match(/([0-9a-fA-F]{6,8})/);
        if (m) return "#" + m[1].slice(-6);
      }
      return null;
    }
    var hex1 = extract(r1);
    var hex2 = extract(r2) || hex1;
    if (hex1){
      document.documentElement.style.setProperty("--accent-1", hex1);
      document.documentElement.style.setProperty("--accent-2", hex2);
    } else {
      document.documentElement.style.removeProperty("--accent-1");
      document.documentElement.style.removeProperty("--accent-2");
    }
  }

  // ============================================================
  // ui.conf persistence
  // ============================================================
  function renderUiConf(){
    return [
      "# HyperTouch WebUI preferences — cosmetic only.",
      "# apply.sh/action.sh never read this file.",
      "MODE=" + uiState.MODE,
      "ACCENT_SOURCE=" + uiState.ACCENT_SOURCE,
      "WALLPAPER=" + uiState.WALLPAPER,
      "ANIM=" + uiState.ANIM,
      "TRANSITION=" + uiState.TRANSITION,
      "EXIT_DIR=" + uiState.EXIT_DIR
    ].join("\n");
  }

  async function loadUiConf(){
    var r = await ksuExec("mkdir -p " + MODDIR + "/webui 2>/dev/null; cat " + UICONF + " 2>/dev/null");
    if (r.errno === 0 && r.stdout){
      var parsed = parseConf(r.stdout);
      Object.keys(parsed).forEach(function(k){ if (k in uiState) uiState[k] = parsed[k]; });
    }
    applyMode();
    applyWallpaper();
    applyAnim();
    applyTransition();
    await tryApplyMonet();
    renderSettingsSegments();
  }

  async function saveUiConf(){
    var tmp = UICONF + ".tmp";
    var cmd = "mkdir -p " + MODDIR + "/webui 2>/dev/null; cat > '" + tmp + "' << 'HT_EOF'\n" + renderUiConf() + "\nHT_EOF\nmv -f '" + tmp + "' '" + UICONF + "'";
    return ksuExec(cmd);
  }

  async function updateUiPref(key, val){
    uiState[key] = val;
    applyMode(); applyWallpaper(); applyAnim(); applyTransition();
    if (key === "ACCENT_SOURCE") await tryApplyMonet();
    renderSettingsSegments();
    logInfo("Preference " + key + " → " + val);
    await saveUiConf();
  }

  // ============================================================
  // settings.conf persistence (device tweaks — unchanged behavior)
  // ============================================================
  function renderConf(){
    return [
      "# HyperTouch settings.",
      "# Edit from the WebUI (recommended), or by hand — most changes apply",
      "# immediately via \"Apply now\" / the Action button, no reboot needed.",
      "",
      "# ── Sampling ──────────────────────────────────────────────",
      "REPORT_RATE_MODE=" + state.REPORT_RATE_MODE,
      "",
      "# ── System ────────────────────────────────────────────────",
      "DISABLE_POWERKEEPER=" + state.DISABLE_POWERKEEPER,
      "POWERKEEPER_FULL_DISABLE=" + state.POWERKEEPER_FULL_DISABLE,
      "SPOOF_BATTERY_TEMP=" + state.SPOOF_BATTERY_TEMP,
      "",
      "# ── Duchamp Tuning (confirmed / named-experimental devices only) ──",
      "FAST_CPU_RESPONSE=" + state.FAST_CPU_RESPONSE,
      "GPU_FLOOR=" + state.GPU_FLOOR,
      "",
      "# ── Smooth Touch (userspace, kernel-independent) ────────────",
      "SMOOTH_TOUCH_MODE=" + state.SMOOTH_TOUCH_MODE,
      "",
      "# ── Parallel Animation (reboot recommended) ──────────────────",
      "PARALLEL_ANIM=" + state.PARALLEL_ANIM,
      "LAUNCHER_ANIM_RATE=" + state.LAUNCHER_ANIM_RATE,
      "",
      "# ── Priority Apps (userspace, kernel-independent) ───────────",
      "PRIORITY_APPS=" + state.PRIORITY_APPS,
      "TG_LAG_FIX=" + state.TG_LAG_FIX,
      "",
      "# ── VM / ZRAM (post-fs-data, early boot) ─────────────────────",
      "VM_TWEAKS_ENABLED=" + state.VM_TWEAKS_ENABLED,
      "SWAPPINESS=" + state.SWAPPINESS,
      "",
      "# ── Internal — do not edit ───────────────────────────────────",
      "CONF_VERSION=" + state.CONF_VERSION
    ].join("\n");
  }

  async function loadConf(){
    var r = await ksuExec("cat " + CONF);
    if (r.errno === 0 && r.stdout){
      var parsed = parseConf(r.stdout);
      Object.keys(parsed).forEach(function(k){ if (k in state) state[k] = parsed[k]; });
      render();
      setStatus("Settings loaded.");
      logOk("settings.conf loaded (" + Object.keys(parsed).length + " keys)");
    } else {
      render();
      setStatus(window.ksu ? "Could not read settings.conf — using defaults." : "Open this from your root manager to enable controls.", true);
      logErr("Could not read settings.conf (errno " + r.errno + ")" + (r.stderr ? ": " + r.stderr : ""));
    }
  }

  async function saveConf(){
    var tmp = CONF + ".tmp";
    var cmd = "cat > '" + tmp + "' << 'HT_EOF'\n" + renderConf() + "\nHT_EOF\nmv -f '" + tmp + "' '" + CONF + "'";
    return ksuExec(cmd);
  }

  // ============================================================
  // status / toast / live pill
  // ============================================================
  function setStatus(msg, isErr){
    ["status","statusTweaks","statusApps","statusSettings"].forEach(function(id){
      var el = document.getElementById(id);
      if (!el) return;
      el.textContent = msg;
      el.classList.toggle("err", !!isErr);
    });
  }
  function showToast(msg, isErr){
    var stack = document.getElementById("toastStack");
    var t = document.createElement("div");
    t.className = "toast" + (isErr ? " err" : "");
    t.textContent = msg;
    stack.appendChild(t);
    setTimeout(function(){ t.remove(); }, 2400);
  }
  function setLivePill(ok){
    if (!els.livePill) return;
    els.livePill.classList.toggle("err", !ok);
    els.livePillText.textContent = ok ? "Bridge Online" : "Bridge Offline";
  }

  // ============================================================
  // apply / reset / revert
  // ============================================================
  async function applyNow(showBusy){
    var btns = [document.getElementById("applyBtn"), document.getElementById("applyBtnTweaks"), document.getElementById("applyBtnApps")];
    if (showBusy) btns.forEach(function(b){ if(b){ b.disabled = true; b.textContent = "Applying…"; } });
    await saveConf();
    var t0 = Date.now();
    var r = await ksuExec("sh " + MODDIR + "/apply.sh 2>&1");
    var ms = Date.now() - t0;
    if (showBusy) btns.forEach(function(b){ if(b){ b.disabled = false; b.textContent = "Apply now"; } });
    if (r.errno === 0){
      setStatus("Applied at " + new Date().toLocaleTimeString() + ".");
      if (showBusy) showToast("Applied");
      logOk("apply.sh completed (" + ms + "ms)");
    } else {
      setStatus("apply.sh exited " + r.errno + (r.stdout ? "\n" + r.stdout : ""), true);
      if (showBusy) showToast("Apply failed", true);
      logErr("apply.sh exited " + r.errno + " (" + ms + "ms)" + (r.stderr ? ": " + r.stderr : ""));
    }
    return r;
  }

  // ============================================================
  // render — reflects `state` into the DOM
  // ============================================================
  function render(){
    var boosted = state.REPORT_RATE_MODE === "1";
    els.heroReportRate.classList.toggle("on", boosted);
    els.heroReportRateStatus.textContent = boosted ? "Boosted" : "Stock";

    els.statPowerkeeper.textContent = state.POWERKEEPER_FULL_DISABLE === "1" ? "Full disable" : (state.DISABLE_POWERKEEPER === "1" ? "Disabled" : "Stock");
    els.statDevice.textContent = els.statDevice.dataset.model || "—";
    els.statKernel.textContent = els.statKernel.dataset.kernel || "—";

    els.swPowerkeeperHome.classList.toggle("on", state.DISABLE_POWERKEEPER === "1");
    els.swFastCpuHome.classList.toggle("on", state.FAST_CPU_RESPONSE === "1");

    var apps = state.PRIORITY_APPS.split(" ").filter(Boolean);
    var effectiveCount = apps.length + (state.TG_LAG_FIX === "1" && apps.indexOf("org.telegram.messenger") === -1 ? 1 : 0);
    els.qaPriorityAppsSub.textContent = effectiveCount === 0 ? "None exempted" :
      (effectiveCount === 1 ? "1 app exempted from Doze" : effectiveCount + " apps exempted from Doze");

    els.reportRateSwitches.forEach(function(el){ el.classList.toggle("on", state.REPORT_RATE_MODE === "1"); });
    els.swPowerkeeper.classList.toggle("on", state.DISABLE_POWERKEEPER === "1");
    els.swBatterySpoof.classList.toggle("on", state.SPOOF_BATTERY_TEMP === "1");
    els.swFastCpu.classList.toggle("on", state.FAST_CPU_RESPONSE === "1");
    els.swGpuFloor.classList.toggle("on", state.GPU_FLOOR === "1");
    els.swPowerkeeperFull.classList.toggle("on", state.POWERKEEPER_FULL_DISABLE === "1");
    els.swParallelAnim.classList.toggle("on", state.PARALLEL_ANIM === "1");
    els.swLauncherAnim.classList.toggle("on", state.LAUNCHER_ANIM_RATE === "1");
    els.swTgFix.classList.toggle("on", state.TG_LAG_FIX === "1");
    els.swVmTweaks.classList.toggle("on", state.VM_TWEAKS_ENABLED === "1");

    els.swappinessSlider.value = state.SWAPPINESS;
    els.swappinessVal.textContent = state.SWAPPINESS;
    els.swappinessRow.style.opacity = state.VM_TWEAKS_ENABLED === "1" ? "1" : ".45";
    els.swappinessSlider.disabled = state.VM_TWEAKS_ENABLED !== "1";

    els.chipList.innerHTML = "";
    apps.forEach(function(pkg){
      var chip = document.createElement("div");
      chip.className = "chip";
      var span = document.createElement("span");
      span.textContent = pkg;
      var btn = document.createElement("button");
      btn.textContent = "\u00d7";
      btn.setAttribute("aria-label", "Remove " + pkg);
      btn.addEventListener("click", function(){
        state.PRIORITY_APPS = state.PRIORITY_APPS.split(" ").filter(function(p){ return p && p !== pkg; }).join(" ");
        logInfo("Priority app removed: " + pkg);
        render();
        applyNow(false);
      });
      chip.appendChild(span); chip.appendChild(btn);
      els.chipList.appendChild(chip);
    });
  }

  function renderSettingsSegments(){
    setSeg(els.segMode, uiState.MODE);
    setSeg(els.segAccent, uiState.ACCENT_SOURCE);
    setSeg(els.segAnim, uiState.ANIM);
    setSeg(els.segTransition, uiState.TRANSITION);
    setSeg(els.segExitDir, uiState.EXIT_DIR);
    document.querySelectorAll(".wallpaper-swatch").forEach(function(sw){
      sw.classList.toggle("active", sw.dataset.val === uiState.WALLPAPER);
    });
  }
  function setSeg(container, val){
    if (!container) return;
    container.querySelectorAll(".seg-btn").forEach(function(b){
      b.classList.toggle("active", b.dataset.val === val);
    });
  }

  // ============================================================
  // pages / nav
  // ============================================================
  var titles = {
    home:["Home", "Touch + performance tuning for <device>."],
    tweaks:["Tweaks", "All device tweaks, grouped by what they touch."],
    apps:["Priority Apps", "Per-app background priority."],
    settings:["Settings", "Appearance, motion, and reset."],
    about:["About", "Module and device info."]
  };

  var pageOrder = ["home","tweaks","settings","about"]; // apps has no tab, excluded from swipe order
  var currentPage = "home";

  function switchPage(name, dir){
    if (name === currentPage) return;
    // dir: +1 means "incoming page enters as if content moved left"
    // (i.e. next-in-order / forward), -1 the reverse. Only used by
    // miuix/aosp's --exit-dir; scale/none ignore it entirely.
    if (dir === undefined){
      if (uiState.EXIT_DIR === "right") dir = 1;
      else if (uiState.EXIT_DIR === "left") dir = -1;
      else {
        var from = pageOrder.indexOf(currentPage);
        var to = pageOrder.indexOf(name);
        dir = (from === -1 || to === -1 || to >= from) ? 1 : -1;
      }
    }
    document.documentElement.style.setProperty("--exit-dir", dir);

    document.querySelectorAll(".page").forEach(function(p){ p.hidden = (p.id !== "page-" + name); });
    document.querySelectorAll(".navitem").forEach(function(b){ b.classList.toggle("active", b.dataset.page === name); });
    var t = titles[name];
    els.pageTitle.textContent = t[0];
    if (name === "home"){
      els.pageSub.innerHTML = 'Touch + performance tuning for <span id="devModel">' + (els.lastModel || "your device") + '</span>.';
    } else {
      els.pageSub.textContent = t[1];
    }
    currentPage = name;
    window.scrollTo(0, 0);
  }

  // ---- Appbar: blur intensifies once content has actually scrolled
  // under it, rather than being a flat translucent bar the whole time.
  // `main` has no overflow of its own — the document (window) is the
  // real scroll container here — so we listen on window/scrollY.
  function initScrollChrome(){
    var appbar = document.querySelector(".appbar");
    function onScroll(){
      appbar.classList.toggle("scrolled", (window.scrollY || document.documentElement.scrollTop) > 4);
    }
    window.addEventListener("scroll", onScroll, {passive:true});
    onScroll();
  }

  // ---- Swipe gesture: horizontal drag on `main` moves between
  // pageOrder entries. Vertical scroll is left alone (touch-action:
  // pan-y on main; we only take over once horizontal intent is clear).
  function initSwipe(){
    var main = document.querySelector("main");
    var startX = 0, startY = 0, curX = 0, dragging = false, decided = false, horizontal = false;
    var width = main.clientWidth || 360;

    function activePageEl(){ return document.getElementById("page-" + currentPage); }

    main.addEventListener("touchstart", function(e){
      if (e.touches.length !== 1) return;
      startX = curX = e.touches[0].clientX;
      startY = e.touches[0].clientY;
      dragging = true; decided = false; horizontal = false;
      width = main.clientWidth || 360;
    }, {passive:true});

    main.addEventListener("touchmove", function(e){
      if (!dragging) return;
      var x = e.touches[0].clientX, y = e.touches[0].clientY;
      var dx = x - startX, dy = y - startY;
      if (!decided){
        if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
        horizontal = Math.abs(dx) > Math.abs(dy) * 1.3;
        decided = true;
        if (horizontal) activePageEl().classList.add("dragging");
      }
      if (!horizontal) return;
      // At the boundary of pageOrder, allow a little resistive drag
      // rather than nothing — feels intentional, not broken.
      var idx = pageOrder.indexOf(currentPage);
      var atStart = idx <= 0 && dx > 0;
      var atEnd = idx >= pageOrder.length - 1 && dx < 0;
      curX = startX + (atStart || atEnd ? dx * 0.28 : dx);
      var page = activePageEl();
      page.style.transform = "translateX(" + (curX - startX) + "px)";
      page.style.opacity = String(1 - Math.min(Math.abs(curX - startX) / width, 1) * 0.5);
      e.preventDefault();
    }, {passive:false});

    function endDrag(){
      if (!dragging) return;
      dragging = false;
      if (!horizontal){ decided = false; return; }
      var page = activePageEl();
      page.classList.remove("dragging");
      var delta = curX - startX;
      var threshold = width * 0.22;
      var idx = pageOrder.indexOf(currentPage);
      page.style.transform = ""; page.style.opacity = "";
      if (delta <= -threshold && idx < pageOrder.length - 1){
        var nextName = pageOrder[idx + 1];
        switchPage(nextName, uiState.EXIT_DIR === "gesture" ? 1 : (uiState.EXIT_DIR === "right" ? 1 : -1));
      } else if (delta >= threshold && idx > 0){
        var prevName = pageOrder[idx - 1];
        switchPage(prevName, uiState.EXIT_DIR === "gesture" ? -1 : (uiState.EXIT_DIR === "right" ? 1 : -1));
      }
      decided = false; horizontal = false;
    }
    main.addEventListener("touchend", endDrag, {passive:true});
    main.addEventListener("touchcancel", endDrag, {passive:true});
  }

  // ============================================================
  // dialogs
  // ============================================================
  function showDialog(title, body, onConfirm){
    document.getElementById("dlgTitle").textContent = title;
    document.getElementById("dlgBody").textContent = body;
    var overlay = document.getElementById("overlay");
    overlay.hidden = false;
    var confirmBtn = document.getElementById("dlgConfirm");
    var cancelBtn = document.getElementById("dlgCancel");
    function cleanup(){ overlay.hidden = true; confirmBtn.removeEventListener("click", onOk); cancelBtn.removeEventListener("click", onCancel); }
    function onOk(){ cleanup(); onConfirm(); }
    function onCancel(){ cleanup(); }
    confirmBtn.addEventListener("click", onOk);
    cancelBtn.addEventListener("click", onCancel);
  }

  // ============================================================
  // device / module info
  // ============================================================
  // Friendly marketing names for devices this module confirms/targets.
  // Keyed by ro.product.device (the code, e.g. "duchamp") since that's
  // stable across regions/ROMs, unlike ro.product.model which varies
  // (e.g. "2311DRK48C" vs "23122PCD1G" for the same phone in different
  // markets). Add new entries here as more devices get confirmed.
  var DEVICE_NAMES = {
    duchamp: "Poco X6 Pro",
    rodin: "Poco X7 Pro"
  };

  async function loadDevice(){
    var r = await ksuExec("getprop ro.product.model; getprop ro.product.device; uname -r");
    var lines = r.stdout.split("\n").filter(Boolean);
    var model = (lines[0] || "").trim();
    var code = (lines[1] || "").trim();
    var kernel = (lines[2] || "").trim();
    var friendly = DEVICE_NAMES[code] || model || "your device";

    els.lastModel = friendly;
    els.devCode.textContent = code || "—";
    document.getElementById("mDevice").textContent = (model || "—") + (code ? " (" + code + ")" : "");
    els.statDevice.dataset.model = friendly;
    els.statDevice.textContent = friendly;
    els.statKernel.dataset.kernel = kernel || "—";
    els.statKernel.textContent = kernel || "—";
    els.pageSub.innerHTML = 'Touch + performance tuning for <span id="devModel">' + els.lastModel + '</span>.';

    setLivePill(r.errno === 0);
    if (r.errno !== 0) logErr("Root bridge unavailable — open this page from your root manager app");

    var profile = "experimental";
    var profileLabel = "Experimental";
    if (code === "duchamp"){ profile = "confirmed"; profileLabel = "Confirmed"; }
    else if (code === "rodin"){ profile = "experimental-named"; profileLabel = "Experimental (Rodin)"; }
    document.getElementById("mProfile").textContent = profile;
    document.getElementById("mProfile2").textContent = profileLabel.toLowerCase();

    // Mirrors apply.sh's detect_rom() so the WebUI shows the same
    // answer even before the first apply has run.
    var romCmd = "hyperos=$(getprop ro.mi.os.version.name); miui=$(getprop ro.miui.ui.version.name);" +
      "if [ -n \"$hyperos\" ]; then echo \"HyperOS $hyperos\";" +
      "elif [ -n \"$miui\" ]; then echo \"MIUI $miui\";" +
      "elif [ -n \"$(getprop ro.infinity.version)\" ]; then echo \"InfinityX $(getprop ro.infinity.version)\";" +
      "elif [ -n \"$(getprop ro.lineage.version)\" ]; then echo \"LineageOS $(getprop ro.lineage.version)\";" +
      "elif [ -n \"$(getprop ro.crdroid.version)\" ]; then echo \"crDroid $(getprop ro.crdroid.version)\";" +
      "elif [ -n \"$(getprop ro.pixelexperience.version)\" ]; then echo \"PixelExperience $(getprop ro.pixelexperience.version)\";" +
      "elif [ -n \"$(getprop ro.aospa.version)\" ]; then echo \"AOSPA $(getprop ro.aospa.version)\";" +
      "elif [ -n \"$(getprop ro.build.version.opporom)\" ] || [ -n \"$(getprop ro.oplus.version)\" ]; then echo \"ColorOS-based $(getprop ro.build.version.opporom)\";" +
      "else echo \"AOSP-based (Android $(getprop ro.build.version.release))\"; fi";
    var rr = await ksuExec(romCmd);
    if (rr.errno === 0 && rr.stdout) document.getElementById("mRom").textContent = rr.stdout.trim();

    // Refresh rate — mirrors apply.sh's fixed detection: reads the
    // active mode's fps from SurfaceFlinger, not the max advertised.
    var refreshCmd = "dumpsys SurfaceFlinger 2>/dev/null | grep -o 'refresh-rate:[[:space:]]*[0-9.]*' | head -1 | grep -o '[0-9.]*$'";
    var rf = await ksuExec(refreshCmd);
    var refreshVal = (rf.stdout || "").trim();
    els.statRefresh.textContent = refreshVal ? Math.round(parseFloat(refreshVal)) + " Hz" : "—";
  }

  async function loadModuleProp(){
    var r = await ksuExec("cat " + MODDIR + "/module.prop");
    if (r.errno !== 0 || !r.stdout) return;
    var p = parseConf(r.stdout);
    if (p.version) document.getElementById("mVersion").textContent = p.version;
    if (p.author) document.getElementById("mAuthor").textContent = p.author;
  }

  // ============================================================
  // init
  // ============================================================
  function init(){
    els.livePill = document.getElementById("livePill");
    els.livePillText = document.getElementById("livePillText");
    els.pageTitle = document.getElementById("pageTitle");
    els.pageSub = document.getElementById("pageSub");
    els.devCode = document.getElementById("devCode");
    els.heroReportRate = document.getElementById("heroReportRate");
    els.heroReportRateStatus = document.getElementById("heroReportRateStatus");
    els.statPowerkeeper = document.getElementById("statPowerkeeper");
    els.statRefresh = document.getElementById("statRefresh");
    els.statDevice = document.getElementById("statDevice");
    els.statKernel = document.getElementById("statKernel");
    els.swPowerkeeperHome = document.getElementById("swPowerkeeperHome");
    els.swFastCpuHome = document.getElementById("swFastCpuHome");
    els.qaPriorityAppsSub = document.getElementById("qaPriorityAppsSub");
    els.reportRateSwitches = [document.getElementById("swReportRate2")];
    els.swPowerkeeper = document.getElementById("swPowerkeeper");
    els.swPowerkeeperFull = document.getElementById("swPowerkeeperFull");
    els.swBatterySpoof = document.getElementById("swBatterySpoof");
    els.swFastCpu = document.getElementById("swFastCpu");
    els.swGpuFloor = document.getElementById("swGpuFloor");
    els.swParallelAnim = document.getElementById("swParallelAnim");
    els.swLauncherAnim = document.getElementById("swLauncherAnim");
    els.swTgFix = document.getElementById("swTgFix");
    els.swVmTweaks = document.getElementById("swVmTweaks");
    els.swappinessSlider = document.getElementById("swappinessSlider");
    els.swappinessVal = document.getElementById("swappinessVal");
    els.swappinessRow = document.getElementById("swappinessRow");
    els.chipList = document.getElementById("chipList");
    els.pkgInput = document.getElementById("pkgInput");
    els.segMode = document.getElementById("segMode");
    els.segAccent = document.getElementById("segAccent");
    els.segAnim = document.getElementById("segAnim");
    els.segTransition = document.getElementById("segTransition");
    els.segExitDir = document.getElementById("segExitDir");
    els.shellBtn = document.getElementById("shellBtn");
    els.shellScrim = document.getElementById("shellScrim");
    els.shellPanel = document.getElementById("shellPanel");
    els.shellBody = document.getElementById("shellBody");
    els.shellClose = document.getElementById("shellClose");
    els.shellClear = document.getElementById("shellClear");

    document.querySelectorAll(".navitem").forEach(function(b){
      b.addEventListener("click", function(){ switchPage(b.dataset.page); });
    });
    document.querySelectorAll("[data-goto]").forEach(function(el){
      el.addEventListener("click", function(){ switchPage(el.dataset.goto); });
    });

    function toggleState(key, label){
      state[key] = state[key] === "1" ? "0" : "1";
      logInfo(label + " → " + (state[key] === "1" ? "on" : "off"));
      render(); applyNow(false);
    }

    els.heroReportRate.addEventListener("click", function(){ toggleState("REPORT_RATE_MODE", "Boosted report rate"); });
    els.reportRateSwitches.forEach(function(el){
      el.addEventListener("click", function(){ toggleState("REPORT_RATE_MODE", "Boosted report rate"); });
    });
    els.swPowerkeeperHome.addEventListener("click", function(){ toggleState("DISABLE_POWERKEEPER", "PowerKeeper disable"); });
    els.swFastCpuHome.addEventListener("click", function(){ toggleState("FAST_CPU_RESPONSE", "Fast CPU response"); });
    els.swPowerkeeper.addEventListener("click", function(){ toggleState("DISABLE_POWERKEEPER", "PowerKeeper disable"); });
    els.swBatterySpoof.addEventListener("click", function(){ toggleState("SPOOF_BATTERY_TEMP", "Battery temp spoof"); });
    els.swFastCpu.addEventListener("click", function(){ toggleState("FAST_CPU_RESPONSE", "Fast CPU response"); });
    els.swGpuFloor.addEventListener("click", function(){ toggleState("GPU_FLOOR", "GPU floor"); });
    els.swPowerkeeperFull.addEventListener("click", function(){ toggleState("POWERKEEPER_FULL_DISABLE", "PowerKeeper full disable"); });
    els.swParallelAnim.addEventListener("click", function(){ toggleState("PARALLEL_ANIM", "Parallel animation"); });
    els.swLauncherAnim.addEventListener("click", function(){ toggleState("LAUNCHER_ANIM_RATE", "Launcher animation rate"); });
    els.swTgFix.addEventListener("click", function(){ toggleState("TG_LAG_FIX", "TG lag fix"); });
    els.swVmTweaks.addEventListener("click", function(){ toggleState("VM_TWEAKS_ENABLED", "VM/ZRAM tweaks"); });
    els.swappinessSlider.addEventListener("change", function(){
      state.SWAPPINESS = String(els.swappinessSlider.value);
      logInfo("Swappiness → " + state.SWAPPINESS);
      render(); applyNow(false);
    });
    els.swappinessSlider.addEventListener("input", function(){
      els.swappinessVal.textContent = els.swappinessSlider.value;
    });
    els.pkgInput.addEventListener("keydown", function(e){ if (e.key === "Enter") document.getElementById("pkgAdd").click(); });
    document.getElementById("pkgAdd").addEventListener("click", function(){
      var v = els.pkgInput.value.trim();
      if (!v) return;
      var current = state.PRIORITY_APPS.split(" ").filter(Boolean);
      if (current.indexOf(v) === -1) current.push(v);
      state.PRIORITY_APPS = current.join(" ");
      els.pkgInput.value = "";
      logInfo("Priority app added: " + v);
      render(); applyNow(false);
    });

    ["applyBtn","applyBtnTweaks","applyBtnApps"].forEach(function(id){
      var b = document.getElementById(id);
      if (b) b.addEventListener("click", function(){ applyNow(true); });
    });

    els.segMode.addEventListener("click", function(e){
      var b = e.target.closest(".seg-btn");
      if (b) updateUiPref("MODE", b.dataset.val);
    });
    els.segAccent.addEventListener("click", function(e){
      var b = e.target.closest(".seg-btn");
      if (b) updateUiPref("ACCENT_SOURCE", b.dataset.val);
    });
    els.segAnim.addEventListener("click", function(e){
      var b = e.target.closest(".seg-btn");
      if (b) updateUiPref("ANIM", b.dataset.val);
    });
    els.segTransition.addEventListener("click", function(e){
      var b = e.target.closest(".seg-btn");
      if (b) updateUiPref("TRANSITION", b.dataset.val);
    });
    els.segExitDir.addEventListener("click", function(e){
      var b = e.target.closest(".seg-btn");
      if (b) updateUiPref("EXIT_DIR", b.dataset.val);
    });
    document.querySelectorAll(".wallpaper-swatch").forEach(function(sw){
      sw.addEventListener("click", function(){ updateUiPref("WALLPAPER", sw.dataset.val); });
    });

    document.getElementById("resetBtn").addEventListener("click", function(){
      showDialog("Reset to defaults?", "This restores settings.conf to the shipped defaults and re-applies. Cannot be undone from here.", async function(){
        setStatus("Resetting…");
        logInfo("Reset to defaults requested");
        var r = await ksuExec("sh " + MODDIR + "/action.sh reset 2>&1");
        setStatus(r.stdout || (r.errno === 0 ? "Reset." : "Reset failed."), r.errno !== 0);
        showToast(r.errno === 0 ? "Reset to defaults" : "Reset failed", r.errno !== 0);
        if (r.errno === 0) logOk("Reset to defaults completed"); else logErr("Reset failed (errno " + r.errno + ")");
        loadConf();
      });
    });
    document.getElementById("revertBtn").addEventListener("click", function(){
      showDialog("Revert now?", "Temporarily undoes tweaks for this session without changing your saved settings.conf.", async function(){
        setStatus("Reverting…");
        logInfo("Revert requested");
        var r = await ksuExec("sh " + MODDIR + "/action.sh revert 2>&1");
        setStatus(r.stdout || (r.errno === 0 ? "Reverted." : "Revert failed."), r.errno !== 0);
        showToast(r.errno === 0 ? "Reverted" : "Revert failed", r.errno !== 0);
        if (r.errno === 0) logOk("Revert completed"); else logErr("Revert failed (errno " + r.errno + ")");
      });
    });
    document.getElementById("githubBtn").addEventListener("click", function(){
      ksuExec("am start -a android.intent.action.VIEW -d 'https://github.com/sandtomatowich-hubexe/HyperTouch' >/dev/null 2>&1");
    });
    document.getElementById("probeInfoBtn").addEventListener("click", function(){
      showDialog("Touch report-rate node", "apply.sh auto-detects between two known Goodix driver node names at apply time. If your build uses a third name, run tools/probe_device.sh as root (it only reads sysfs, never writes) and share the output on GitHub so it can be added.", function(){});
    });

    els.shellBtn.addEventListener("click", openShell);
    els.shellClose.addEventListener("click", closeShell);
    els.shellScrim.addEventListener("click", closeShell);
    els.shellClear.addEventListener("click", function(){
      logEntries = [];
      renderLog();
      els.shellBtn.classList.remove("has-activity");
      ksuExec("mkdir -p " + MODDIR + "/webui 2>/dev/null; : > '" + LOGFILE + "'");
    });

    render();
    initSwipe();
    initScrollChrome();
    Promise.all([loadDevice(), loadConf(), loadModuleProp(), loadUiConf()]).then(function(){
      document.querySelectorAll(".skel").forEach(function(el){ el.classList.remove("skel"); });
    });
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
