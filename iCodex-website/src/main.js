import "./styles.css";

const appLinks = {
  ios:    "https://apps.apple.com/us/search?term=iCodex",
  dmg:    "https://github.com/adidshaft/iCodex/releases/download/main-build/iCodex-Connect.dmg",
  appZip: "https://github.com/adidshaft/iCodex/releases/download/main-build/iCodex-Connect.app.zip",
};

const supabaseConfig = {
  url:     import.meta.env.VITE_SUPABASE_URL     ?? "",
  anonKey: import.meta.env.VITE_SUPABASE_ANON_KEY ?? "",
};

const releaseMeta = {
  version:     "2.1.0",
  minimumMacOS:"12+",
  dmgChecksum: "DMG  56bdbe64124374090cce41c79fa3d9e2b9a94b5abc68262a6d63d7c045c0cf0d",
  appChecksum: "ZIP  c154c906414afd1cf6a2bce7732f20fe2659154e52f9ce054d5ac7a5ed879141",
};

/* ── hydrate links ────────────────────────────────────────────── */
for (const el of document.querySelectorAll("[data-link]")) {
  const k = el.dataset.link;
  if (k && appLinks[k]) el.href = appLinks[k];
}

for (const el of document.querySelectorAll("[data-build-version]"))
  el.textContent = releaseMeta.version;

for (const el of document.querySelectorAll("[data-min-macos]"))
  el.textContent = releaseMeta.minimumMacOS;

const dmgEl = document.querySelector("[data-dmg-checksum]");
if (dmgEl) dmgEl.textContent = releaseMeta.dmgChecksum;

const appEl = document.querySelector("[data-app-checksum]");
if (appEl) appEl.textContent = releaseMeta.appChecksum;

/* ── theme toggle ─────────────────────────────────────────────── */
const THEME_KEY = "icodex-theme";
const html      = document.documentElement;

const savedTheme = localStorage.getItem(THEME_KEY);
const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
const initial    = savedTheme ?? (systemDark ? "dark" : "light");
html.setAttribute("data-theme", initial);

const toggle = document.getElementById("themeToggle");
if (toggle) {
  toggle.addEventListener("click", () => {
    const next = html.getAttribute("data-theme") === "dark" ? "light" : "dark";
    html.setAttribute("data-theme", next);
    localStorage.setItem(THEME_KEY, next);
  });
}

/* ── feedback form — Supabase edge function ───────────────────── */
const feedbackForm   = document.querySelector("[data-feedback-form]");
const feedbackStatus = document.querySelector("[data-feedback-status]");

if (feedbackForm && feedbackStatus) {
  feedbackForm.addEventListener("submit", async (e) => {
    e.preventDefault();

    if (!supabaseConfig.url || !supabaseConfig.anonKey) {
      feedbackStatus.textContent = "Supabase env vars missing.";
      feedbackStatus.dataset.state = "error";
      return;
    }

    const submitBtn = feedbackForm.querySelector('button[type="submit"], .form-btn');
    const data      = new FormData(feedbackForm);

    const payload = {
      category:     data.get("category")    || null,
      name:         data.get("name")        || null,
      email:        data.get("email")       || null,
      message:      data.get("message"),
      page_context: data.get("pageContext") || "website",
    };

    feedbackStatus.textContent    = "Sending…";
    feedbackStatus.dataset.state  = "pending";
    if (submitBtn) submitBtn.disabled = true;

    try {
      const res = await fetch(`${supabaseConfig.url}/functions/v1/icodex-feedback`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey":        supabaseConfig.anonKey,
          "Authorization": `Bearer ${supabaseConfig.anonKey}`,
        },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.message || err.error || "Could not send.");
      }

      feedbackForm.reset();
      const ctx = feedbackForm.querySelector('input[name="pageContext"]');
      if (ctx) ctx.value = "support-page";

      feedbackStatus.textContent   = "Sent — thanks.";
      feedbackStatus.dataset.state = "success";
    } catch (err) {
      feedbackStatus.textContent   = err instanceof Error ? err.message : "Something went wrong.";
      feedbackStatus.dataset.state = "error";
    } finally {
      if (submitBtn) submitBtn.disabled = false;
    }
  });
}

/* ── reveal on scroll ────────────────────────────────────────── */
const observerOptions = {
  threshold: 0.1,
  rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('active');
    }
  });
}, observerOptions);

document.querySelectorAll('.reveal').forEach(el => observer.observe(el));
