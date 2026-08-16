// HyperTouch — app.js
"use strict";
(function(){
  var MODDIR = "/data/adb/modules/hypertouch";
  var CONF = MODDIR + "/settings.conf";
  var UICONF = MODDIR + "/webui/ui.conf";
  var cbSeq = 0;

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
  // Device-tweak state (settings.conf) — unchanged from before.
  // ============================================================
  var state = {
    REPORT_RATE_MODE:"1", DISABLE_POWERKEEPER:"1", SPOOF_BATTERY_TEMP:"0",
    TOUCH_SENSITIVITY_PATH:"", TOUCH_SENSITIVITY_VALUE:"",
    TOUCH_EDGE_PATH:"", TOUCH_EDGE_VALUE:"",
    PALM_REJECT_PATH:"", PALM_REJECT_VALUE:"",
    SMOOTH_TOUCH_MODE:"1", PRIORITY_APPS:"", TG_LAG_FIX:"0",
    CONF_VERSION:"2"
  };

  // ============================================================
  // WebUI-only preferences (webui/ui.conf) — separate file, never
  // touched by apply.sh/action.sh. Purely cosmetic, purely ours.
  // ============================================================
  var uiState = {
    MODE:"dark",          // dark | light | system
    ACCENT_SOURCE:"fixed", // fixed | monet
    WALLPAPER:"none",      // none | signal | aurora | grid
    ANIM:"full"            // full | reduced | off
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

  // ---- Monet: best-effort, silent fallback ----
  // Reads the live Material You accent Android generates from the
  // wallpaper. Confirmed working on stock AOSP 12+ via `cmd overlay
  // lookup`; HyperOS has its own theming engine so this may or may not
  // return a color there — if it doesn't, this quietly no-ops and the
  // signature default accent stays active instead of breaking anything.
  async function tryApplyMonet(){
    if (uiState.ACCENT_SOURCE !== "monet"){
      document.documentElement.style.removeProperty("--accent");
      return;
    }
    var r = await ksuExec("cmd overlay lookup android android:color/system_accent1_500 2>/dev/null");
    var hex = null;
    if (r.errno === 0 && r.stdout){
      var m = r.stdout.match(/([0-9a-fA-F]{6,8})/);
      if (m) hex = "#" + m[1].slice(-6);
    }
    if (hex){
      document.documentElement.style.setProperty("--accent", hex);
    } else {
      document.documentElement.style.removeProperty("--accent");
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
      "ANIM=" + uiState.ANIM
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
    await tryApplyMonet();
    renderSettingsSegments();
  }

  async function saveUiConf(){
    var cmd = "mkdir -p " + MODDIR + "/webui 2>/dev/null; cat > '" + UICONF + "' << 'HT_EOF'\n" + renderUiConf() + "\nHT_EOF";
    return ksuExec(cmd);
  }

  async function updateUiPref(key, val){
    uiState[key] = val;
    applyMode(); applyWallpaper(); applyAnim();
    if (key === "ACCENT_SOURCE") await tryApplyMonet();
    renderSettingsSegments();
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
      "SPOOF_BATTERY_TEMP=" + state.SPOOF_BATTERY_TEMP,
      "",
      "# ── Touch tuning (kernel-dependent, pending device data) ───",
      "TOUCH_SENSITIVITY_PATH=" + state.TOUCH_SENSITIVITY_PATH,
      "TOUCH_SENSITIVITY_VALUE=" + state.TOUCH_SENSITIVITY_VALUE,
      "TOUCH_EDGE_PATH=" + state.TOUCH_EDGE_PATH,
      "TOUCH_EDGE_VALUE=" + state.TOUCH_EDGE_VALUE,
      "PALM_REJECT_PATH=" + state.PALM_REJECT_PATH,
      "PALM_REJECT_VALUE=" + state.PALM_REJECT_VALUE,
      "",
      "# ── Smooth Touch (userspace, kernel-independent) ────────────",
      "SMOOTH_TOUCH_MODE=" + state.SMOOTH_TOUCH_MODE,
      "",
      "# ── Priority Apps (userspace, kernel-independent) ───────────",
      "PRIORITY_APPS=" + state.PRIORITY_APPS,
      "TG_LAG_FIX=" + state.TG_LAG_FIX,
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
    } else {
      render();
      setStatus(window.ksu ? "Could not read settings.conf — using defaults." : "Open this from your root manager to enable controls.", true);
    }
  }

  async function saveConf(){
    var cmd = "cat > '" + CONF + "' << 'HT_EOF'\n" + renderConf() + "\nHT_EOF";
    return ksuExec(cmd);
  }

  // ============================================================
  // status / toast
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

  // ============================================================
  // apply / reset / revert
  // ============================================================
  async function applyNow(showBusy){
    var btns = [document.getElementById("applyBtn"), document.getElementById("applyBtnTweaks"), document.getElementById("applyBtnApps")];
    if (showBusy) btns.forEach(function(b){ if(b){ b.disabled = true; b.textContent = "Applying…"; } });
    await saveConf();
    var r = await ksuExec("sh " + MODDIR + "/apply.sh 2>&1");
    if (showBusy) btns.forEach(function(b){ if(b){ b.disabled = false; b.textContent = "Apply now"; } });
    if (r.errno === 0){
      setStatus("Applied at " + new Date().toLocaleTimeString() + ".");
      if (showBusy) showToast("Applied");
    } else {
      setStatus("apply.sh exited " + r.errno + (r.stdout ? "\n" + r.stdout : ""), true);
      if (showBusy) showToast("Apply failed", true);
    }
    return r;
  }

  // ============================================================
  // render — reflects `state` into the DOM
  // ============================================================
  var smoothLabels = {"0":"Stock", "1":"Fast", "2":"Instant"};

  function render(){
    els.reportRateSwitches.forEach(function(el){ el.classList.toggle("on", state.REPORT_RATE_MODE === "1"); });
    els.swPowerkeeper.classList.toggle("on", state.DISABLE_POWERKEEPER === "1");
    els.swBatterySpoof.classList.toggle("on", state.SPOOF_BATTERY_TEMP === "1");
    els.swTgFix.classList.toggle("on", state.TG_LAG_FIX === "1");

    var boosted = state.REPORT_RATE_MODE === "1";
    els.heroReportRate.classList.toggle("on", boosted);
    els.heroReportRateStatus.textContent = boosted ? "Boosted" : "Stock";
    els.statSmooth.textContent = smoothLabels[state.SMOOTH_TOUCH_MODE] || "Fast";

    els.smoothSegs.forEach(function(seg){
      seg.querySelectorAll(".seg-btn").forEach(function(b){
        b.classList.toggle("active", b.dataset.val === state.SMOOTH_TOUCH_MODE);
      });
    });

    els.chipList.innerHTML = "";
    state.PRIORITY_APPS.split(" ").filter(Boolean).forEach(function(pkg){
      var chip = document.createElement("div");
      chip.className = "chip";
      var span = document.createElement("span");
      span.textContent = pkg;
      var btn = document.createElement("button");
      btn.textContent = "\u00d7";
      btn.addEventListener("click", function(){
        state.PRIORITY_APPS = state.PRIORITY_APPS.split(" ").filter(function(p){ return p && p !== pkg; }).join(" ");
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
    home:["Home", null],
    tweaks:["Tweaks", "All device tweaks"],
    apps:["Apps", "Per-app background priority"],
    settings:["Settings", "Appearance & module info"]
  };

  function switchPage(name){
    document.querySelectorAll(".page").forEach(function(p){ p.hidden = (p.id !== "page-" + name); });
    document.querySelectorAll(".navitem").forEach(function(b){ b.classList.toggle("active", b.dataset.page === name); });
    els.pageTitle.textContent = titles[name][0];
    var sub = titles[name][1];
    if (sub){
      els.pageSubText.textContent = sub;
      els.pageSubText.hidden = false;
      els.pageSubDevice.hidden = true;
    } else {
      els.pageSubText.hidden = true;
      els.pageSubDevice.hidden = false;
    }
    window.scrollTo(0, 0);
    els.topbar.classList.remove("compact");
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
  async function loadDevice(){
    var r = await ksuExec("getprop ro.product.model; getprop ro.product.device");
    var lines = r.stdout.split("\n").filter(Boolean);
    if (lines[0]) document.getElementById("devModel").textContent = lines[0].trim();
    if (lines[1]) document.getElementById("devCode").textContent = lines[1].trim();
    if (lines[1]) document.getElementById("mDevice").textContent = lines[1].trim();
    if (r.errno === 0) els.liveDot.classList.add("live");

    var deviceCode = (lines[1] || "").trim();
    var profile = deviceCode === "duchamp" ? "confirmed" : "experimental";
    document.getElementById("mProfile").textContent = profile;
    els.statProfile.textContent = profile === "confirmed" ? "Confirmed" : "Experimental";
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
    els.liveDot = document.getElementById("liveDot");
    els.pageTitle = document.getElementById("pageTitle");
    els.pageSubText = document.getElementById("pageSubText");
    els.pageSubDevice = document.getElementById("pageSubDevice");
    els.topbar = document.querySelector("header.topbar");
    els.heroReportRate = document.getElementById("heroReportRate");
    els.heroReportRateStatus = document.getElementById("heroReportRateStatus");
    els.statProfile = document.getElementById("statProfile");
    els.statSmooth = document.getElementById("statSmooth");
    els.reportRateSwitches = [document.getElementById("swReportRate2")];
    els.swPowerkeeper = document.getElementById("swPowerkeeper");
    els.swBatterySpoof = document.getElementById("swBatterySpoof");
    els.swTgFix = document.getElementById("swTgFix");
    els.smoothSegs = [document.getElementById("segSmoothHome"), document.getElementById("segSmoothTweaks")];
    els.chipList = document.getElementById("chipList");
    els.pkgInput = document.getElementById("pkgInput");
    els.segMode = document.getElementById("segMode");
    els.segAccent = document.getElementById("segAccent");
    els.segAnim = document.getElementById("segAnim");

    document.querySelectorAll(".navitem").forEach(function(b){
      b.addEventListener("click", function(){ switchPage(b.dataset.page); });
    });
    window.addEventListener("scroll", function(){
      els.topbar.classList.toggle("compact", window.scrollY > 28);
    }, {passive:true});

    els.heroReportRate.addEventListener("click", function(){
      state.REPORT_RATE_MODE = state.REPORT_RATE_MODE === "1" ? "0" : "1";
      render(); applyNow(false);
    });
    els.reportRateSwitches.forEach(function(el){
      el.addEventListener("click", function(){
        state.REPORT_RATE_MODE = state.REPORT_RATE_MODE === "1" ? "0" : "1";
        render(); applyNow(false);
      });
    });
    els.swPowerkeeper.addEventListener("click", function(){
      state.DISABLE_POWERKEEPER = state.DISABLE_POWERKEEPER === "1" ? "0" : "1";
      render(); applyNow(false);
    });
    els.swBatterySpoof.addEventListener("click", function(){
      state.SPOOF_BATTERY_TEMP = state.SPOOF_BATTERY_TEMP === "1" ? "0" : "1";
      render(); applyNow(false);
    });
    els.swTgFix.addEventListener("click", function(){
      state.TG_LAG_FIX = state.TG_LAG_FIX === "1" ? "0" : "1";
      render(); applyNow(false);
    });
    els.smoothSegs.forEach(function(seg){
      seg.addEventListener("click", function(e){
        var b = e.target.closest(".seg-btn");
        if (!b) return;
        state.SMOOTH_TOUCH_MODE = b.dataset.val;
        render(); applyNow(false);
      });
    });
    els.pkgInput.addEventListener("keydown", function(e){ if (e.key === "Enter") document.getElementById("pkgAdd").click(); });
    document.getElementById("pkgAdd").addEventListener("click", function(){
      var v = els.pkgInput.value.trim();
      if (!v) return;
      var current = state.PRIORITY_APPS.split(" ").filter(Boolean);
      if (current.indexOf(v) === -1) current.push(v);
      state.PRIORITY_APPS = current.join(" ");
      els.pkgInput.value = "";
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
    document.querySelectorAll(".wallpaper-swatch").forEach(function(sw){
      sw.addEventListener("click", function(){ updateUiPref("WALLPAPER", sw.dataset.val); });
    });

    document.getElementById("resetBtn").addEventListener("click", function(){
      showDialog("Reset to defaults?", "This restores settings.conf to the shipped defaults and re-applies. Cannot be undone from here.", async function(){
        setStatus("Resetting…");
        var r = await ksuExec("sh " + MODDIR + "/action.sh reset 2>&1");
        setStatus(r.stdout || (r.errno === 0 ? "Reset." : "Reset failed."), r.errno !== 0);
        showToast(r.errno === 0 ? "Reset to defaults" : "Reset failed", r.errno !== 0);
        loadConf();
      });
    });
    document.getElementById("revertBtn").addEventListener("click", function(){
      showDialog("Revert now?", "Temporarily undoes tweaks for this session without changing your saved settings.conf.", async function(){
        setStatus("Reverting…");
        var r = await ksuExec("sh " + MODDIR + "/action.sh revert 2>&1");
        setStatus(r.stdout || (r.errno === 0 ? "Reverted." : "Revert failed."), r.errno !== 0);
        showToast(r.errno === 0 ? "Reverted" : "Revert failed", r.errno !== 0);
      });
    });
    document.getElementById("githubBtn").addEventListener("click", function(){
      ksuExec("am start -a android.intent.action.VIEW -d 'https://github.com/sandtomatowich-hubexe/HyperTouch' >/dev/null 2>&1");
    });
    document.getElementById("probeInfoBtn").addEventListener("click", function(){
      showDialog("Unlocking touch tuning", "Run tools/probe_touch.sh as root (adb shell su -c \"sh /sdcard/probe_touch.sh\"). It only reads sysfs, never writes. Share the output on GitHub and the real sensitivity/edge/palm-reject nodes get wired in.", function(){});
    });

    render();
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
 
