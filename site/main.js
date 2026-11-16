// CallBridge landing page interactions.
// Restrained on purpose: the banner drops once, chips copy, the switch flips,
// sections fade in. Everything honors prefers-reduced-motion.

const repo = "thepushkaraj/CallBridge";
const fallback = {
  version: "0.4.2",
  apk: "https://github.com/thepushkaraj/CallBridge/releases/download/v0.4.2/CallBridge-v0.4.2.apk",
  zip: "https://github.com/thepushkaraj/CallBridge/releases/download/v0.4.2/CallBridge-macOS.zip",
  notes: "https://github.com/thepushkaraj/CallBridge/releases/tag/v0.4.2",
};

function applyRelease(version, apk, zip, notes, apkName) {
  document.querySelectorAll("[data-version]").forEach((node) => {
    node.textContent = version;
  });
  document.querySelectorAll("[data-apk]").forEach((node) => {
    node.href = apk;
  });
  document.querySelectorAll("[data-zip]").forEach((node) => {
    node.href = zip;
  });
  document.querySelectorAll("[data-notes]").forEach((node) => {
    node.href = notes;
  });
  document.querySelectorAll("[data-apk-name]").forEach((node) => {
    node.textContent = apkName;
  });
}

async function loadRelease() {
  try {
    const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) throw new Error(String(response.status));
    const release = await response.json();
    const version = String(release.tag_name || fallback.version).replace(/^v/, "");
    const assets = Array.isArray(release.assets) ? release.assets : [];
    const apk = assets.find((a) => a.name.startsWith("CallBridge-") && a.name.endsWith(".apk"));
    const zip = assets.find((a) => a.name === "CallBridge-macOS.zip");
    applyRelease(
      version,
      apk ? apk.browser_download_url : fallback.apk,
      zip ? zip.browser_download_url : fallback.zip,
      release.html_url || fallback.notes,
      apk ? apk.name : `CallBridge-v${version}.apk`
    );
  } catch {
    applyRelease(fallback.version, fallback.apk, fallback.zip, fallback.notes, `CallBridge-v${fallback.version}.apk`);
  }
}

// ---- the macOS banner: drops in where macOS drops banners ----
function stageBanner() {
  const banner = document.querySelector("[data-banner]");
  if (!banner) return;
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  banner.setAttribute("aria-hidden", "false");
  const show = () => banner.classList.add("is-in");
  if (reduced) {
    show();
    return;
  }
  setTimeout(show, 900);
  setTimeout(() => banner.classList.add("is-out"), 11000);
  banner.querySelector("[data-banner-close]").addEventListener("click", () => {
    banner.classList.add("is-out");
  });
}

// ---- copy chips: flip to Copied ✓, actually copy ----
function stageChips() {
  document.querySelectorAll("[data-copy]").forEach((chip) => {
    chip.addEventListener("click", async () => {
      const value = chip.getAttribute("data-copy");
      try {
        await navigator.clipboard.writeText(value);
      } catch {
        /* the flip alone still demonstrates the interaction */
      }
      chip.classList.add("is-done");
      chip.textContent = "Copied ✓";
      const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      if (!reduced) {
        setTimeout(() => {
          chip.classList.remove("is-done");
          chip.textContent = "Copy code";
        }, 2200);
      }
    });
  });
}

// ---- the Forward SMS switch ----
function stageSwitch() {
  const sw = document.querySelector("[data-switch]");
  if (!sw) return;
  const state = document.querySelector("[data-switch-state]");
  sw.addEventListener("click", () => {
    const on = sw.getAttribute("aria-pressed") !== "true";
    sw.setAttribute("aria-pressed", String(on));
    if (state) state.textContent = on ? "on · texts may arrive" : "off";
  });
}

// ---- scroll reveals ----
function stageReveals() {
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const targets = document.querySelectorAll(
    ".arrivals-copy, .arrivals-stage, .how > h2, .moves li, .wire-copy, .terminal, .sms-copy, .sms-stage, .limits-inner, .download > h2, .dl-cards"
  );
  targets.forEach((el) => el.classList.add("reveal"));
  if (reduced || !("IntersectionObserver" in window)) {
    targets.forEach((el) => el.classList.add("in"));
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.18, rootMargin: "0px 0px -8% 0px" }
  );
  targets.forEach((el) => io.observe(el));
}

loadRelease();
stageBanner();
stageChips();
stageSwitch();
stageReveals();
