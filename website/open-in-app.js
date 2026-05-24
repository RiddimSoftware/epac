(function () {
  var APP_STORE_URL = "https://apps.apple.com/ca/app/epac/id1224459142";
  var GATEWAY_PATH = "/app/";

  function isAppleMobile() {
    var ua = window.navigator.userAgent || "";
    var iOSDevice = /iPhone|iPad|iPod/.test(ua);
    var iPadDesktopMode = window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1;
    return iOSDevice || iPadDesktopMode;
  }

  function currentPath() {
    return window.location.pathname + window.location.search + window.location.hash;
  }

  function gatewayUrl(source) {
    var url = new URL(GATEWAY_PATH, window.location.origin);
    url.searchParams.set("path", currentPath());
    url.searchParams.set("utm_source", "epac-web");
    url.searchParams.set("utm_medium", source);
    url.searchParams.set("utm_campaign", "open-in-app");
    return url.toString();
  }

  function appStoreUrl() {
    var url = new URL(APP_STORE_URL);
    url.searchParams.set("ct", "epac-web-open-in-app");
    url.searchParams.set("mt", "8");
    url.searchParams.set("utm_source", "epac-web");
    url.searchParams.set("utm_medium", "open-in-app-fallback");
    url.searchParams.set("utm_campaign", "open-in-app");
    url.searchParams.set("epac_path", currentPath());
    return url.toString();
  }

  function sendTelemetry(eventName) {
    var url = new URL("/app/telemetry/", window.location.origin);
    url.searchParams.set("event", eventName);
    url.searchParams.set("path", currentPath());
    url.searchParams.set("ts", String(Date.now()));

    var pixel = new Image();
    pixel.src = url.toString();
  }

  function ensureSmartBannerMeta() {
    var content = "app-id=1224459142, app-argument=" + gatewayUrl("smart-banner");
    var meta = document.querySelector('meta[name="apple-itunes-app"]');
    if (meta) {
      meta.setAttribute("content", content);
    } else {
      meta = document.createElement("meta");
      meta.setAttribute("name", "apple-itunes-app");
      meta.setAttribute("content", content);
      document.head.appendChild(meta);
    }
  }

  function injectStyles() {
    if (document.getElementById("open-in-app-style")) { return; }
    var style = document.createElement("style");
    style.id = "open-in-app-style";
    style.textContent = [
      ".open-in-app-banner{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:12px 14px 0;padding:12px 14px;border:1px solid rgba(0,0,0,.1);border-radius:16px;background:rgba(255,255,255,.94);color:#111;box-shadow:0 12px 30px rgba(0,0,0,.12);font-family:-apple-system,BlinkMacSystemFont,'Inter','Segoe UI',sans-serif;position:relative;z-index:20}",
      ".open-in-app-copy{min-width:0}",
      ".open-in-app-title{display:block;font-size:14px;font-weight:700;line-height:1.2}",
      ".open-in-app-subtitle{display:block;margin-top:2px;font-size:12px;line-height:1.25;color:#5f6368}",
      ".open-in-app-button{flex:0 0 auto;display:inline-flex;align-items:center;justify-content:center;min-height:36px;padding:0 14px;border-radius:999px;background:#007aff;color:#fff;text-decoration:none;font-size:13px;font-weight:700;white-space:nowrap}",
      ".open-in-app-store{display:none}",
      "@media(prefers-color-scheme:dark){",
      ".open-in-app-banner{border-color:rgba(255,255,255,.14);background:rgba(24,24,27,.94);color:#fff;box-shadow:0 12px 30px rgba(0,0,0,.34)}",
      ".open-in-app-subtitle{color:#b8bcc4}",
      "}",
      "@media(max-width:760px){",
      ".open-in-app-banner{margin:12px 14px 0}",
      "}"
    ].join("");
    document.head.appendChild(style);
  }

  function renderBanner() {
    if (!isAppleMobile()) { return; }
    if (window.location.pathname.replace(/\/+$/, "") === "/app") { return; }
    if (document.querySelector(".open-in-app-banner")) { return; }

    injectStyles();

    var banner = document.createElement("aside");
    banner.className = "open-in-app-banner";
    banner.setAttribute("aria-label", "Open this page in epac");
    banner.innerHTML = [
      '<span class="open-in-app-copy">',
      '<span class="open-in-app-title">Open in epac</span>',
      '<span class="open-in-app-subtitle">Continue with this exact page in the app.</span>',
      '</span>',
      '<a class="open-in-app-button" data-open-in-app-link href="' + gatewayUrl("mobile-cta") + '">Open</a>',
      '<a class="open-in-app-store" href="' + appStoreUrl() + '">App Store</a>'
    ].join("");

    var link = banner.querySelector("[data-open-in-app-link]");
    link.addEventListener("click", function () {
      sendTelemetry("cta-click");
    });

    document.body.insertBefore(banner, document.body.firstChild);
  }

  ensureSmartBannerMeta();

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", renderBanner);
  } else {
    renderBanner();
  }
})();
